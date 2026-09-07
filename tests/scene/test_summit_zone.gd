extends TestCase

func _zone(whiteout := true) -> SummitZone:
	var zone := SummitZone.new()
	await add_to_tree(zone)
	var random := RandomNumberGenerator.new()
	random.seed = 7
	var schedule: Dictionary = DataLib.preset("slice_2km")["zone"].duplicate(true)
	if not whiteout:
		schedule.erase("theme")
		schedule.erase("summitFinish")
		schedule.erase("endgameCenterM")
	zone.start(schedule, 1000.0, 67.0, random,
		func() -> Array: return [], func(_x: float, _z: float) -> float: return 150.0)
	zone.set_process(false)
	return zone

func test_whiteout_timeline_finishes_on_summit() -> void:
	var zone: SummitZone = await _zone()
	assert_true(zone.is_whiteout())
	assert_true(zone.has_summit_finish())
	var previous := zone.center
	var previous_radius := zone.radius
	for step in 5000:
		zone.advance(0.1)
		assert_true(zone.center.distance_to(previous) + zone.radius <= previous_radius + 0.01, "live interpolated circle remains nested")
		assert_true(zone.center.distance_to(zone.summit_target()) <= zone.radius + 0.01)
		previous = zone.center
		previous_radius = zone.radius
		if zone.state == "done":
			break
	assert_eq(zone.state, "done")
	assert_near(zone.radius, 0.0)
	assert_true(zone.center.is_equal_approx(zone.summit_target()))
	assert_true(zone.is_outside(Vector3(0, 150, 0)), "no invulnerable exact-centre point after collapse")
	zone.queue_free()
	await settle(1)

func test_exposure_is_smooth_and_independent_of_altitude() -> void:
	var zone: SummitZone = await _zone()
	assert_near(zone.exposure_at(Vector3(1000, 0, 1000)), 0.0, 0.001, "no storm before reveal")
	zone.phase = 0
	zone.radius = 100.0
	assert_near(zone.exposure_at(Vector3.ZERO), 0.0)
	assert_between(zone.exposure_at(Vector3(100, 0, 0)), 0.001, 0.99)
	assert_near(zone.exposure_at(Vector3(200, 0, 0)), 1.0)
	assert_near(zone.exposure_at(Vector3(120, 500, 0)), zone.exposure_at(Vector3(120, 0, 0)))
	assert_false(zone.is_outside(Vector3(99, 0, 0)))
	assert_true(zone.is_outside(Vector3(101, 0, 0)))
	zone.queue_free()
	await settle(1)

func test_legacy_preset_keeps_gas_behavior() -> void:
	var zone: SummitZone = await _zone(false)
	assert_false(zone.is_whiteout())
	assert_false(zone.has_summit_finish())
	assert_eq(zone.wall.name, "GasWall")
	zone.phase = 0
	zone.radius = 100.0
	assert_near(zone.exposure_at(Vector3(500, 0, 0)), 0.0)
	assert_true(zone.is_outside(Vector3(500, 0, 0)))
	zone.queue_free()
	await settle(1)

func test_invalid_summit_target_falls_back_to_legacy_circle_selection() -> void:
	var zone: SummitZone = await _zone()
	zone.schedule["endgameCenterM"] = [950.0, 950.0]
	assert_false(zone.has_summit_finish())
	zone._pick_first_circle()
	assert_true(zone._fits(zone.next_center, zone.next_radius))
	zone.queue_free()
	await settle(1)

func test_whiteout_material_and_tall_wall() -> void:
	var zone: SummitZone = await _zone()
	assert_eq(zone.wall.name, "WhiteoutWall")
	assert_eq((zone.wall.material_override as ShaderMaterial).shader.resource_path, "res://game/match/whiteout_wall.gdshader")
	assert_near((zone.wall.mesh as CylinderMesh).height, 900.0)
	zone._update_visuals()
	assert_near(zone.wall.position.y, 225.0)
	zone.queue_free()
	await settle(1)

func test_whiteout_damage_catches_up_whole_seconds() -> void:
	var zone: SummitZone = await _zone()
	var scene: PackedScene = load("res://game/character/character.tscn")
	var inside: Character = scene.instantiate()
	var outside: Character = scene.instantiate()
	tree.root.add_child(inside)
	tree.root.add_child(outside)
	inside.set_physics_process(false)
	outside.set_physics_process(false)
	inside.global_position = Vector3.ZERO
	outside.global_position = Vector3(300, 0, 0)
	var characters: Array = [inside, outside]
	zone._get_characters = func() -> Array: return characters
	zone.phase = 0
	zone.state = "close"
	zone.radius = 100.0
	zone.dps = 2.0
	zone._damage_tick(3.25)
	assert_near(inside.health.hp, 100.0)
	assert_near(outside.health.hp, 94.0)
	assert_near(zone._tick, 0.25)
	zone._damage_tick(0.75)
	assert_near(outside.health.hp, 92.0)
	zone.state = "done"
	zone.radius = 0.0
	zone._damage_tick(1.0)
	assert_near(inside.health.hp, 98.0, 0.001, "final collapse damages exact centre")
	inside.queue_free()
	outside.queue_free()
	zone.queue_free()
	await settle(1)
