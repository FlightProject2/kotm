extends TestCase
## AR-15 vs a helmeted dummy at 100 m: helmet pops and 75 hp remain; hunting rifle one-taps
## through a tactical helmet; a shooter never hits its own hitboxes.

var floor_body: StaticBody3D
var ps: ProjectileSystem

func _setup() -> void:
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position.y = -0.5
	await add_to_tree(floor_body)
	ps = ProjectileSystem.new()
	await add_to_tree(ps)
	var tr := TracerRenderer.new()
	tree.root.add_child(tr)
	var fx := HitFx.new()
	tree.root.add_child(fx)

func _spawn(pos: Vector3, yaw: float, bot: bool) -> Character:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.position = pos
	ch.is_bot = bot
	ch.character_id = randi() % 1000 + 1
	tree.root.add_child(ch)
	ch.yaw = yaw
	return ch

func _head_pos(ch: Character) -> Vector3:
	var rig: HitboxRig = ch.get_node("Hitboxes")
	return rig.areas[0].global_position

func _fire_at(shooter: Character, target_point: Vector3, def: Dictionary) -> void:
	var muzzle := shooter.combat.muzzle_position()
	var aim := target_point
	aim.y += Ballistics.drop_at(muzzle.distance_to(target_point), def)
	var dir := (aim - muzzle).normalized()
	for i in 3:
		var inp := CharacterInput.new()
		inp.yaw = shooter.yaw
		inp.aim_dir = dir
		inp.set_button(CharacterInput.B_FIRE, i == 1)
		shooter.submit_input(inp)
		await tree.physics_frame
	for i in 30:
		var inp := CharacterInput.new()
		inp.yaw = shooter.yaw
		inp.aim_dir = dir
		shooter.submit_input(inp)
		await tree.physics_frame

func test_helmet_pop_at_100m_and_pierce() -> void:
	await _setup()
	var shooter := _spawn(Vector3(0, 0.05, 0), 0.0, false)          # faces -Z
	shooter.set_meta("spread_override", 0.0)
	var dummy := _spawn(Vector3(0, 0.05, -100), PI, true)
	await settle(30)
	shooter.inventory.give_weapon("ar15")
	shooter.inventory.give_ammo("223", 60)
	await settle(2)
	assert_eq(shooter.inventory.current_id(), "ar15")
	dummy.health.set_helmet("tactical_helmet")
	var hits := []
	Events.hit_confirmed.connect(func(kind: String, killed: bool) -> void: hits.append([kind, killed]))
	shooter.owner_peer_id = 1
	await _fire_at(shooter, _head_pos(dummy), ItemCatalog.weapon_def("ar15"))
	assert_true(ps.shots_fired >= 1, "a shot was fired")
	assert_near(dummy.health.hp, 75.0, 0.01, "tactical helmet leaves 75 hp (hp %.1f, hits %s)" % [dummy.health.hp, ps.hits])
	assert_false(dummy.health.has_helmet(), "helmet popped")
	assert_true(dummy.alive())
	assert_eq(shooter.inventory.mags["ar15"], 29, "one round left the magazine")
	assert_near(shooter.health.hp, 100.0, 0.001, "shooter never hits itself")
	assert_true(hits.size() >= 1 and hits[0][0] == DamageModel.KIND_HELMET_POP, "shooter got a helmet-pop hitmarker")
	# hunting rifle through a fresh tactical helmet
	dummy.health.set_helmet("tactical_helmet")
	shooter.inventory.give_weapon("hunting_rifle")
	shooter.inventory.give_ammo("308", 10)
	var sel := CharacterInput.new()
	sel.slot = 2
	shooter.submit_input(sel)
	await settle(45)
	assert_eq(shooter.inventory.current_id(), "hunting_rifle")
	await _fire_at(shooter, _head_pos(dummy), ItemCatalog.weapon_def("hunting_rifle"))
	assert_false(dummy.alive(), "hunting rifle one-taps through a tactical helmet (hp %.1f)" % dummy.health.hp)
	assert_true(dummy.last_hit_by == shooter, "kill credited to the shooter")
	shooter.queue_free(); dummy.queue_free(); floor_body.queue_free(); ps.queue_free()
	await settle(1)

func test_reload_and_fire_rate() -> void:
	await _setup()
	var shooter := _spawn(Vector3(20, 0.05, 20), 0.0, false)
	await settle(10)
	shooter.inventory.give_weapon("m9")
	shooter.inventory.give_ammo("9mm", 30)
	shooter.inventory.mags["m9"] = 2
	await settle(1)
	# hold fire for a second: semi-auto fires once per press, so only one shot
	for i in 60:
		var inp := CharacterInput.new()
		inp.set_button(CharacterInput.B_FIRE, true)
		inp.aim_dir = Vector3(0, 0, -1)
		shooter.submit_input(inp)
		await tree.physics_frame
	assert_eq(shooter.inventory.mags["m9"], 1, "semi-auto fires once per press")
	# reload
	var inp := CharacterInput.new()
	inp.set_button(CharacterInput.B_RELOAD, true)
	shooter.submit_input(inp)
	await tree.physics_frame
	shooter.submit_input(CharacterInput.new())
	await tree.physics_frame
	assert_true(shooter.combat.reload_t > 0.0, "reloading")
	for i in 130:
		await tree.physics_frame
	assert_eq(shooter.inventory.mags["m9"], 15, "magazine refilled")
	assert_eq(shooter.inventory.ammo["9mm"], 16, "reserve reduced by the rounds loaded")
	shooter.queue_free(); floor_body.queue_free(); ps.queue_free()
	await settle(1)
