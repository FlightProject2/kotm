extends SceneTree
## Generates world/prefabs/buildings/*.tscn from design/map/prefabs.json.
## Kit buildings are assembled from Kenney Building Kit pieces (2 m cells, 2.4 m walls, pivots at
## the bottom centre, walls run along local Z). Every prefab root is a StaticBody3D on layers
## world + camera_blockers carrying BoxShape3D colliders, a "Visual" node with the models, and
## Marker3D loot nodes under "LootNodes". Root meta "footprint" = Vector2 world size.

const OUT_DIR := "res://world/prefabs/buildings/"
const CELL := 2.0
const WALL_H := 2.4
var pieces: Dictionary
var piece_scenes: Dictionary = {}

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var f := FileAccess.open("res://design/map/prefabs.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	pieces = data["kitPieces"]
	for k in pieces:
		piece_scenes[k] = load(pieces[k])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var count := 0
	for id in data["prefabs"]:
		var def: Dictionary = data["prefabs"][id]
		var root := StaticBody3D.new()
		root.name = id.to_pascal_case()
		root.collision_layer = 1 | 32
		root.collision_mask = 0
		var visual := Node3D.new(); visual.name = "Visual"; root.add_child(visual); visual.owner = root
		var loot := Node3D.new(); loot.name = "LootNodes"; root.add_child(loot); loot.owner = root
		var footprint := Vector2.ZERO
		match def["kind"]:
			"kit": footprint = _build_kit(root, visual, loot, def, id)
			"model": footprint = _build_model(root, visual, loot, def)
			"boxes": footprint = _build_boxes(root, visual, loot, def)
		for e in def.get("extras", []):
			_add_extra(root, visual, e)
		root.set_meta("footprint", footprint)
		root.set_meta("prefab_id", id)
		var packed := PackedScene.new()
		var err := packed.pack(root)
		if err != OK:
			print("PREFAB %s pack failed: %s" % [id, error_string(err)])
			continue
		err = ResourceSaver.save(packed, OUT_DIR + id + ".tscn")
		print("PREFAB %-18s %s footprint=%s" % [id, error_string(err), footprint])
		count += 1
		root.free()
	print("PREFABS: %d written" % count)
	quit(0)

# ---------- helpers ----------
func _instance(root: Node, parent: Node, key: String, xf: Transform3D) -> Node3D:
	var inst: Node3D = piece_scenes[key].instantiate()
	parent.add_child(inst)
	inst.owner = root
	inst.transform = xf
	return inst

func _box(root: Node, size: Vector3, xf: Transform3D, name := "Col") -> void:
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = size
	cs.shape = s
	cs.name = name + str(root.get_child_count())
	root.add_child(cs)
	cs.owner = root
	cs.transform = xf

func _marker(root: Node, loot: Node, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = "Loot" + str(loot.get_child_count())
	loot.add_child(m)
	m.owner = root
	m.position = pos

## Wall piece on an edge: p = edge centre (at floor base), along = unit direction of the edge.
func _wall(root: Node, visual: Node, key: String, p: Vector3, along: Vector3, wide := false) -> void:
	var yaw := atan2(along.x, along.z)   # rotate local Z onto `along`
	var xf := Transform3D(Basis(Vector3.UP, yaw), p)
	_instance(root, visual, key, xf)
	var len := 4.0 if wide else 2.0
	if key == "door":
		# jambs 0.5 m each side + lintel over a 1 m x 2 m opening
		var up := Vector3(0, WALL_H * 0.5, 0)
		_box(root, Vector3(0.2, WALL_H, 0.5), Transform3D(Basis(Vector3.UP, yaw), p + up) * Transform3D(Basis(), Vector3(0, 0, 0.75)))
		_box(root, Vector3(0.2, WALL_H, 0.5), Transform3D(Basis(Vector3.UP, yaw), p + up) * Transform3D(Basis(), Vector3(0, 0, -0.75)))
		_box(root, Vector3(0.2, 0.4, 1.0), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, WALL_H - 0.2, 0)))
	else:
		_box(root, Vector3(0.2, WALL_H, len), Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, WALL_H * 0.5, 0)))

func _build_kit(root: Node, visual: Node, loot: Node, def: Dictionary, id: String) -> Vector2:
	var cx := int(def["cells"][0])
	var cz := int(def["cells"][1])
	var floors := int(def.get("floors", 1))
	var rows := int(def.get("wallRows", 1))
	var windows: String = def.get("windows", "alternate")
	var door: String = def.get("door", "front")
	var stairs: bool = def.get("stairs", false)
	var w := cx * CELL
	var d := cz * CELL
	var x0 := -w * 0.5
	var z0 := -d * 0.5
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var floor_h := WALL_H * rows
	var stair_cells: Array = []
	if stairs and floors > 1:
		stair_cells = [Vector2i(0, 0), Vector2i(0, 1)]   # back-left, running +Z
	for f in floors:
		var y := f * floor_h
		# floor slabs (skip the stair hole on upper floors)
		for i in cx:
			for j in cz:
				if f > 0 and stair_cells.has(Vector2i(i, j)):
					continue
				var c := Vector3(x0 + (i + 0.5) * CELL, y, z0 + (j + 0.5) * CELL)
				_instance(root, visual, "floor", Transform3D(Basis(), c))
				_box(root, Vector3(CELL, 0.1, CELL), Transform3D(Basis(), c + Vector3(0, 0.05, 0)))
		# perimeter walls, `rows` high
		for r in rows:
			var yb := y + r * WALL_H
			for i in cx:
				# front (+Z) and back (-Z), edges run along X
				for side: int in [1, -1]:
					var zc := z0 + (d if side == 1 else 0.0)
					var p := Vector3(x0 + (i + 0.5) * CELL, yb, zc)
					var key := "wall"
					var is_door: bool = f == 0 and r == 0 and i == cx / 2 and ((side == 1 and door != "none") or (side == -1 and door == "front_back"))
					if is_door:
						key = "door"
					elif _window_here(windows, i, cx, rng) and r == 0:
						key = "window"
					_wall(root, visual, key, p, Vector3(1, 0, 0))
			for j in cz:
				for side: int in [1, -1]:
					var xc := x0 + (w if side == 1 else 0.0)
					var p := Vector3(xc, yb, z0 + (j + 0.5) * CELL)
					var key := "wall"
					if _window_here(windows, j, cz, rng) and r == 0 and j != 0 and j != cz - 1:
						key = "window"
					_wall(root, visual, key, p, Vector3(0, 0, 1))
		# stairs from this floor to the next
		if f < floors - 1 and not stair_cells.is_empty():
			var sp := Vector3(x0 + 0.65 + 0.35, y, z0 + 2.0)   # piece spans z -2..2 around its origin
			_instance(root, visual, "stairs", Transform3D(Basis(), sp))
			var ramp_len := 4.0
			var ramp_h := floor_h
			var ang := -atan2(ramp_h, ramp_len)
			var centre := sp + Vector3(0, ramp_h * 0.5, 0)
			_box(root, Vector3(1.3, 0.2, sqrt(ramp_len * ramp_len + ramp_h * ramp_h)), Transform3D(Basis(Vector3.RIGHT, ang), centre))
		# loot nodes on this floor
		var n := int(def.get("lootNodes", 1))
		for k in ceili(float(n) / floors):
			var i := rng.randi_range(0, cx - 1)
			var j := rng.randi_range(0, cz - 1)
			_marker(root, loot, Vector3(x0 + (i + 0.5) * CELL, y + 0.15, z0 + (j + 0.5) * CELL))
	# roof: slab + parapet
	var ry := floors * floor_h
	for i in cx:
		for j in cz:
			var c := Vector3(x0 + (i + 0.5) * CELL, ry, z0 + (j + 0.5) * CELL)
			_instance(root, visual, "floor", Transform3D(Basis(), c))
			_box(root, Vector3(CELL, 0.1, CELL), Transform3D(Basis(), c + Vector3(0, 0.05, 0)))
	for i in cx:
		for side: int in [1, -1]:
			var zc := z0 + (d if side == 1 else 0.0)
			var p := Vector3(x0 + (i + 0.5) * CELL, ry, zc)
			_instance(root, visual, "border", Transform3D(Basis(Vector3.UP, PI * 0.5 * (1 if side == 1 else -1)), p))
			_box(root, Vector3(2.0, 0.3, 0.2), Transform3D(Basis(), p + Vector3(0, 0.15, 0)))
	for j in cz:
		for side: int in [1, -1]:
			var xc := x0 + (w if side == 1 else 0.0)
			var p := Vector3(xc, ry, z0 + (j + 0.5) * CELL)
			_instance(root, visual, "border", Transform3D(Basis(Vector3.UP, 0.0 if side == 1 else PI), p))
			_box(root, Vector3(0.2, 0.3, 2.0), Transform3D(Basis(), p + Vector3(0, 0.15, 0)))
	# outdoor loot node by the door
	_marker(root, loot, Vector3(x0 + (cx / 2 + 0.5) * CELL + 1.5, 0.15, z0 + d + 1.5))
	return Vector2(w, d)

func _window_here(mode: String, i: int, n: int, rng: RandomNumberGenerator) -> bool:
	match mode:
		"none": return false
		"alternate": return i % 2 == 1
		"wide": return i % 2 == 1
		"sparse": return i == n / 2 and n > 2
	return false

func _build_model(root: Node, visual: Node, loot: Node, def: Dictionary) -> Vector2:
	var scene: PackedScene = load(def["scene"])
	var inst: Node3D = scene.instantiate()
	visual.add_child(inst)
	inst.owner = root
	var s := float(def.get("scale", 1.0))
	inst.scale = Vector3.ONE * s
	var aabb := _aabb(inst)
	_box(root, aabb.size, Transform3D(Basis(), aabb.get_center()))
	var n := int(def.get("lootNodes", 1))
	for k in n:
		var a := float(k) / maxf(n, 1) * TAU + 0.6
		_marker(root, loot, Vector3(aabb.get_center().x + cos(a) * (aabb.size.x * 0.5 + 1.5), 0.15, aabb.get_center().z + sin(a) * (aabb.size.z * 0.5 + 1.5)))
	return Vector2(aabb.size.x, aabb.size.z)

func _build_boxes(root: Node, visual: Node, loot: Node, def: Dictionary) -> Vector2:
	var ext := Vector2.ZERO
	for b in def["boxes"]:
		var size := Vector3(b["size"][0], b["size"][1], b["size"][2])
		var pos := Vector3(b["pos"][0], b["pos"][1], b["pos"][2])
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(b.get("color", "#777777"))
		mat.roughness = 0.9
		mi.material_override = mat
		visual.add_child(mi)
		mi.owner = root
		mi.position = pos
		if not b.get("ramp", false):
			_box(root, size, Transform3D(Basis(), pos))
		ext.x = maxf(ext.x, absf(pos.x) * 2 + size.x)
		ext.y = maxf(ext.y, absf(pos.z) * 2 + size.z)
	var n := int(def.get("lootNodes", 0))
	for k in n:
		_marker(root, loot, Vector3(ext.x * 0.5 + 1.0, 0.15, 0))
	return ext

func _add_extra(root: Node, visual: Node, e: Dictionary) -> void:
	var scene: PackedScene = load(e["scene"])
	if scene == null:
		return
	var inst: Node3D = scene.instantiate()
	visual.add_child(inst)
	inst.owner = root
	var s := float(e.get("scale", 1.0))
	inst.scale = Vector3.ONE * s
	inst.position = Vector3(e["pos"][0], e["pos"][1], e["pos"][2])
	inst.rotation.y = float(e.get("rotY", 0.0))
	if e.get("collision", "box") == "box":
		var aabb := _aabb(inst)
		_box(root, aabb.size, Transform3D(Basis(), aabb.get_center()))

func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var a: AABB = (n.get_parent() as Node3D).global_transform.affine_inverse() * (mi.global_transform * mi.get_aabb()) if n.is_inside_tree() else _local_aabb(n, mi)
		out = a if first else out.merge(a)
		first = false
	return out

## AABB of a mesh instance relative to its prefab-local ancestor without needing the tree.
func _local_aabb(ancestor: Node3D, mi: MeshInstance3D) -> AABB:
	var xf := Transform3D.IDENTITY
	var n: Node = mi
	while n != null and n != ancestor.get_parent():
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf * mi.get_aabb()
