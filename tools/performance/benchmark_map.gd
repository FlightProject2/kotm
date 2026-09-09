extends Node
var label := "baseline"
var output := ""
var results: Array = []
var world: World
var camera: Camera3D
var sample_frames := 150
var warmup_frames := 45
var resolution := Vector2i(1600, 900)
var with_player := false

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--1080p":
			resolution = Vector2i(1920, 1080)
		if arg == "--with-player":
			with_player = true
		if arg == "--sustained":
			sample_frames = 900
			warmup_frames = 120
		if arg.begins_with("--report="):
			output = arg.substr(9)
		if arg.begins_with("--label="):
			label = arg.substr(8)
	call_deferred("run_benchmark")

func sample(name: String, eye: Vector3, target: Vector3) -> void:
	camera.position = eye
	camera.look_at(target, Vector3.UP)
	for i in warmup_frames:
		await get_tree().process_frame
	var frames: Array[float] = []
	var draws := 0.0
	var primitives := 0.0
	var process_ms := 0.0
	var physics_ms := 0.0
	var render_cpu := 0.0
	var render_gpu := 0.0
	var render_setup := 0.0
	var previous := Time.get_ticks_usec()
	for i in sample_frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - previous) / 1000.0)
		previous = now
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		render_cpu += RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid())
		render_gpu += RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())
		render_setup += RenderingServer.get_frame_setup_time_cpu()
	frames.sort()
	var sum := 0.0
	for value in frames:
		sum += value
	var record = {"view":name,"average_fps":float(sample_frames)*1000.0/sum,"median_ms":frames[int(sample_frames*.5)],"p95_ms":frames[int(sample_frames*.95)],"p99_ms":frames[int(sample_frames*.99)],"slowest_ms":frames[-1],"sample_frames":sample_frames,"draw_calls":draws/sample_frames,"primitives":primitives/sample_frames,"process_ms":process_ms/sample_frames,"physics_ms":physics_ms/sample_frames,"render_cpu_ms":render_cpu/sample_frames,"render_gpu_ms":render_gpu/sample_frames,"render_setup_ms":render_setup/sample_frames,"nodes":get_tree().get_node_count(),"orphans":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)}
	record["actors_alive"] = get_tree().get_nodes_in_group("characters").filter(func(c): return c.alive()).size()
	record["actors_grounded"] = get_tree().get_nodes_in_group("characters").filter(func(c): return c.mode == Character.Mode.GROUND).size()
	results.append(record)
	print("BENCH_VIEW=" + JSON.stringify(record))
	if output != "":
		await RenderingServer.frame_post_draw
		get_tree().root.get_texture().get_image().save_png(output.get_base_dir().path_join(label + "_" + name + ".png"))

func run_benchmark() -> void:
	await get_tree().process_frame
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	get_tree().root.size = resolution
	world = load("res://game/world/world.tscn").instantiate() as World
	get_tree().root.add_child(world)
	var start := Time.get_ticks_msec()
	world.setup("mesh",null,true)
	var build_ms := Time.get_ticks_msec()-start
	camera=Camera3D.new()
	camera.name="BenchmarkCamera"
	camera.near=0.15
	camera.far=3500.0
	camera.fov=66.0
	get_tree().root.add_child(camera)
	camera.make_current()
	var village := Vector2(-560,-300)
	var y := world.height_at(village.x,village.y)

	if "--diagnose" in OS.get_cmdline_user_args():
		var eye := Vector3(-630,y+3.2,-300)
		var target := Vector3(-530,y+3,-300)
		await sample("all",eye,target)
		world.vehicles.process_mode = Node.PROCESS_MODE_DISABLED
		await sample("vehicles_paused",eye,target)
		world.vehicles.visible = false
		await sample("vehicles_hidden",eye,target)
		world.trees.visible = false
		await sample("trees_hidden",eye,target)
		world.get_node("Sun").shadow_enabled = false
		await sample("shadows_off",eye,target)
		world.terrain.visible = false
		await sample("terrain_hidden",eye,target)
		FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"label":label,"samples":results},"\t"))
		get_tree().quit()
		return
	await sample("street_world",Vector3(-630,y+3.2,-300),Vector3(-530,y+3,-300))
	await sample("overview_world",Vector3(1500,1450,1700),Vector3(0,-70,0))
	if "--full-review" in OS.get_cmdline_user_args():
		await sample("freight_world", Vector3(-579,85,-700), Vector3(-648,54,-760))
		await sample("resort_world", Vector3(585,71,612), Vector3(522,35,547))
	var match_node:=Match.new()
	get_tree().root.add_child(match_node)
	match_node.start(487,world,DataLib.preset("slice_2km"),30,with_player)
	await sample("street_match30",Vector3(-630,y+3.2,-300),Vector3(-530,y+3,-300))
	if "--sustained" in OS.get_cmdline_user_args():
		var deadline := Time.get_ticks_msec()+60000
		while Time.get_ticks_msec() < deadline:
			var grounded := 0
			for actor: Character in match_node.characters:
				if actor.mode == Character.Mode.GROUND:
					grounded += 1
			if grounded >= 27:
				break
			await get_tree().physics_frame
		await sample("grounded_match30",Vector3(-630,y+3.2,-300),Vector3(-530,y+3,-300))
	if "--full-review" in OS.get_cmdline_user_args():
		await sample("freight_match30", Vector3(-579,85,-700), Vector3(-648,54,-760))
		await sample("resort_match30", Vector3(585,71,612), Vector3(522,35,547))
	var report={"label":label,"renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"resolution":[resolution.x,resolution.y],"vsync":"disabled","window":"background Windows renderer; not headless","world_build_ms":build_ms,"world_stats":world.build_stats,"samples":results,"bots":30,"additional_player":with_player,"physics_hz":Engine.physics_ticks_per_second}
	if output != "":
		var file:=FileAccess.open(output,FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
	print("BENCH_COMPLETE="+JSON.stringify(report))
	get_tree().quit()
