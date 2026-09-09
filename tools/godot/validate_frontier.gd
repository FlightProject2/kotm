extends Node
## Real imports + structural physics + terrain continuity, without building the whole map.
var errors: Array[String] = []
var report: Dictionary = {"assets": [], "buildings": [], "road_max_height_error": 0.0}

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var layout := MapLayout.load_default()
	var hf := HeightField.load_from(layout.heightmap_path, layout.vertex_spacing, World.TERRAIN_LOD)
	var world := load("res://game/world/world.tscn").instantiate() as World
	add_child(world)
	world.layout = layout
	world.height_field = hf
	var kit: Dictionary = FrontierExpansion._assets()
	for id: String in kit:
		var mesh := FrontierExpansion.mesh_for(id)
		if mesh == null or mesh.get_aabb().size.length() < .1:
			errors.append("Invalid model " + id)
			continue
		report["assets"].append({"id": id, "surfaces": mesh.get_surface_count(), "bounds": str(mesh.get_aabb())})
	var nodes: Array[Node3D] = []
	for b: Dictionary in layout.frontier.get("buildings", []):
		var node := FrontierExpansion.instantiate_asset(String(b["prefab"]))
		world.buildings.add_child(node)
		node.global_transform = Transform3D(Basis(Vector3.UP, float(b["yaw"])), Vector3(float(b["x"]), float(b["baseY"]), float(b["z"])))
		nodes.append(node)
		var id := String(b["prefab"]).trim_prefix("frontier_")
		var size: Array = kit[id]["footprint"]
		var max_delta := 0.0
		for x in [-float(size[0])*.5, 0.0, float(size[0])*.5]:
			for z in [-float(size[1])*.5, 0.0, float(size[1])*.5]:
				var p: Vector3 = node.global_transform * Vector3(x, 0, z)
				max_delta = maxf(max_delta, absf(p.y - hf.height_at(p.x,p.z)))
		report["buildings"].append({"id": id, "position": str(node.position), "terrain_delta": max_delta})
		if max_delta > .25:
			errors.append("Building foundation/terrain mismatch %s: %.3fm" % [node.position,max_delta])
	FrontierExpansion.build_details(world)
	for road: Dictionary in layout.frontier.get("roads", []):
		var points: Array = road["points"]
		var heights: Array = road["profileHeightsM"]
		for i in range(points.size()-1):
			var a := Vector2(float(points[i][0]),float(points[i][1]))
			var b := Vector2(float(points[i+1][0]),float(points[i+1][1]))
			for t in range(11):
				var p := a.lerp(b,t/10.0)
				var y := lerpf(float(heights[i]),float(heights[i+1]),t/10.0)
				var delta := absf(y-hf.height_at(p.x,p.y))
				report["road_max_height_error"] = maxf(float(report["road_max_height_error"]),delta)
				if delta > .2:
					errors.append("Road floating/buried " + String(road["id"]) + ": " + str(delta))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	var entrances := 0
	for node: Node3D in nodes:
		var id: String = node.get_meta("frontier_asset")
		for p: Array in kit[id].get("entrances", []):
			var center := Vector3(float(p[0]),1.25,float(p[2]))
			var from := node.global_transform * (center + Vector3(0,0,1.8))
			var to := node.global_transform * (center - Vector3(0,0,.65))
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))
			if not hit.is_empty():
				errors.append("Blocked doorway: " + id + " at " + str(node.position))
			entrances += 1
		var from := node.global_transform * Vector3(0,1,0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from,from-Vector3.UP*2,1))
		if hit.is_empty():
			errors.append("No solid interior floor: " + id)
	report["entrances_checked"] = entrances
	report["prop_loot_markers"] = world.loot_nodes.size()
	report["errors"] = errors
	var output := "res://assets/frontier/validation.json"
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FRONTIER_VALIDATION ", kit.size(), " assets; ", entrances, " entrances; ", errors.size(), " errors")
	for error: String in errors:
		push_error(error)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if errors.is_empty() else 1)
