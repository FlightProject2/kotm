extends Node
## Compare the previous exact animator with the new path using the real imported pivots.
func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var previous_path := ProjectSettings.globalize_path("res://../character/style_revision/world_style/vehicle_animation_before_idle.gd")
	var previous := GDScript.new()
	previous.source_code = FileAccess.get_file_as_string(previous_path).replace("class_name VehicleAnimation", "")
	if previous.reload() != OK:
		push_error("Cannot compile preserved animator baseline")
		get_tree().quit(1)
		return
	var results: Array = []
	for id in ["pickup_truck", "atv"]:
		var older := Vehicle.new()
		add_child(older)
		older.setup(id, null)
		older.set_physics_process(false)
		var candidate := Vehicle.new()
		add_child(candidate)
		candidate.setup(id, null)
		candidate.set_physics_process(false)
		var baseline: Node3D = previous.new()
		older.add_child(baseline)
		baseline.call("setup", older.model)
		var current := candidate.get("animator") as VehicleAnimation
		var pairs: Array = []
		for node: Node3D in older.model.find_children("*", "Node3D", true, false):
			var match_node := candidate.model.find_child(String(node.name), true, false) as Node3D
			if match_node:
				pairs.append([node, match_node])
		var max_origin_error := 0.0
		var max_basis_error := 0.0
		for frame in 360:
			var speed := 7.0 if frame < 40 else (-3.0 if frame < 80 else 0.0)
			var steer := .8 if frame < 60 else (-.4 if frame < 90 else 0.0)
			var occupied := frame < 100
			var wrecked := frame >= 80 and frame < 90
			if frame == 105:
				baseline.call("play_door_cycle")
				current.play_door_cycle()
			baseline.call("update_motion",1.0/60.0,speed,steer,occupied,wrecked)
			current.update_motion(1.0/60.0,speed,steer,occupied,wrecked)
			for pair: Array in pairs:
				var a: Transform3D = pair[0].transform
				var b: Transform3D = pair[1].transform
				max_origin_error = maxf(max_origin_error,a.origin.distance_to(b.origin))
				max_basis_error = maxf(max_basis_error,maxf((a.basis.x-b.basis.x).length(),maxf((a.basis.y-b.basis.y).length(),(a.basis.z-b.basis.z).length())))
		var start := Time.get_ticks_usec()
		for i in 600:
			baseline.call("update_motion",1.0/60.0,0.0,0.0,false,false)
		var before := (Time.get_ticks_usec()-start)/600.0
		start = Time.get_ticks_usec()
		for i in 600:
			current.update_motion(1.0/60.0,0.0,0.0,false,false)
		var after := (Time.get_ticks_usec()-start)/600.0
		var passed := max_origin_error < .00001 and max_basis_error < .00001
		var result := {"vehicle": id, "baseline_us_per_parked_update": before, "revised_us_per_parked_update": after, "max_origin_error_m": max_origin_error, "max_basis_error": max_basis_error, "visible_trace_equivalent": passed, "nodes_compared": pairs.size()}
		results.append(result)
		print("VEHICLE_IDLE_CPU ",JSON.stringify(result))
		older.queue_free()
		candidate.queue_free()
		await get_tree().process_frame
	FileAccess.open(ProjectSettings.globalize_path("res://../character/style_revision/world_style/vehicle_idle_cpu.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	get_tree().quit(0 if results.all(func(r): return r["visible_trace_equivalent"]) else 1)
