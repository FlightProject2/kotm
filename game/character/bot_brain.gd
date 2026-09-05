class_name BotBrain
extends Node
## Server-side AI producing CharacterInput (port of the prototype's botThink): parachute,
## perception with line of sight, lead + drop compensated aim, strafing fights, reload/swap,
## looting inside the next circle, wandering, healing, moving to the zone, stuck detours.

var c: Character
var rng: RandomNumberGenerator
var t: float = 0.0
var state: String = "chute"
var target: Character
var look_t: float = 0.0
var react: float = 1.0
var spread: float = 4.0
var goal: Vector2 = Vector2.ZERO
var goal_t: float = 0.0
var item: LootRegistry.Entry
var stuck_t: float = 0.0
var detour_t: float = 0.0
var detour_side: float = 1.0
var fire_toggle: bool = false
var crouch: bool = false
var strafe_phase: float = 0.0
var zone: Zone
var _prev_pos: Vector3 = Vector3.ZERO

const PERCEPTION_RANGE := 140.0
const MELEE_SEARCH := 6.0
const LOOT_SEARCH := 90.0
const WANDER := 40.0

func _ready() -> void:
	process_physics_priority = -1
	c = get_parent() as Character
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = hash(c.name)
	react = rng.randf_range(0.3, 1.2)
	spread = rng.randf_range(2.5, 6.0)
	look_t = rng.randf() * 0.35
	strafe_phase = rng.randf() * TAU
	c.set_meta("spread_override", spread)

func _physics_process(dt: float) -> void:
	if not multiplayer.is_server() or c == null or not c.alive():
		return
	if zone == null:
		zone = get_tree().get_first_node_in_group("zone") as Zone
	t += dt
	var i := CharacterInput.new()
	i.yaw = c.yaw
	i.pitch = 0.0
	i.aim_dir = c.forward()
	if c.mode == Character.Mode.PARACHUTE:
		i.move = Vector2(0, 1.0 if t > 3.0 else 0.0)
		c.submit_input(i)
		return
	_think(dt, i)
	i.yaw = c.yaw
	i.set_button(CharacterInput.B_CROUCH, crouch)
	c.submit_input(i)

func _turn_towards(want_yaw: float, rate: float, dt: float) -> float:
	var dy := wrapf(want_yaw - c.yaw, -PI, PI)
	c.yaw += clampf(dy, -rate * dt, rate * dt)
	return dy

func _think(dt: float, i: CharacterInput) -> void:
	var pos := c.global_position
	var weapon_id := c.inventory.current_id()
	var def := c.combat.current_def()
	var is_melee: bool = ItemCatalog.get_item(weapon_id).get("class", "") == "melee"
	# perception
	look_t -= dt
	if look_t <= 0.0:
		look_t = 0.35
		_perceive(is_melee)
	if target and (not is_instance_valid(target) or not target.alive()):
		target = null
	if target and not is_melee:
		_combat(dt, i, def)
		return
	if target and is_melee:
		var rel := target.global_position - pos
		_turn_towards(atan2(-rel.x, -rel.z), 6.0, dt)
		i.move = Vector2(0, 1)
		i.set_button(CharacterInput.B_SPRINT, true)
		if rel.length() < 1.8:
			fire_toggle = not fire_toggle
			i.set_button(CharacterInput.B_FIRE, fire_toggle)
		return
	# heal when safe
	if c.health.hp < 60.0 and c.heal_timer <= 0.0 and c.heal_amount <= 0.0:
		if c.health.hp < 45.0 and int(c.inventory.meds.get("first_aid_kit", 0)) > 0:
			i.use_med = 2
		elif int(c.inventory.meds.get("bandage", 0)) > 0:
			i.use_med = 1
	# decide where to go
	goal_t -= dt
	var outside_next := false
	var in_gas := false
	if zone and zone.phase >= 0:
		outside_next = zone.distance_to_next_edge(pos) > -10.0
		in_gas = zone.is_outside(pos)
	if goal_t <= 0.0 or (outside_next and state != "zone"):
		_pick_goal(pos, outside_next or in_gas)
	var d2 := Vector2(goal.x - pos.x, goal.y - pos.z)
	var d := d2.length()
	if d > 1.2:
		_turn_towards(atan2(-d2.x, -d2.y), 3.0, dt)
		i.move = Vector2(0, 1)
		i.set_button(CharacterInput.B_SPRINT, state == "zone" or d > 20.0)
	else:
		goal_t = 0.0
		if item != null and c.world and c.world.loot_registry.entries.has(item.id):
			c.interaction.take(item)
		item = null
	crouch = false
	_stuck_check(dt, i, pos)

func _perceive(is_melee: bool) -> void:
	var best: Character = null
	var bd := MELEE_SEARCH if is_melee else PERCEPTION_RANGE
	var eye := c.eye_position()
	var space := c.get_world_3d().direct_space_state
	for other in get_tree().get_nodes_in_group("characters"):
		var o := other as Character
		if o == null or o == c or not o.alive():
			continue
		var d := o.global_position.distance_to(c.global_position)
		if d >= bd:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, o.eye_position(), 1)
		if not space.intersect_ray(q).is_empty():
			continue
		if c.world and c.world.height_field.segment_hit(eye, o.eye_position(), 2.0) >= 0.0:
			continue
		bd = d
		best = o
	if best != target:
		react = rng.randf_range(0.3, 1.2)
	target = best

func _combat(dt: float, i: CharacterInput, def: Dictionary) -> void:
	var pos := c.global_position
	var tp := target.global_position + Vector3(0, target.height() * 0.75, 0)
	var rel := tp - pos
	var d := rel.length()
	var dy := _turn_towards(atan2(-rel.x, -rel.z), 4.0, dt)
	var weapon_id := c.inventory.current_id()
	var mag := int(c.inventory.mags.get(weapon_id, 0))
	if mag <= 0:
		if int(c.inventory.ammo.get(def.get("ammo", ""), 0)) > 0:
			fire_toggle = not fire_toggle
			i.set_button(CharacterInput.B_RELOAD, fire_toggle)
		else:
			for s in range(1, 5):
				var sid: String = c.inventory.slots[s]
				if sid != "" and int(c.inventory.mags.get(sid, 0)) > 0:
					i.slot = s
					break
	react -= dt
	if react <= 0.0 and absf(dy) < 0.15 and mag > 0:
		var aim := Ballistics.lead_point(c.combat.muzzle_position(), tp, target.velocity, def)
		var dir := (aim - c.combat.muzzle_position()).normalized()
		i.aim_dir = dir
		i.pitch = asin(clampf(dir.y, -1.0, 1.0))
		if rng.randf() < 0.85:
			fire_toggle = not fire_toggle
			i.set_button(CharacterInput.B_FIRE, fire_toggle if String(def.get("fireMode", "semi")) != "auto" else true)
	# movement in a fight
	strafe_phase += dt * 1.7
	i.move.x = 1.0 if sin(strafe_phase) > 0.0 else -1.0
	if d > 60.0:
		i.move.y = 1.0
	elif d < 25.0 and String(def.get("id", "")) != "shotgun_12g":
		i.move.y = -1.0
	if d < 12.0 and rng.randf() < 0.02:
		i.set_button(CharacterInput.B_JUMP, true)
	if rng.randf() < 0.01:
		crouch = not crouch
	if d > 25.0:
		crouch = false
	if target.global_position.y - pos.y > 3.0 and rng.randf() < 0.05:
		i.set_button(CharacterInput.B_JUMP, true)

func _pick_goal(pos: Vector3, need_zone: bool) -> void:
	goal_t = 8.0
	item = null
	if need_zone and zone:
		state = "zone"
		var a := rng.randf() * TAU
		var r := rng.randf() * zone.next_radius * 0.6
		goal = zone.next_center + Vector2(cos(a) * r, sin(a) * r)
		return
	state = "goto"
	var reg: LootRegistry = c.world.loot_registry if c.world else null
	if reg:
		var have_guns := 0
		for s in range(1, 5):
			if c.inventory.slots[s] != "":
				have_guns += 1
		var best: LootRegistry.Entry = null
		var bd := LOOT_SEARCH
		for e in reg.in_radius(pos, LOOT_SEARCH):
			if not _wants(e.item, have_guns):
				continue
			if zone and zone.phase >= 0 and Vector2(e.pos.x, e.pos.z).distance_to(zone.next_center) > zone.next_radius:
				continue
			var d := Vector2(e.pos.x - pos.x, e.pos.z - pos.z).length()
			if d < bd:
				bd = d
				best = e
		if best:
			item = best
			goal = Vector2(best.pos.x, best.pos.z)
			return
	var a := rng.randf() * TAU
	var half := (c.world.half_size() - 30.0) if c.world else 500.0
	goal = Vector2(clampf(pos.x + cos(a) * WANDER, -half, half), clampf(pos.z + sin(a) * WANDER, -half, half))

func _wants(it: Dictionary, have_guns: int) -> bool:
	match it["kind"]:
		"weapon":
			var cls: String = ItemCatalog.get_item(it["id"]).get("class", "")
			return cls != "melee" and have_guns < 2 and not c.inventory.has_weapon(it["id"])
		"helmet": return not c.health.has_helmet()
		"armor": return not c.health.has_armor()
		"ammo":
			for s in c.inventory.slots:
				if s != "" and ItemCatalog.weapon_def(s).get("ammo", "") == it["id"]:
					return true
			return false
		"med": return true
		"bag": return true
	return false

func _stuck_check(dt: float, i: CharacterInput, pos: Vector3) -> void:
	if detour_t > 0.0:
		detour_t -= dt
		i.move = Vector2(detour_side, 0.6)
		return
	if i.move.length_squared() > 0.1 and pos.distance_to(_prev_pos) < 0.02:
		stuck_t += dt
		if stuck_t > 1.0:
			stuck_t = 0.0
			detour_t = 1.5
			detour_side = 1.0 if rng.randf() < 0.5 else -1.0
			i.set_button(CharacterInput.B_JUMP, true)
	else:
		stuck_t = 0.0
	_prev_pos = pos
