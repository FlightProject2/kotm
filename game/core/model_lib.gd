class_name ModelLib
extends RefCounted
## Studio-made glTF assets (assets/models, exported from Blender by tools/blender/convert_blends.py).
## A model is merged once into a single ArrayMesh with one surface per material (dozens of
## parts -> one draw call, and MultiMesh-able for ground loot) and cached. Socket positions
## exported alongside the models come from assets/models/sockets.json.

const DIR := "res://assets/models/"
const SOCKETS := "res://assets/models/sockets.json"
static var _meshes: Dictionary = {}     # id -> ArrayMesh
static var _aabbs: Dictionary = {}      # id -> AABB
static var _sockets: Dictionary = {}

static func path(id: String) -> String:
	return KOTMWorldStyle.path(DIR + id + ".glb")

static func exists(id: String) -> bool:
	return ResourceLoader.exists(path(id))

static func sockets(id: String) -> Dictionary:
	if _sockets.is_empty():
		var f := FileAccess.open(SOCKETS, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_sockets = parsed
	return _sockets.get(id, {})

static func socket(id: String, name: String, fallback := Vector3.ZERO) -> Vector3:
	var s: Dictionary = sockets(id)
	if s.has(name):
		var a: Array = s[name]
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback

## Merged mesh of the whole model, in the model's own space (origin as exported).
static func mesh(id: String) -> ArrayMesh:
	if _meshes.has(id):
		return _meshes[id]
	var scene: PackedScene = load(path(id)) if exists(id) else null
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var groups: Dictionary = {}
	var order: Array = []
	var aabb := AABB()
	var first := true
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := _relative(mi, root)
		for si in mi.mesh.get_surface_count():
			var mat: Material = mi.get_active_material(si)
			var key := "%s|%s" % [mat.resource_path if mat and mat.resource_path != "" else (str(mat.get_instance_id()) if mat else "none"), _format_key(mi.mesh, si)]
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = [st, mat]
				order.append(key)
			(groups[key][0] as SurfaceTool).append_from(mi.mesh, si, xf)
		var part_aabb: AABB = xf * mi.mesh.get_aabb()
		aabb = part_aabb if first else aabb.merge(part_aabb)
		first = false
	root.free()
	var out := ArrayMesh.new()
	for key in order:
		var st: SurfaceTool = groups[key][0]
		st.commit(out)
		var mat: Material = groups[key][1]
		if mat:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	_meshes[id] = out
	_aabbs[id] = aabb
	return out

static func aabb(id: String) -> AABB:
	if not _aabbs.has(id):
		mesh(id)
	return _aabbs.get(id, AABB())

## A MeshInstance3D of the merged model; optional uniform scale so its longest side is [fit_to].
static func instance(id: String, fit_to := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = id
	mi.mesh = mesh(id)
	if fit_to > 0.0 and mi.mesh:
		var s := aabb(id).size
		var longest := maxf(s.x, maxf(s.y, s.z))
		if longest > 0.0:
			mi.scale = Vector3.ONE * (fit_to / longest)
	return mi

static func _format_key(m: Mesh, si: int) -> String:
	var arrays := m.surface_get_arrays(si)
	var key := ""
	for i in arrays.size():
		key += "1" if arrays[i] != null else "0"
	return key

static func _relative(n: Node3D, ancestor: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf
