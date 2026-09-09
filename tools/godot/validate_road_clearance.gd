extends Node
## Full map ground-level collision sweeps and road-end connectivity, not only new content.
func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var world := load("res://game/world/world.tscn").instantiate() as World
	add_child(world)
	world.setup("mesh", null, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := world.get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = .25
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 1
	var blockers: Dictionary = {}
	var samples := 0
	var roads: Array = world.layout.roads.filter(func(r): return r.get("type", "") != "rail")
	var connections: Dictionary = {}
	var endpoints: Array = []
	for road: Dictionary in roads:
		connections[String(road["id"])] = []
		var points: Array = road["points"]
		for end_index in [0, points.size()-1]:
			endpoints.append({"road":String(road["id"]),"position":Vector2(float(points[end_index][0]),float(points[end_index][1])),"width":float(road["width"])})
		var last_sample := Vector2(INF, INF)
		for i in range(points.size()-1):
			var a := Vector2(float(points[i][0]),float(points[i][1]))
			var b := Vector2(float(points[i+1][0]),float(points[i+1][1]))
			var length := a.distance_to(b)
			var direction := (b-a).normalized()
			var side := Vector2(-direction.y,direction.x)
			var count := maxi(1,ceili(length/3.0))
			for k in range(count+1):
				var center := a.lerp(b,float(k)/count)
				if center.distance_to(last_sample) < 2.0:
					continue
				last_sample = center
				for lane in [-1.0,0.0,1.0]:
					var p: Vector2 = center+side*float(lane)*maxf(.0,float(road["width"])*.5-.4)
					var y: float = world.call("road_height_at",p.x,p.y) if world.has_method("road_height_at") else world.height_at(p.x,p.y)
					query.transform = Transform3D(Basis.IDENTITY,Vector3(p.x,y+.95,p.y))
					for hit: Dictionary in space.intersect_shape(query,16):
						var node: Node = hit["collider"]
						if not node is StaticBody3D:
							continue
						if not world.buildings.is_ancestor_of(node) and not world.props.is_ancestor_of(node):
							continue
						var key := String(road["id"])+":"+str(node.get_path())
						if not blockers.has(key):
							blockers[key] = {"road":road["id"],"collider":str(node.get_path()),"position":[p.x,y,p.y],"name":String(node.name),"hits":0}
						blockers[key]["hits"] += 1
					samples += 1
	for endpoint: Dictionary in endpoints:
		var closest := INF
		var target := ""
		var threshold := 0.0
		var p: Vector2 = endpoint["position"]
		for road: Dictionary in roads:
			if road["id"] == endpoint["road"]:
				continue
			var points: Array = road["points"]
			for i in range(points.size()-1):
				var a := Vector2(float(points[i][0]),float(points[i][1]))
				var b := Vector2(float(points[i+1][0]),float(points[i+1][1]))
				var distance := p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b))
				if distance < closest:
					closest = distance
					target = road["id"]
					threshold = (float(endpoint["width"])+float(road["width"]))*0.5+.5
		endpoint["nearest_road"] = target
		endpoint["gap_m"] = closest
		endpoint["connected"] = closest <= threshold
		endpoint["position"] = [p.x,p.y]
		if closest <= threshold:
			connections[endpoint["road"]].append(target)
			connections[target].append(endpoint["road"])
	var reached: Dictionary = {}
	var pending: Array = ["ring"]
	while not pending.is_empty():
		var road: String = pending.pop_back()
		if reached.has(road):
			continue
		reached[road] = true
		pending.append_array(connections.get(road, []))
	var disconnected: Array = []
	for id: String in connections:
		if not reached.has(id):
			disconnected.append(id)
	var report := {"road_count":roads.size(),"sweep_samples":samples,"blocking_static_objects":blockers.values(),"disconnected_roads":disconnected,"endpoints":endpoints,"build_stats":world.build_stats}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/map"))
	FileAccess.open("res://docs/map/road_clearance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("ROAD_CLEARANCE ",roads.size()," roads; ",samples," samples; ",blockers.size()," blockers; disconnected=",disconnected)
	for blocker: Dictionary in blockers.values():
		print("ROAD_BLOCKER ",JSON.stringify(blocker))
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if blockers.is_empty() and disconnected.is_empty() else 1)
