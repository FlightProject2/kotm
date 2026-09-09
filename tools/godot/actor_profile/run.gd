extends SceneTree
const PROFILE = preload("res://tools/godot/actor_profile/metrics.gd")
var world
var match_node
var results: Array = []
var destination := ""

func _initialize() -> void:
	call_deferred("run")

func sample(label: String, frame_count := 180) -> void:
	PROFILE.reset()
	var physics_ms := 0.0
	var process_ms := 0.0
	var active_objects := 0.0
	var collision_pairs := 0.0
	var islands := 0.0
	var mode_counts := {}
	for i in frame_count:
		await physics_frame
		physics_ms += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		active_objects += Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)
		collision_pairs += Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)
		islands += Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)
	for ch in match_node.characters:
		var mode_name: String = ["GROUND", "AIR", "PARACHUTE", "LANDING"][ch.mode]
		mode_counts[mode_name] = int(mode_counts.get(mode_name, 0)) + 1
	var record := {"phase": label, "frames": frame_count, "bots": match_node.characters.size(), "alive": match_node.alive_characters().size(), "modes": mode_counts, "physics_ms": physics_ms / frame_count, "process_ms": process_ms / frame_count, "timings_inclusive": PROFILE.report(frame_count)}
	record["native_physics"] = {"active_objects": active_objects / frame_count, "collision_pairs": collision_pairs / frame_count, "islands": islands / frame_count}
	results.append(record)
	print("ACTOR_CPU_PHASE=" + JSON.stringify(record))

func run() -> void:
	if not "--profile-actor-cpu" in OS.get_cmdline_user_args():
		push_error("Explicit --profile-actor-cpu required")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			destination = arg.substr(9)
	Engine.max_fps = 60
	await process_frame
	world = load("res://game/world/world.tscn").instantiate()
	root.add_child(world)
	world.setup("mesh", null, true)
	match_node = load("res://tools/godot/actor_profile/match.gd").new()
	root.add_child(match_node)
	match_node.start(487, world, DataLib.preset("slice_2km"), 30, false)
	for warmup in 15:
		await physics_frame
	await sample("initial_drop")
	# Let the exact spawned bots land naturally; no extra movement/AI ticks or teleport.
	for frame in 3600:
		var parachuting := false
		for ch in match_node.characters:
			parachuting = parachuting or ch.mode == 2
		if not parachuting:
			break
		await physics_frame
	await sample("grounded", 360)
	var report := {"seed": 487, "bots": 30, "renderer": "headless", "physics_hz": Engine.physics_ticks_per_second, "note": "Profiler subclasses only; nested timings are inclusive and must not be added together. No gameplay scripts instrumented, no AI cadence/RNG/combat/pose changes. Ground sample follows natural landings.", "samples": results}
	if destination != "":
		var file := FileAccess.open(destination, FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "\t"))
	print("ACTOR_CPU_COMPLETE=" + JSON.stringify(report))
	quit()
