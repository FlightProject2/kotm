extends TestCase
## Admin tooling and the hit-reg assist: bots spawn on the ground near a point, bullet trails
## obey the setting, a near miss within the bullet's width still registers, vehicles face -Z.

func test_hit_assist_registers_near_miss() -> void:
	var fl := StaticBody3D.new(); fl.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(200, 1, 200); cs.shape = bs; fl.add_child(cs); fl.position.y = -0.5
	await add_to_tree(fl)
	var ps := ProjectileSystem.new()
	await add_to_tree(ps)
	var shooter: Character = load("res://game/character/character.tscn").instantiate()
	shooter.position = Vector3(0, 0.05, 0)
	await add_to_tree(shooter)
	var target: Character = load("res://game/character/character.tscn").instantiate()
	target.position = Vector3(0, 0.05, -20)
	await add_to_tree(target)
	await settle(30)
	var rig: HitboxRig = target.get_node("Hitboxes")
	await rig.skeleton.skeleton_updated
	# aim 4 cm outside the head sphere: the exact ray misses, the capsule assist should not
	var head_bi := rig.skeleton.find_bone("head")
	var head: Vector3 = rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(head_bi).origin
	var origin := Vector3(0, 1.5, 0)
	var edge := head + Vector3(0.15 + 0.04, 0, 0)
	var def := ItemCatalog.weapon_def("ar15")
	var hp0 := target.health.hp
	ps.fire(shooter, origin, (edge - origin).normalized(), def, 1, false)
	await settle(10)
	assert_true(target.health.hp < hp0 or target.health.helmet_id == "", "near-miss shot registered (hp %.0f -> %.0f)" % [hp0, target.health.hp])
	assert_true(ps.hits >= 1, "projectile counted a hit")
	shooter.queue_free(); target.queue_free(); ps.queue_free(); fl.queue_free()
	await settle(1)

func test_tracer_toggle_and_god_mode() -> void:
	var tr := TracerRenderer.new()
	await add_to_tree(tr)
	Settings.tracers = false
	Events.tracer.emit(1, Vector3.ZERO, Vector3(0, 0, -800), "ar15")
	assert_eq(tr.tracers.size(), 0, "no trail when trails are off")
	Settings.tracers = true
	Events.tracer.emit(1, Vector3.ZERO, Vector3(0, 0, -800), "ar15")
	assert_eq(tr.tracers.size(), 1, "trail when trails are on")
	tr.queue_free()
	var fl := StaticBody3D.new(); fl.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(50, 1, 50); cs.shape = bs; fl.add_child(cs); fl.position.y = -0.5
	await add_to_tree(fl)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.god_mode = true
	ch.take_plain_damage(80.0, null, "test")
	assert_eq(ch.health.hp, 100.0, "god mode ignores damage")
	ch.god_mode = false
	ch.take_plain_damage(30.0, null, "test")
	assert_eq(ch.health.hp, 70.0)
	ch.queue_free(); fl.queue_free()
	await settle(1)

func test_vehicle_faces_forward() -> void:
	var v := Vehicle.new()
	tree.root.add_child(v)
	v.setup("pickup_truck", null)
	await settle(1)
	assert_true(v.model != null, "truck model loaded")
	assert_true(absf(v.model.rotation.y - PI * 0.5) < 0.01, "long axis turned so the nose points -Z")
	assert_true(v.reverse_max <= 5.0, "reverse capped")
	v.queue_free()
	await settle(1)

func test_admin_spawns_bots_on_the_ground() -> void:
	var w: World = load("res://game/world/world.tscn").instantiate()
	await add_to_tree(w)
	w.setup("mesh", null, false)
	var m := Match.new()
	await add_to_tree(m)
	m.world = w
	m.preset = DataLib.preset("slice_2km")
	m.rng_bots.seed = 3
	var centre := Vector3(100, w.height_at(100, 100), 100)
	var made := m.spawn_bots_near(centre, 3)
	await settle(5)
	assert_eq(made.size(), 3)
	for b in made:
		assert_true(b.is_bot and b.alive())
		assert_true(b.mode != Character.Mode.PARACHUTE, "spawned on the ground, not parachuting")
		assert_true(b.global_position.y < w.height_at(b.global_position.x, b.global_position.z) + 1.5, "standing on the terrain")
		assert_true(Vector2(b.global_position.x - centre.x, b.global_position.z - centre.z).length() < 30.0, "within the spawn ring")
	assert_eq(m.alive_count, 3)
	# free the bots here: a later test's bot perceives every character in the tree, and a leftover
	# standing 190 m away is a target it should never have seen
	for b in made:
		b.queue_free()
	m.queue_free(); w.queue_free()
	await tree.process_frame
	await settle(2)
