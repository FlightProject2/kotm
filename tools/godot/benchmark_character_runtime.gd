extends SceneTree
var samples: Array[float] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.look_at_from_position(Vector3(0, 5, -14), Vector3(0, 1, 5))
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	var scene = load("res://game/character/character.tscn")
	var start := Time.get_ticks_usec()
	for i in 30:
		var character = scene.instantiate()
		character.is_bot = true
		character.name = "Benchmark_%d" % i
		character.position = Vector3((i % 6 - 2.5) * 2.2, 0, (i / 6) * 2.5)
		world.add_child(character)
		character.set_physics_process(false)
		character.mode = 0
		character.velocity = Vector3(0, 0, -3.5)
		character.show_weapon("ar15", "rifle")
	var spawn_ms := (Time.get_ticks_usec() - start) / 1000.0
	await process_frame
	world.get_child(2).visual.anim.viewer = camera
	for i in 90:
		await process_frame
	var previous := Time.get_ticks_usec()
	for i in 180:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		previous = now
	samples.sort()
	var total := 0.0
	for value in samples: total += value
	var report := {"characters": 30, "close_range": true, "engine": Engine.get_version_info().string,
		"mean_frame_ms": total / samples.size(), "p95_frame_ms": samples[int(samples.size() * 0.95)],
		"spawn_ms": spawn_ms, "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"rendered_objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"asset_sha256": FileAccess.get_sha256("res://assets/characters/kotm/KOTM_Character.glb")}
	print("CHARACTER_BENCHMARK ", JSON.stringify(report))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/character"))
	FileAccess.open("res://docs/character/benchmark.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	quit()
