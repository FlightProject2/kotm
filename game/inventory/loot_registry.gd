class_name LootRegistry
extends Node3D
## All loot on the ground: a spatial grid for queries plus dense spatial MultiMeshes for nearby loot.
## The server owns add/remove; clients mirror through loot_added/loot_removed events.

class Entry:
	var id: int
	var item: Dictionary          # {kind, id, qty} or {kind: "bag", owner, items: []}
	var pos: Vector3
	var key: String               # visual key
	var slot: int = -1            # dense index in its visual chunk
	var batch_key: String = ""
	var visual_transform: Transform3D

const CELL := 32.0
const CAPACITY := 128
const VISUAL_CELL := 96.0
const VISUAL_RANGE := 280.0
const WEAPON_MODEL_LENGTH := 0.75

var entries: Dictionary = {}          # id -> Entry
var grid: Dictionary = {}             # Vector2i -> Array[int]
var _mm: Dictionary = {}              # key -> MultiMeshInstance3D
var _batch_entries: Dictionary = {}   # visual chunk -> dense Array[Entry]
var _next_id: int = 1

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))

func add(item: Dictionary, pos: Vector3, forced_id := -1) -> Entry:
	var e := Entry.new()
	e.id = forced_id if forced_id > 0 else _next_id
	_next_id = maxi(_next_id, e.id + 1)
	e.item = item
	e.pos = pos
	e.key = _key_for(item)
	entries[e.id] = e
	var c := _cell(pos)
	if not grid.has(c):
		grid[c] = []
	grid[c].append(e.id)
	_show(e)
	return e

func remove(id: int) -> void:
	var e: Entry = entries.get(id)
	if e == null:
		return
	_hide(e)
	entries.erase(id)
	var c := _cell(e.pos)
	if grid.has(c):
		grid[c].erase(id)

func count() -> int:
	return entries.size()

func in_radius(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var c0 := _cell(pos - Vector3(radius, 0, radius))
	var c1 := _cell(pos + Vector3(radius, 0, radius))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			for id in grid.get(Vector2i(cx, cz), []):
				var e: Entry = entries[id]
				if Vector2(e.pos.x - pos.x, e.pos.z - pos.z).length() <= radius and absf(e.pos.y - pos.y) < 3.0:
					out.append(e)
	return out

func nearest(pos: Vector3, radius: float, filter: Callable = Callable()) -> Entry:
	var best: Entry = null
	var bd := radius
	for e in in_radius(pos, radius):
		if filter.is_valid() and not filter.call(e):
			continue
		var d := Vector2(e.pos.x - pos.x, e.pos.z - pos.z).length()
		if d < bd:
			bd = d
			best = e
	return best

# ---- visuals ----
func _key_for(item: Dictionary) -> String:
	match item["kind"]:
		"weapon": return "weapon:" + item["id"]
		"bag": return "bag"
		_: return item["kind"]

func _ensure_mm(key: String, batch: String, center: Vector3) -> MultiMeshInstance3D:
	if _mm.has(batch):
		return _mm[batch]
	var mmi := MultiMeshInstance3D.new()
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	mmi.name = "MM_" + batch.replace(":", "_").replace("@", "_").replace(",", "_")
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.instance_count = CAPACITY
	mm.visible_instance_count = 0
	var built := _mesh_for(key)
	mm.mesh = built[0]
	mmi.multimesh = mm
	if built[1] != null:
		mmi.material_override = built[1]
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.position = center
	mmi.visibility_range_end = VISUAL_RANGE
	mmi.visibility_range_end_margin = 24.0
	add_child(mmi)
	_mm[batch] = mmi
	_batch_entries[batch] = []
	return mmi

const STUDIO_MODELS := {"helmet": ["motorcycle_helmet", 0.34], "backpack": ["military_backpack", 0.5]}

func _mesh_for(key: String) -> Array:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.8
	if STUDIO_MODELS.has(key):
		var id: String = STUDIO_MODELS[key][0]
		var m := ModelLib.mesh(id)
		if m:
			var sz := ModelLib.aabb(id).size
			_mesh_scale[key] = float(STUDIO_MODELS[key][1]) / maxf(maxf(sz.x, sz.y), sz.z)
			return [m, null]
	if key.begins_with("weapon:"):
		var wid := key.substr(7)
		var path: String = WeaponHolder.MODELS.get(wid, "")
		if path.begins_with(ModelLib.DIR):
			var id := path.trim_prefix(ModelLib.DIR).trim_suffix(".glb")
			var m := ModelLib.mesh(id)
			if m:
				var sz := ModelLib.aabb(id).size
				_mesh_scale[key] = WEAPON_MODEL_LENGTH / maxf(maxf(sz.x, sz.y), sz.z)
				return [m, null]
		if path != "":
			var scene: PackedScene = load(KOTMWorldStyle.path(path))
			if scene:
				var inst := scene.instantiate()
				var mis := inst.find_children("*", "MeshInstance3D", true, false)
				if not mis.is_empty():
					var mi := mis[0] as MeshInstance3D
					var mesh: Mesh = mi.mesh
					var aabb := mi.get_aabb()
					var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
					var m := mesh.surface_get_material(0)
					inst.free()
					mat = null
					_mesh_scale[key] = WEAPON_MODEL_LENGTH / maxf(longest, 0.001)
					if WeaponHolder.TINTS.has(wid):
						var tm := StandardMaterial3D.new()
						tm.albedo_color = WeaponHolder.TINTS[wid]
						return [mesh, tm]
					return [mesh, null]
		mat.albedo_color = Color(0.15, 0.15, 0.17)
		var bm := BoxMesh.new(); bm.size = Vector3(0.75, 0.1, 0.18)
		return [bm, mat]
	var colors := {"ammo": Color(0.85, 0.72, 0.23), "helmet": Color(0.16, 0.37, 0.82), "armor": Color(0.37, 0.54, 0.2),
		"med": Color(0.94, 0.94, 0.94), "throwable": Color(0.3, 0.45, 0.25), "backpack": Color(0.45, 0.3, 0.18),
		"material": Color(0.5, 0.5, 0.5), "bag": Color(0.1, 0.1, 0.1)}
	mat.albedo_color = colors.get(key, Color(0.6, 0.6, 0.6))
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	mat.emission_energy_multiplier = 0.15
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 0.6, 0.7) if key == "bag" else Vector3(0.36, 0.28, 0.28)
	_mesh_scale[key] = 1.0
	return [bm, mat]

var _mesh_scale: Dictionary = {}

func _show(e: Entry) -> void:
	var cell := Vector2i(floori(e.pos.x / VISUAL_CELL), floori(e.pos.z / VISUAL_CELL))
	e.batch_key = "%s@%d,%d" % [e.key, cell.x, cell.y]
	var center := Vector3((cell.x + 0.5) * VISUAL_CELL, 0, (cell.y + 0.5) * VISUAL_CELL)
	var mmi := _ensure_mm(e.key, e.batch_key, center)
	var active: Array = _batch_entries[e.batch_key]
	var mm := mmi.multimesh
	if active.size() == mm.instance_count:
		mm.instance_count *= 2
		for index in active.size():
			mm.set_instance_transform(index, active[index].visual_transform)
	e.slot = active.size()
	active.append(e)
	var s: float = _mesh_scale.get(e.key, 1.0)
	var basis := Basis(Vector3.UP, float(e.id % 360) * 0.0174).scaled(Vector3.ONE * s)
	var lift := 0.05 if e.key.begins_with("weapon:") else 0.15
	e.visual_transform = Transform3D(basis, e.pos - center + Vector3(0, lift, 0))
	mm.set_instance_transform(e.slot, e.visual_transform)
	mm.visible_instance_count = active.size()

func _hide(e: Entry) -> void:
	if e.slot < 0 or not _mm.has(e.batch_key):
		return
	var mmi: MultiMeshInstance3D = _mm[e.batch_key]
	var active: Array = _batch_entries[e.batch_key]
	var last := active.size() - 1
	if e.slot != last:
		var moved: Entry = active[last]
		mmi.multimesh.set_instance_transform(e.slot, moved.visual_transform)
		active[e.slot] = moved
		moved.slot = e.slot
	active.pop_back()
	mmi.multimesh.visible_instance_count = active.size()
	e.slot = -1
	e.batch_key = ""
