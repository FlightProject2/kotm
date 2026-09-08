extends TestCase

func test_hitboxes_move_even_when_animation_is_frozen() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.visual.anim.set_process(false)
	ch.visual.anim.player.pause()
	var hitboxes: HitboxRig = ch.get_node("Hitboxes")
	var before := hitboxes.head_world()
	ch.position += Vector3(8, 0, 2)
	assert_true((hitboxes.head_world() - before).is_equal_approx(Vector3(8, 0, 2)), "collision follows body translation without a skeleton update")
	ch.queue_free()
	await settle(1)

func test_sneaker_pickup_changes_gameplay_and_visible_outfit() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	assert_false(ch.health.has_running_shoes(), "fresh spawn has no sneaker buff")
	ch.motor.stamina.exhausted = true
	ch.motor.stamina.value = 0
	ch.interaction._apply({"kind": "shoes", "id": "running_shoes"}, Vector3.ZERO)
	await settle(2)
	assert_true(ch.health.has_running_shoes())
	assert_false(ch.motor.stamina.exhausted)
	assert_true(ch.visual.studio_rig.worn_shoes)
	assert_true(ch.visual.studio_rig.roots["Sneakers"].visible)
	ch.queue_free()
	await settle(1)

func test_vehicle_keeps_momentum_on_exit_but_braked_vehicle_stays_parked() -> void:
	var vehicle := Vehicle.new()
	tree.root.add_child(vehicle)
	vehicle.setup("pickup_truck", null)
	vehicle.set_physics_process(false)
	vehicle.speed = 10.0
	vehicle.exit()
	assert_near(vehicle.speed, 10.0)
	for i in 60:
		vehicle._coast(1.0 / 60.0)
		await settle(1)
	assert_between(vehicle.speed, 8.5, 9.5, "gentle rolling resistance")
	vehicle.speed = 0.0
	vehicle.exit()
	vehicle._coast(1.0)
	assert_near(vehicle.speed, 0.0, 0.001)
	vehicle.queue_free()
	await settle(1)

func test_truck_head_is_above_window_and_windows_are_shootable() -> void:
	var vehicle := Vehicle.new()
	tree.root.add_child(vehicle)
	vehicle.setup("pickup_truck", null)
	vehicle.set_physics_process(false)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.enter_vehicle(vehicle)
	await settle(12)
	var rig: HitboxRig = ch.get_node("Hitboxes")
	var head := rig.head_world()
	assert_between(head.y, 1.85, 2.0, "head centre is visible above the 1.55 m window sill")
	var query := PhysicsRayQueryParameters3D.create(Vector3(-4, head.y, head.z), head, 4 | 32)
	query.collide_with_areas = true
	var hit := tree.root.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "side-window ray has a target")
	if not hit.is_empty():
		assert_true(HitboxRig.character_of(hit.collider) == ch, "glass does not grant immunity")
	query = PhysicsRayQueryParameters3D.create(Vector3(-4, 1.0, 0.0), Vector3(0, 1.0, 0.0), 32)
	hit = tree.root.get_world_3d().direct_space_state.intersect_ray(query)
	assert_false(hit.is_empty(), "opaque lower door still stops bullets")
	ch.queue_free(); vehicle.queue_free()
	await settle(1)

func test_ar_timed_taps_recover_accuracy_and_drop_increases_with_range() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.inventory.give_weapon("ar15")
	ch.input.aim_dir = Vector3.FORWARD
	assert_true(ch.combat.try_fire(false))
	var first := ch.combat.bloom
	ch.combat.tick(0.1)
	assert_true(ch.combat.try_fire(false))
	assert_true(ch.combat.bloom > first, "rapid fire widens dispersion")
	ch.combat.tick(1.0)
	assert_near(ch.combat.bloom, 0.0, 0.00001, "pausing restores accurate taps")
	var ar := ItemCatalog.weapon_def("ar15")
	assert_between(Ballistics.drop_at(100, ar), 0.26, 0.28)
	assert_between(Ballistics.drop_at(200, ar), 1.06, 1.09)
	ch.queue_free()
	await settle(1)

func test_authoritative_impact_stops_only_its_matching_tracer() -> void:
	var renderer := TracerRenderer.new()
	await add_to_tree(renderer)
	renderer.set_process(false)
	Settings.tracers = true
	Events.projectile_tracer.emit(991, 2, Vector3.ZERO, Vector3.FORWARD * 620, "ar15")
	Events.projectile_tracer.emit(992, 2, Vector3.ZERO, Vector3.FORWARD * 620, "ar15")
	Events.projectile_impact.emit(991, Vector3(0, 0, -4))
	assert_true(renderer.tracers[0].stopped)
	assert_eq(renderer.tracers[0].pos, Vector3(0, 0, -4))
	assert_false(renderer.tracers[1].stopped)
	renderer.queue_free()
	await settle(1)

func test_clipped_muzzle_hits_cover_instead_of_firing_through_it() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.inventory.give_weapon("ar15")
	ch.input.aim_dir = Vector3.FORWARD
	await settle(5)
	var muzzle := ch.combat.muzzle_position()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 0.08
	shape.shape = box
	wall.add_child(shape)
	wall.position = ch.eye_position().lerp(muzzle, 0.5)
	await add_to_tree(wall)
	var ps := ProjectileSystem.new()
	await add_to_tree(ps)
	ps.set_physics_process(false)
	assert_true(ch.combat.try_fire(false))
	assert_eq(ps.projectiles.size(), 1)
	assert_false(ps.projectiles[0].alive, "obstructed barrel cannot spawn a live round beyond cover")
	assert_true(ps.projectiles[0].pos.distance_to(wall.position) < 0.08)
	ps.queue_free(); wall.queue_free(); ch.queue_free()
	await settle(1)
