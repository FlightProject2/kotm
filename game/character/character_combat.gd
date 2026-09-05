class_name CharacterCombat
extends Node
## Weapon handling driven by CharacterInput: slot switching, firing (semi/auto/bolt/pump),
## reloads, melee, medical use. Runs on the authority; visuals are updated through Character.

var c: Character
var inv: Inventory
var fire_times: Dictionary = {}   # weapon id -> time of its last shot
var swap_t: float = 0.0            # weapon swap delay remaining
var cycle_t: float = 0.0
var reload_t: float = 0.0
var reloading_id: String = ""
var shot_counter: int = 0
var time: float = 0.0
var last_slot_id: String = "fists"
var melee_def: Dictionary = {}
var spread_cfg: Dictionary = DataLib.movement()["spread"]
var melee_cfg: Dictionary = DataLib.movement()["melee"]
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	c = get_parent() as Character
	inv = c.inventory
	rng.seed = hash(c.name)
	inv.changed.connect(_on_inventory_changed)

func current_def() -> Dictionary:
	return inv.current_def()

func current_is_scoped() -> bool:
	return current_def().has("scope")

func tick(dt: float) -> void:
	time += dt
	var inp := c.input
	if inp.slot >= 0 and inp.slot != inv.cur and inp.slot < inv.slots.size():
		if inv.select(inp.slot):
			reload_t = 0.0
			cycle_t = 0.0
			swap_t = 0.4 if ItemCatalog.get_item(inv.current_id()).get("class", "") == "pistol" else 0.6
	if inp.use_med > 0 and c.prev_input.use_med == 0:
		_use_med("bandage" if inp.use_med == 1 else "first_aid_kit")
	cycle_t = maxf(0.0, cycle_t - dt)
	swap_t = maxf(0.0, swap_t - dt)
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			_finish_reload()
	var def := current_def()
	var id := inv.current_id()
	if def.is_empty():
		return
	var is_melee: bool = ItemCatalog.get_item(id).get("class", "") == "melee"
	if inp.pressed(CharacterInput.B_RELOAD) and not c.prev_input.pressed(CharacterInput.B_RELOAD) and not is_melee:
		start_reload()
	var want_fire := inp.pressed(CharacterInput.B_FIRE)
	var edge := want_fire and not c.prev_input.pressed(CharacterInput.B_FIRE)
	var mode: String = def.get("fireMode", "semi")
	if want_fire and (mode == "auto" or edge or is_melee):
		try_fire(is_melee)

func can_fire() -> bool:
	return c.alive() and c.stun <= 0.0 and c.mode != Character.Mode.PARACHUTE and reload_t <= 0.0 and cycle_t <= 0.0 and swap_t <= 0.0

func try_fire(is_melee: bool) -> bool:
	if not can_fire():
		return false
	var def := current_def()
	var id := inv.current_id()
	var rpm := float(def.get("rpmCap", def.get("rpm", 120)))
	if is_melee:
		rpm = 60.0 / float(def.get("swingSec", 0.5))
	if time - float(fire_times.get(id, -10.0)) < 60.0 / rpm:
		return false
	if is_melee:
		fire_times[id] = time
		_melee(def)
		return true
	if int(inv.mags.get(id, 0)) <= 0:
		if int(inv.ammo.get(def["ammo"], 0)) > 0:
			start_reload()
		return false
	fire_times[id] = time
	inv.mags[id] = int(inv.mags[id]) - 1
	if def.has("boltCycleSec"):
		cycle_t = float(def["boltCycleSec"])
	elif def.has("pumpSec"):
		cycle_t = float(def["pumpSec"])
	shot_counter += 1
	var shot_id := c.character_id * 100000 + shot_counter
	var aiming := c.input.pressed(CharacterInput.B_AIM)
	var moving := Vector2(c.velocity.x, c.velocity.z).length_squared() > 1.0
	var airborne := not c.is_on_floor()
	var spread := float(def["adsSpreadDeg"] if aiming else def["hipSpreadDeg"])
	if c.has_meta("spread_override"):
		spread = float(c.get_meta("spread_override"))   # bots and tests set their own accuracy
	if moving:
		spread *= float(spread_cfg["movingMult"])
	if airborne:
		spread *= float(spread_cfg["airborneMult"])
	var pellets := int(def.get("pellets", 1))
	var origin := muzzle_position()
	var base_dir := c.input.aim_dir.normalized() if c.input.aim_dir.length_squared() > 0.5 else c.forward()
	var ps := ProjectileSystem.instance
	for i in pellets:
		var dir := Ballistics.jitter(base_dir, spread, rng)
		if ps:
			ps.fire(c, origin, dir, def, shot_id, pellets > 1)
	c.fired.emit(float(def.get("recoilVertical", 1.0)), float(def.get("recoilHorizontal", 0.3)) * rng.randf_range(-1.0, 1.0))
	Net.fx_all("gunshot", [origin, id, c.character_id])
	return true

func muzzle_position() -> Vector3:
	var vis: Node = c.get_node_or_null("Visual")
	if vis and vis.get("weapon_holder") != null and vis.weapon_holder.has_weapon_model():
		return vis.weapon_holder.muzzle_global()
	return c.global_position + Vector3(0, c.height() - 0.5, 0) + c.right() * 0.28 + c.forward() * 0.5

func start_reload() -> void:
	var def := current_def()
	var id := inv.current_id()
	if def.is_empty() or reload_t > 0.0 or not def.has("magSize"):
		return
	if int(inv.ammo.get(def["ammo"], 0)) <= 0 or int(inv.mags.get(id, 0)) >= int(def["magSize"]):
		return
	var t := float(def.get("reloadSec", 2.0))
	if def.has("reloadPerShellSec"):
		t = float(def["reloadPerShellSec"]) * (int(def["magSize"]) - int(inv.mags.get(id, 0)))
	if int(inv.mags.get(id, 0)) > 0 and def.has("reloadTacticalSec"):
		t = float(def["reloadTacticalSec"])
	reload_t = t
	reloading_id = id

func _finish_reload() -> void:
	var def: Dictionary = ItemCatalog.weapon_def(reloading_id)
	if def.is_empty():
		return
	var want := int(def["magSize"]) - int(inv.mags.get(reloading_id, 0))
	var take := mini(want, int(inv.ammo.get(def["ammo"], 0)))
	inv.mags[reloading_id] = int(inv.mags.get(reloading_id, 0)) + take
	inv.ammo[def["ammo"]] = int(inv.ammo[def["ammo"]]) - take
	inv.changed.emit()

func _melee(def: Dictionary) -> void:
	var reach := float(def.get("reachM", melee_cfg["reachM"]))
	var f := c.forward()
	var cos_half := cos(deg_to_rad(float(melee_cfg["arcDeg"]) * 0.5))
	for other in get_tree().get_nodes_in_group("characters"):
		var o := other as Character
		if o == c or not o.alive():
			continue
		var rel := o.global_position - c.global_position
		var d := rel.length()
		if d <= reach and rel.normalized().dot(f) >= cos_half:
			var region := "head" if rng.randf() < 0.1 else "upperTorso"
			var r := DamageModel.melee(def, region, o.health)
			o.apply_hit(r, c, def["name"])
			Net.event_to(c.owner_peer_id if not c.is_bot else 1, "hit_confirmed", [r.kind, r.killed]) if c.is_local() else null
			Net.fx_all("hit_fx", [o.global_position + Vector3(0, 1.2, 0), -f, "flesh"])
	if c.visual and c.visual.has_method("play_melee"):
		c.visual.play_melee()

func _use_med(id: String) -> void:
	if int(inv.meds.get(id, 0)) <= 0:
		return
	if c.start_heal(id):
		inv.meds[id] = int(inv.meds[id]) - 1
		inv.changed.emit()

func _on_inventory_changed() -> void:
	var id := inv.current_id()
	if id != last_slot_id:
		last_slot_id = id
		c.show_weapon(id, ItemCatalog.get_item(id).get("class", "melee"))
	if c.is_local():
		Events.inventory_changed.emit(c.character_id)
