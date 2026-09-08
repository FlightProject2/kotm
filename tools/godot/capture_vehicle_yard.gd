extends SceneTree
## Render review images from the real game scene; needs a graphics driver, not --headless.
## godot --path . --fixed-fps 60 --resolution 1600x1000 --script res://tools/godot/capture_vehicle_yard.gd -- --output=/absolute/output

func _initialize() -> void:
	_capture()

func _capture() -> void:
	await process_frame
	var output := "res://docs/vehicles"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.substr(9)
	output = ProjectSettings.globalize_path(output)
	var error := DirAccess.make_dir_recursive_absolute(output)
	if error != OK:
		push_error("Cannot create capture directory: " + output)
		quit(1)
		return
	var yard: Node3D = load("res://game/dev/vehicle_test_yard.tscn").instantiate()
	root.add_child(yard)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for node in yard.get_children():
		if node is CanvasLayer:
			node.visible = false
		elif node is Label3D:
			node.visible = false
	yard.set_process(false)
	yard.set_process_unhandled_input(false)
	yard.input_source.set_physics_process(false)
	yard.camera_rig.set_process(false)
	yard.camera_rig.set_process_unhandled_input(false)
	for driver: Character in yard.drivers:
		driver.set_physics_process(false)
	for vehicle: Vehicle in yard.vehicles:
		vehicle.set_physics_process(false)
	var camera: Camera3D = yard.inspection_camera
	camera.fov = 42
	camera.make_current()
	# Side fill keeps the truck occupant readable through physically transparent glazing.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 135, 0)
	fill.light_energy = 0.65
	yard.add_child(fill)
	var views := [
		{"index": 0, "name": "snow-truck-front", "offset": Vector3(-5.7, 3.4, -7.4), "target": Vector3(0, 1.3, -0.15), "steer": 0.0},
		{"index": 0, "name": "snow-truck-cab-side", "offset": Vector3(-5.8, 2.65, -1.8), "target": Vector3(-0.25, 1.45, -0.35), "steer": 0.0},
		{"index": 1, "name": "snowmobile-quarter", "offset": Vector3(-4.7, 2.9, -5.0), "target": Vector3(0, 0.95, 0), "steer": 0.0},
		{"index": 1, "name": "snowmobile-steering", "offset": Vector3(-4.5, 2.8, -4.7), "target": Vector3(0, 1.0, -0.1), "steer": 1.0},
	]
	for view: Dictionary in views:
		for index in yard.vehicles.size():
			yard.vehicles[index].visible = index == int(view.index)
			yard.drivers[index].visible = index == int(view.index)
		var vehicle: Vehicle = yard.vehicles[int(view.index)]
		vehicle.speed = 0.0
		vehicle.steer = float(view.steer)
		camera.global_position = vehicle.global_transform * Vector3(view.offset)
		camera.look_at(vehicle.global_transform * Vector3(view.target), Vector3.UP)
		for frame in 150:
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		if capture == null or capture.is_empty():
			push_error("Viewport returned no rendered image; run with a graphics driver.")
			quit(1)
			return
		var path: String = output.path_join(String(view.name) + ".png")
		var result := capture.save_png(path)
		if result != OK:
			push_error("Cannot save capture: " + path)
			quit(1)
			return
		print("VEHICLE_CAPTURE " + path)
	quit(0)
