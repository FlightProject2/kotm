extends SceneTree
## Capture nine review views and the layout plan from the real World. Requires a graphics driver.
## godot --path . --fixed-fps 60 --resolution 1600x1000 --script res://tools/godot/capture_snow_map.gd -- --output=/absolute/output

func _initialize() -> void:
	_capture()

func _capture() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		push_error("Map captures require a graphics driver; omit --headless.")
		quit(1)
		return
	var output := "res://docs/map/captures"
	var only_view := -1
	var first_view := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.substr(9)
		elif argument.begins_with("--view="):
			only_view = maxi(argument.substr(7).to_int() - 1, 0)
		elif argument.begins_with("--from-view="):
			first_view = maxi(argument.substr(12).to_int() - 1, 0)
	output = ProjectSettings.globalize_path(output)
	var error := DirAccess.make_dir_recursive_absolute(output)
	if error != OK:
		push_error("Cannot create map capture directory: " + output)
		quit(1)
		return
	var scene := load("res://game/dev/snow_map_tour.tscn") as PackedScene
	if scene == null:
		push_error("Cannot load the snow map tour scene.")
		quit(1)
		return
	var tour: Node3D = scene.instantiate()
	root.add_child(tour)
	tour.call("set_hud_visible", false)
	tour.set_process(false)
	tour.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var names: PackedStringArray = tour.call("get_view_files")
	for index in names.size():
		if index < first_view:
			continue
		if only_view != -1 and index != only_view:
			continue
		tour.call("select_view", index)
		# Allow newly visible shaders, shadows and material pipelines to settle.
		for frame in 90:
			await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		if capture == null or capture.is_empty():
			push_error("Viewport returned no rendered map image.")
			await _finish(tour, 1)
			return
		var path := output.path_join(names[index] + ".png")
		var result := capture.save_png(path)
		if result != OK:
			push_error("Cannot save map capture: " + path)
			await _finish(tour, 1)
			return
		print("SNOW_MAP_CAPTURE " + path)
	if only_view == -1 and first_view == 0:
		tour.call("set_tactical_view", true)
		for frame in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var plan := root.get_texture().get_image()
		var plan_path := output.path_join("00-layout-plan.png")
		if plan.save_png(plan_path) != OK:
			push_error("Cannot save layout plan: " + plan_path)
			await _finish(tour, 1)
			return
		print("SNOW_MAP_CAPTURE " + plan_path)
	await _finish(tour, 0)

func _finish(tour: Node, code: int) -> void:
	tour.queue_free()
	await process_frame
	quit(code)
