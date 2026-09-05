class_name WorldBuilder
extends RefCounted
## Places the authored layout: building prefabs on their pads, trees, props and road wrecks.
## Deterministic from the layout seed. Records loot node positions for the LootSpawner.

const PREFAB_DIR := "res://world/prefabs/buildings/"
const CAR_SCALE := 1.6
const PROP_SCALE := 2.5

static func build(world: World) -> Dictionary:
	var layout := world.layout
	var rng := RandomNumberGenerator.new()
	rng.seed = layout.seed + 11
	var stats := {"buildings": 0, "placeholders": 0, "props": 0, "wrecks": 0, "loot_nodes": 0}
	var cache: Dictionary = {}
	for b in layout.buildings:
		var id: String = b["prefab"]
		var base := layout.building_base_height(b)
		var x := float(b["x"])
		var z := float(b["z"])
		var y := base if not is_nan(base) else world.height_at(x, z)
		var yaw := float(b.get("yaw", 0.0))
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))
		var scene: PackedScene = cache.get(id)
		if scene == null and not cache.has(id):
			scene = load(PREFAB_DIR + id + ".tscn") if ResourceLoader.exists(PREFAB_DIR + id + ".tscn") else null
			cache[id] = scene
		var node: Node3D
		if scene:
			node = scene.instantiate()
			merge_meshes(node, id)
			stats["buildings"] += 1
		else:
			node = _placeholder(id)
			stats["placeholders"] += 1
		node.name = "%s_%d" % [id, stats["buildings"] + stats["placeholders"]]
		world.buildings.add_child(node)
		node.global_transform = xf
		node.set_meta("node_class", b.get("nodeClass", "residential"))
		var loot_nodes := node.get_node_or_null("LootNodes")
		if loot_nodes:
			for m in loot_nodes.get_children():
				var p: Vector3 = (m as Node3D).global_position
				world.loot_nodes.append({"pos": p, "class": b.get("nodeClass", "residential")})
				stats["loot_nodes"] += 1
		_props_for(world, b, node, rng, stats)
	_wrecks(world, rng, stats)
	_farm_fences(world, rng, stats)
	return stats

static var _merged_cache: Dictionary = {}   # prefab id -> {mesh: ArrayMesh, xf: Transform3D}

## A prefab is ~50 kit pieces, each its own draw call (x shadow splits). Merge every mesh piece
## into one ArrayMesh with a surface per material so a building costs a handful of draw calls.
## Collision shapes and LootNodes are untouched. The merged mesh is cached per prefab id.
static func merge_meshes(node: Node3D, id: String) -> void:
	var pieces: Array = []
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		pieces.append(mi)
	if pieces.is_empty():
		return
	var merged: ArrayMesh = null
	if _merged_cache.has(id):
		merged = _merged_cache[id]
	else:
		var groups: Dictionary = {}    # "material_rid|format" -> [SurfaceTool, Material]
		var order: Array = []
		for mi in pieces:
			var xf: Transform3D = _relative_transform(mi, node)
			for si in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(si)
				var key := "%s|%s" % [mat.get_rid() if mat else "none", _format_key(mi.mesh, si)]
				if not groups.has(key):
					var st := SurfaceTool.new()
					st.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[key] = [st, mat]
					order.append(key)
				var st: SurfaceTool = groups[key][0]
				st.append_from(mi.mesh, si, xf)
		merged = ArrayMesh.new()
		for key in order:
			var st: SurfaceTool = groups[key][0]
			st.commit(merged)
			var mat: Material = groups[key][1]
			if mat:
				merged.surface_set_material(merged.get_surface_count() - 1, mat)
		_merged_cache[id] = merged
	for mi in pieces:
		mi.get_parent().remove_child(mi)
		mi.queue_free()
	var out := MeshInstance3D.new()
	out.name = "MergedMesh"
	out.mesh = merged
	out.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	node.add_child(out)

## Which vertex arrays a surface carries (surfaces with different layouts must not be merged).
static func _format_key(mesh: Mesh, si: int) -> String:
	var arrays := mesh.surface_get_arrays(si)
	var key := ""
	for i in arrays.size():
		key += "1" if arrays[i] != null else "0"
	return key

static func _relative_transform(n: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

static func _placeholder(id: String) -> Node3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 32
	var size := Vector3(8, 4, 6)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = size; cs.shape = bs
	cs.position.y = size.y * 0.5
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size; mi.mesh = bm
	mi.position.y = size.y * 0.5
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.6, 0.55, 0.5)
	mi.material_override = mat
	body.add_child(mi)
	body.set_meta("placeholder", id)
	return body

static func _prop(world: World, scene_path: String, pos: Vector3, yaw: float, scale: float, with_collision := true) -> Node3D:
	var scene: PackedScene = load(scene_path)
	if scene == null:
		return null
	var root: Node3D
	var inst: Node3D = scene.instantiate()
	inst.scale = Vector3.ONE * scale
	if with_collision:
		var body := StaticBody3D.new()
		body.collision_layer = 1 | 32
		body.add_child(inst)
		var aabb := _aabb(inst, scale)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new(); bs.size = aabb.size; cs.shape = bs
		cs.position = aabb.get_center()
		body.add_child(cs)
		root = body
	else:
		root = inst
	world.props.add_child(root)
	root.global_transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, world.height_at(pos.x, pos.z) if pos.y == 0.0 else pos.y, pos.z))
	return root

static func _aabb(inst: Node3D, scale: float) -> AABB:
	var out := AABB()
	var first := true
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var a := mi.get_aabb()
		var n: Node = mi
		var xf := Transform3D.IDENTITY
		while n != inst and n != null:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		a = xf * a
		a = AABB(a.position * scale, a.size * scale)
		out = a if first else out.merge(a)
		first = false
	return out

static func _props_for(world: World, b: Dictionary, node: Node3D, rng: RandomNumberGenerator, stats: Dictionary) -> void:
	var cls: String = b.get("nodeClass", "residential")
	var fp: Vector2 = node.get_meta("footprint", Vector2(8, 6))
	var x := float(b["x"]); var z := float(b["z"]); var yaw := float(b.get("yaw", 0.0))
	var basis := Basis(Vector3.UP, yaw)
	var front := basis * Vector3(0, 0, fp.y * 0.5 + 2.5)
	if cls == "industrial":
		for k in rng.randi_range(2, 4):
			var off := basis * Vector3(rng.randf_range(-fp.x * 0.5, fp.x * 0.5), 0, fp.y * 0.5 + rng.randf_range(1.5, 4.0))
			var which := "barrel" if rng.randf() < 0.6 else "box-large"
			if _prop(world, "res://assets/kenney/survival/%s.glb" % which, Vector3(x + off.x, 0, z + off.z), rng.randf() * TAU, PROP_SCALE):
				stats["props"] += 1
	elif b.get("poi", "") in ["ashford", "cranmoor"]:
		if rng.randf() < 0.5:
			var off := front + basis * Vector3(fp.x * 0.5 + 1.0, 0, 0)
			if _prop(world, "res://assets/kenney/retro-urban/detail-light-single.glb", Vector3(x + off.x, 0, z + off.z), yaw, 4.0):
				stats["props"] += 1
		if rng.randf() < 0.3:
			var off := front + basis * Vector3(-fp.x * 0.3, 0, 0)
			if _prop(world, "res://assets/kenney/retro-urban/detail-bench.glb", Vector3(x + off.x, 0, z + off.z), yaw + PI, PROP_SCALE):
				stats["props"] += 1
	elif cls == "hunting" or b["prefab"] == "cabin":
		if rng.randf() < 0.5:
			var off := front
			if _prop(world, "res://assets/kenney/survival/campfire-pit.glb", Vector3(x + off.x, 0, z + off.z), 0.0, PROP_SCALE, false):
				stats["props"] += 1

static func _wrecks(world: World, rng: RandomNumberGenerator, stats: Dictionary) -> void:
	var cars := ["police", "sedan", "truck", "suv", "van"]
	for road in world.layout.roads:
		if road["type"] != "dirt":
			continue
		var pts: Array = road["points"]
		var acc := 0.0
		for i in range(pts.size() - 1):
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i + 1][0], pts[i + 1][1])
			var seg := a.distance_to(b)
			acc += seg
			if acc >= 150.0:
				acc = 0.0
				if rng.randf() < 0.35:
					var dir := (b - a).normalized()
					var side := Vector2(-dir.y, dir.x) * rng.randf_range(2.0, 4.0) * (1.0 if rng.randf() < 0.5 else -1.0)
					var p := a.lerp(b, 0.5) + side
					var yaw := atan2(-dir.x, -dir.y) + rng.randf_range(-0.4, 0.4)
					if _prop(world, "res://assets/kenney/car/%s.glb" % cars[rng.randi_range(0, cars.size() - 1)], Vector3(p.x, 0, p.y), yaw, CAR_SCALE):
						stats["wrecks"] += 1

static func _farm_fences(world: World, rng: RandomNumberGenerator, stats: Dictionary) -> void:
	for poi in world.layout.pois:
		if poi["type"] != "farm":
			continue
		var cx := float(poi["x"]); var cz := float(poi["z"])
		var hw := 62.0; var hd := 52.0
		var seg := 5.9
		var corners := [Vector2(cx - hw, cz - hd), Vector2(cx + hw, cz - hd), Vector2(cx + hw, cz + hd), Vector2(cx - hw, cz + hd)]
		for i in 4:
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[(i + 1) % 4]
			var dir := (b - a).normalized()
			var n := int(a.distance_to(b) / seg)
			for k in n:
				if k == n / 2:
					continue   # gate gap
				var p := a + dir * (k + 0.5) * seg
				var yaw := atan2(dir.x, dir.y)   # Fence runs along local X
				if _prop(world, "res://assets/quaternius/farm/Fence.fbx", Vector3(p.x, 0, p.y), yaw + PI * 0.5, 1.0):
					stats["props"] += 1
