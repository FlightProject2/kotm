class_name FrontierExpansion
extends RefCounted
## Original winter kit, batched by asset and 64 m cell. Existing layout remains intact.
## Every visual shares one mesh resource; collision and reachable loot remain independent.

const KIT_PATH := "res://assets/frontier/kit.json"
const VISUAL_RANGE := 430.0
const DETAIL_RANGE := 190.0
static var _kit: Dictionary = {}
static var _meshes: Dictionary = {}
static var _materials: Dictionary = {}
static var _box_shapes: Dictionary = {}

static func _assets() -> Dictionary:
	if _kit.is_empty() and FileAccess.file_exists(KIT_PATH):
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(KIT_PATH))
		_kit = data.get("assets", {})
		var resort_path := "res://assets/resort/kit.json"
		if FileAccess.file_exists(resort_path):
			var resort: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(resort_path))
			_kit.merge(resort.get("assets", {}))
	return _kit

static func recognizes(id: String) -> bool:
	return id.begins_with("frontier_") and _assets().has(id.trim_prefix("frontier_"))

static func replacement_prefab(id: String, placement: Dictionary) -> String:
	if id == "railcar" and not _assets().is_empty():
		var variants := ["rail_boxcar", "rail_tanker", "rail_flatcar"]
		var index := absi(int(float(placement.get("z", 0.0)) / 22.0)) % variants.size()
		return "frontier_" + variants[index]
	return id

static func mesh_for(id: String) -> Mesh:
	if _meshes.has(id):
		return _meshes[id]
	var spec: Dictionary = _assets().get(id, {})
	if spec.is_empty():
		return null
	var scene := load(String(spec["model"])) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	var out: Mesh = null
	# Blender exports a single mesh with applied ground-pivot transforms.
	for child: Node in inst.find_children("*", "MeshInstance3D", true, false):
		out = (child as MeshInstance3D).mesh
		break
	inst.free()
	_meshes[id] = out
	return out

static func instantiate_asset(prefab_id: String) -> Node3D:
	var id := prefab_id.trim_prefix("frontier_")
	var spec: Dictionary = _assets().get(id, {})
	if spec.is_empty():
		return null
	var body := _body(id, spec)
	var visual := MeshInstance3D.new()
	visual.name = "FrontierVisual"
	visual.mesh = mesh_for(id)
	visual.visibility_range_end = VISUAL_RANGE
	visual.visibility_range_end_margin = 35.0
	body.add_child(visual)
	var markers := Node3D.new()
	markers.name = "LootNodes"
	body.add_child(markers)
	for p: Array in spec.get("loot", []):
		var marker := Marker3D.new()
		marker.position = _v(p)
		markers.add_child(marker)
	if id.begins_with("rail_"):
		var marker := Marker3D.new()
		marker.position = Vector3(2.05, .22, 0)
		markers.add_child(marker)
	body.set_meta("footprint", Vector2(float(spec["footprint"][0]), float(spec["footprint"][1])))
	body.set_meta("frontier_asset", id)
	return body

static func _body(id: String, spec: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = id
	body.set_meta("frontier_asset", id)
	body.collision_layer = 1 | 32
	body.set_meta("audio_surface", "wood" if id.begins_with("house_") or id == "yard_fence" else "metal")
	for shape_def: Dictionary in spec.get("colliders", []):
		var collision := CollisionShape3D.new()
		if shape_def.has("points"):
			var shape := ConvexPolygonShape3D.new()
			var pts := PackedVector3Array()
			for p: Array in shape_def["points"]:
				pts.append(_v(p))
			shape.points = pts
			collision.shape = shape
		else:
			var size := _v(shape_def["size"])
			var key := str(size)
			if not _box_shapes.has(key):
				var shape := BoxShape3D.new()
				shape.size = size
				_box_shapes[key] = shape
			collision.shape = _box_shapes[key]
			collision.position = _v(shape_def["position"])
		body.add_child(collision)
	return body

static func build_details(world: World) -> Dictionary:
	var data: Dictionary = world.layout.frontier
	var stats := {"frontier_props": 0, "frontier_batches": 0, "frontier_roads": 0}
	if data.is_empty():
		return stats
	var root := Node3D.new()
	root.name = "FrontierDistricts"
	world.props.add_child(root)
	var groups: Dictionary = {}
	for entry: Dictionary in data.get("props", []):
		var id: String = entry["id"]
		var spec: Dictionary = _assets().get(id, {})
		if spec.is_empty():
			continue
		var pos := Vector3(float(entry["x"]), float(entry["y"]), float(entry["z"]))
		var transform := Transform3D(Basis(Vector3.UP, float(entry.get("yaw", 0.0))), pos)
		var cell := Vector2i(floori(pos.x / 64.0), floori(pos.z / 64.0))
		var key := "%s:%d:%d" % [id, cell.x, cell.y]
		if not groups.has(key):
			groups[key] = {"id": id, "origin": Vector3(cell.x * 64.0, 0, cell.y * 64.0), "transforms": []}
		groups[key]["transforms"].append(transform)
		var body := _body(id, spec)
		root.add_child(body)
		body.global_transform = transform
		for p: Array in spec.get("loot", []):
			world.loot_nodes.append({"pos": transform * _v(p), "class": spec["kind"]})
		stats["frontier_props"] += 1
	for key: String in groups:
		var group: Dictionary = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh_for(String(group["id"]))
		var transforms: Array = group["transforms"]
		mm.instance_count = transforms.size()
		var origin: Vector3 = group["origin"]
		for i in transforms.size():
			var transform: Transform3D = transforms[i]
			transform.origin -= origin
			mm.set_instance_transform(i, transform)
		var batch := MultiMeshInstance3D.new()
		batch.name = key.replace(":", "_")
		batch.multimesh = mm
		batch.position = origin
		var landmark: bool = String(group["id"]).begins_with("rail_") or group["id"] == "water_tower"
		batch.visibility_range_end = VISUAL_RANGE if landmark else DETAIL_RANGE
		batch.visibility_range_end_margin = 25.0
		root.add_child(batch)
		stats["frontier_batches"] += 1
	for road: Dictionary in data.get("roads", []):
		_build_road(root, road)
		stats["frontier_roads"] += 1
	for track: Dictionary in data.get("tracks", []):
		_build_track(root, track)
	return stats

static func _build_road(root: Node3D, road: Dictionary) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points: Array = road["points"]
	var heights: Array = road["profileHeightsM"]
	var widths := [-0.5, -0.42, -0.30, 0.30, 0.42, 0.5]
	var colors := [Color(.72,.77,.81), Color(.47,.52,.56), Color(.29,.33,.36), Color(.29,.33,.36), Color(.47,.52,.56), Color(.72,.77,.81)]
	for i in range(points.size() - 1):
		var a := Vector3(float(points[i][0]), float(heights[i]) + 0.027, float(points[i][1]))
		var b := Vector3(float(points[i+1][0]), float(heights[i+1]) + 0.027, float(points[i+1][1]))
		var direction := (b - a).normalized()
		var side := direction.cross(Vector3.UP) * float(road["width"])
		# Powder on ploughed shoulders joins the new streets to the existing winter ground.
		for strip in range(widths.size()-1):
			var corners := [a+side*widths[strip], a+side*widths[strip+1], b+side*widths[strip+1], b+side*widths[strip]]
			for index in [0, 2, 1, 0, 3, 2]:
				st.set_normal(Vector3.UP)
				st.set_color(colors[strip if index == 0 or index == 3 else strip+1])
				st.set_uv(Vector2(corners[index].x, corners[index].z) * 0.2)
				st.add_vertex(corners[index])
	var mesh := st.commit()
	var road_material := _mat("asphalt", Color.WHITE)
	road_material.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, road_material)
	var visual := MeshInstance3D.new()
	visual.name = String(road["id"])
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = VISUAL_RANGE
	root.add_child(visual)

static func _build_track(root: Node3D, data: Dictionary) -> void:
	var points: Array = data["points"]
	var y := float(data["y"])
	var ties: Array[Transform3D] = []
	var rails := SurfaceTool.new()
	rails.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()-1):
		var a := Vector3(float(points[i][0]), y, float(points[i][1]))
		var b := Vector3(float(points[i+1][0]), y, float(points[i+1][1]))
		var length := a.distance_to(b)
		var dir := (b-a).normalized()
		var rotation := Basis(Vector3.UP, atan2(dir.x, dir.z))
		for side in [-1.0, 1.0]:
			var box := BoxMesh.new()
			box.size = Vector3(.075, .13, length)
			var center := (a+b)*.5 + rotation * Vector3(side*1.04,.15,0)
			rails.append_from(box, 0, Transform3D(rotation, center))
		for k in range(ceili(length/.85)):
			ties.append(Transform3D(rotation, a + dir * (k+.5)*.85 + Vector3.UP*.045))
	var mesh := rails.commit()
	mesh.surface_set_material(0, _mat("metal", Color(.22,.24,.24)))
	var visual := MeshInstance3D.new()
	visual.name = "FreightSidingRails"
	visual.mesh = mesh
	visual.visibility_range_end = 300.0
	root.add_child(visual)
	var tie_mesh := BoxMesh.new()
	tie_mesh.size = Vector3(2.7,.09,.24)
	tie_mesh.material = _mat("timber", Color(.22,.18,.13))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tie_mesh
	mm.instance_count = ties.size()
	for i in ties.size():
		mm.set_instance_transform(i, ties[i])
	var batch := MultiMeshInstance3D.new()
	batch.name = "FreightSidingSleepers"
	batch.multimesh = mm
	batch.visibility_range_end = DETAIL_RANGE
	root.add_child(batch)

static func _mat(role: String, color: Color) -> StandardMaterial3D:
	if not _materials.has(role):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = .88
		_materials[role] = KOTMWorldStyle.surface(material, role)
	return _materials[role]

static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))
