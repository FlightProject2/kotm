extends TestCase
## Exercise the imported mechanisms and fitted drivers through the real vehicle runtime.

const VARIANTS := ["pickup_truck", "atv"]
const FILES := {
	"pickup_truck": "res://assets/models/kotm/KOTM_SnowTruck.glb",
	"atv": "res://assets/models/kotm/KOTM_Snowmobile.glb",
}

func _make_vehicle(id: String) -> Vehicle:
	var vehicle := Vehicle.new()
	tree.root.add_child(vehicle)
	vehicle.setup(id, null)
	vehicle.set_physics_process(false)
	return vehicle

func test_imported_parts_and_transparent_truck_windows() -> void:
	for id: String in VARIANTS:
		assert_true(ResourceLoader.exists(FILES[id]), "authored model exists for " + id)
		if not ResourceLoader.exists(FILES[id]):
			continue
		var vehicle := _make_vehicle(id)
		assert_true(vehicle.model.scene_file_path == FILES[id], "runtime uses the authored model")
		assert_true(vehicle.driver_marker != null, "driver seat socket imported")
		for socket in ["HandGrip_L", "HandGrip_R", "FootRest_L", "FootRest_R"]:
			assert_true(vehicle.model.find_child(socket, true, false) is Node3D, "imported contact " + socket)
		var animator: Node3D = vehicle.get("animator")
		assert_true(animator != null, "mechanism animator installed")
		if animator:
			assert_true(animator.get("wheels").size() > 0, "wheel pivots remain separate")
			assert_true(animator.get("steering").size() > 0, "steering pivots remain separate")
			assert_true(animator.get("tracks").size() > 0, "track paths and separate treads imported")
			assert_true(animator.get("body") != null, "suspension body imported")
			if id == "pickup_truck":
				assert_true(animator.get("wipers").size() > 0, "truck wiper pivots imported")
				assert_true(animator.get("doors").size() > 0, "truck door pivots imported")
		if id == "pickup_truck":
			var glass_surfaces := 0
			for node: MeshInstance3D in vehicle.model.find_children("*", "MeshInstance3D", true, false):
				if node.mesh == null:
					continue
				for surface in node.mesh.get_surface_count():
					var material := node.get_active_material(surface) as BaseMaterial3D
					if material == null:
						continue
					var key := (String(node.name) + " " + material.resource_name).to_lower()
					if not key.contains("glass") and not key.contains("window") and not key.contains("windshield"):
						continue
					glass_surfaces += 1
					assert_true(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "truck glass blends alpha")
					assert_between(material.albedo_color.a, 0.01, 0.5, "glass admits a clear view of the driver")
			assert_true(glass_surfaces > 0, "truck has transparent glazing")
		vehicle.queue_free()
		await settle(1)

func test_mechanisms_stop_reverse_and_steer() -> void:
	for id: String in VARIANTS:
		var vehicle := _make_vehicle(id)
		var animator: Node3D = vehicle.get("animator")
		assert_true(animator != null, id + " has animator")
		if animator == null:
			vehicle.queue_free()
			continue
		animator.call("update_motion", 1.0 / 60.0, 0.0, 0.0, false, false)
		var wheels: Array = animator.get("wheels")
		var tracks: Array = animator.get("tracks")
		assert_true(not wheels.is_empty() and not tracks.is_empty(), "moving mechanism geometry is present")
		if wheels.is_empty() or tracks.is_empty():
			vehicle.queue_free()
			continue
		var wheel: Node3D = wheels[0].node
		var tread: Node3D = tracks[0].treads[0].node
		var parked_wheel := wheel.transform
		var parked_tread := tread.transform
		for frame in 12:
			animator.call("update_motion", 1.0 / 60.0, 0.0, 0.0, false, false)
		assert_true(wheel.transform.is_equal_approx(parked_wheel), "parked wheels do not spin")
		assert_true(tread.transform.is_equal_approx(parked_tread), "parked treads do not crawl")
		animator.call("update_motion", 0.1, 1.0, 0.0, true, false)
		assert_false(wheel.transform.is_equal_approx(parked_wheel), "forward travel spins visible wheels")
		assert_true(tread.position.distance_to(parked_tread.origin) > 0.02, "forward travel circulates visible track treads")
		animator.call("update_motion", 0.1, -1.0, 0.0, true, false)
		assert_true(wheel.transform.is_equal_approx(parked_wheel), "equal reverse travel unwinds wheel rotation")
		assert_true(tread.transform.is_equal_approx(parked_tread), "equal reverse travel returns track tread to starting position")
		var steering: Array = animator.get("steering")
		animator.call("update_motion", 0.1, 0.0, 1.0, true, false)
		for part: Dictionary in steering:
			assert_false((part.node as Node3D).transform.is_equal_approx(part.rest), "steering moves " + String(part.node.name))
		animator.call("update_motion", 0.1, 0.0, 0.0, false, false)
		for part: Dictionary in steering:
			assert_true((part.node as Node3D).transform.is_equal_approx(part.rest), "released steering returns to centre")
		var frozen_wheel := wheel.transform
		var frozen_tread := tread.transform
		animator.call("update_motion", 0.1, 8.0, 0.0, true, true)
		assert_true(wheel.transform.is_equal_approx(frozen_wheel), "wrecked wheel animation stops")
		assert_true(tread.transform.is_equal_approx(frozen_tread), "wrecked tread animation stops")
		vehicle.queue_free()
		await settle(1)

func test_truck_wipers_and_entry_door() -> void:
	var vehicle := _make_vehicle("pickup_truck")
	var animator: Node3D = vehicle.get("animator")
	assert_true(animator != null, "truck animator present")
	if animator == null:
		vehicle.queue_free()
		return
	var wipers: Array = animator.get("wipers")
	var doors: Array = animator.get("doors")
	assert_true(not wipers.is_empty() and not doors.is_empty(), "truck has wipers and door")
	animator.call("play_door_cycle")
	animator.call("update_motion", 0.4, 0.0, 0.0, true, false)
	for part: Dictionary in doors:
		assert_false((part.node as Node3D).transform.is_equal_approx(part.rest), "entry opens a hinged door")
	for part: Dictionary in wipers:
		assert_false((part.node as Node3D).transform.is_equal_approx(part.rest), "occupied truck sweeps wipers")
	for frame in 180:
		animator.call("update_motion", 1.0 / 60.0, 0.0, 0.0, false, false)
	for part: Dictionary in doors:
		assert_true((part.node as Node3D).transform.is_equal_approx(part.rest), "door closes after entry")
	for part: Dictionary in wipers:
		assert_true((part.node as Node3D).transform.is_equal_approx(part.rest), "unoccupied wipers park")
	vehicle.queue_free()
	await settle(1)

func test_fitted_drivers_in_both_vehicles() -> void:
	var floor := StaticBody3D.new()
	floor.collision_layer = 1
	floor.position.y = -0.5
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 1, 400)
	shape.shape = box
	floor.add_child(shape)
	await add_to_tree(floor)
	for id: String in VARIANTS:
		var vehicle := _make_vehicle(id)
		var driver: Character = load("res://game/character/character.tscn").instantiate()
		driver.god_mode = true
		await add_to_tree(driver)
		assert_true(driver.enter_vehicle(vehicle), "character enters " + id)
		await settle(24)
		assert_true(driver.visual.visible, "seated character remains visible")
		assert_true(driver.collision.disabled, "driver collision does not fight the vehicle")
		assert_eq(driver.visual.anim.current, vehicle.call("seated_animation"), "vehicle selects its fitted seated clip")
		assert_true(driver.global_position.distance_to(vehicle.seat_global()) < 0.005, "character follows the seat socket")
		await _assert_contacts(driver, id + " idle")
		var start := vehicle.global_position
		var forward := CharacterInput.new()
		forward.move = Vector2(0, 1)
		for frame in 80:
			driver.submit_input(forward)
			await settle(1)
		assert_true(vehicle.global_position.distance_to(start) > 2.0 and vehicle.speed > 3.5, "real character input drives forward with the configured 0-60 acceleration")
		var turn := CharacterInput.new()
		turn.move = Vector2(1, 1)
		turn.yaw = 2.2 # Looking sideways must not turn the seated body away from the controls.
		var initial_yaw := vehicle.rotation.y
		for frame in 24:
			driver.submit_input(turn)
			await settle(1)
		assert_true(absf(wrapf(vehicle.rotation.y - initial_yaw, -PI, PI)) > 0.05, "steering changes the vehicle heading")
		assert_true(driver.global_position.distance_to(vehicle.seat_global()) < 0.005, "seat contact follows suspension during steering")
		await _assert_contacts(driver, id + " full steering")
		var stop := CharacterInput.new()
		stop.set_button(CharacterInput.B_JUMP, true)
		for frame in 90:
			driver.submit_input(stop)
			await settle(1)
		assert_near(vehicle.speed, 0.0, 0.05, "handbrake stops the vehicle")
		var reverse := CharacterInput.new()
		reverse.move = Vector2(0, -1)
		for frame in 60:
			driver.submit_input(reverse)
			await settle(1)
		assert_true(vehicle.speed < -1.0, "real character input drives in reverse")
		await _assert_contacts(driver, id + " reverse")
		driver.submit_input(CharacterInput.new())
		driver.leave_vehicle()
		await settle(3)
		assert_false(driver.in_vehicle(), "character exits " + id)
		assert_false(driver.collision.disabled, "standing collision restored")
		assert_false(driver.visual.anim.current.ends_with("Seated"), "standing animation restored after exit")
		driver.queue_free()
		vehicle.queue_free()
		await settle(1)
	floor.queue_free()
	await settle(1)

func _assert_contacts(driver: Character, context: String) -> void:
	var modifier: SkeletonModifier3D = driver.visual.get("vehicle_contact")
	assert_true(modifier != null, context + " contact modifier exists")
	if modifier == null:
		return
	var samples := {"count": 0, "max_error": 0.0}
	var sockets := {"HandGrip_L": "hand.l", "HandGrip_R": "hand.r", "FootRest_L": "foot.l", "FootRest_R": "foot.r"}
	# Measure the final posed bones when the modifier completes, before the engine restores
	# its animation input pose; ordinary get_bone_global_pose after the frame misses IK.
	modifier.modification_processed.connect(func() -> void:
		var skeleton: Skeleton3D = driver.visual.studio_rig.skeleton
		for socket: String in sockets:
			var marker: Node3D = driver.vehicle.call("contact_marker", socket)
			if marker == null:
				continue
			var bone := skeleton.find_bone(sockets[socket])
			var point := skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin
			samples.max_error = maxf(samples.max_error, point.distance_to(marker.global_position))
			samples.count += 1,
		Object.CONNECT_ONE_SHOT)
	await tree.process_frame
	await tree.process_frame
	assert_eq(samples.count, 4, context + " sampled both wrists and ankles")
	assert_true(samples.max_error < 0.002, "%s contact error %.5f m" % [context, samples.max_error])
	assert_true(int(modifier.get("solve_count")) > 0, context + " contact solver evaluated")
