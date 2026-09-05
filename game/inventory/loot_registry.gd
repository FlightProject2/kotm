class_name LootRegistry
extends Node3D
## All loot on the ground: a spatial grid for queries plus one MultiMesh per visual kind.
## The server owns add/remove; clients mirror through loot_added/loot_removed events.

class Entry:
	var id: int
	var item: Dictionary          # {kind, id, qty} or {kind: "bag", owner, items: []}
	var pos: Vector3
	var key: String               # visual key
	var slot: int = -1            # instance index in the multimesh

const CELL := 32.0
const CAPACITY := 1024
const WEAPON_MODEL_LENGTH := 0.75

var entries: Dictionary = {}          # id -> Entry
var grid: Dictionary = {}             # Vector2i -> Array[int]
var _mm: Dictionary = {}              # key -> MultiMeshInstance3D
var _free: Dictionary = {}            # key -> Array[int]
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

func _ensure_mm(key: String) -> MultiMeshInstance3D:
	if _mm.has(key):
		return _mm[key]
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_" + key.replace(":", "_")
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
	add_child(mmi)
	_mm[key] = mmi
	var free: Array = []
	for i in range(CAPACITY - 1, -1, -1):
		free.append(i)
	_free[key] = free
	# park all instances far away
	for i in CAPACITY:
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0)))
	return mmi

func _mesh_for(key: String) -> Array:
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.8
	if key.begins_with("weapon:"):
		var wid := key.substr(7)
		var path: String = WeaponHolder.MODELS.get(wid, "")
		if path != "":
			var scene: PackedScene = load(path)
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
	var mmi := _ensure_mm(e.key)
	var free: Array = _free[e.key]
	if free.is_empty():
		return
	e.slot = free.pop_back()
	var s: float = _mesh_scale.get(e.key, 1.0)
	var basis := Basis(Vector3.UP, float(e.id % 360) * 0.0174).scaled(Vector3.ONE * s)
	var lift := 0.05 if e.key.begins_with("weapon:") else 0.15
	mmi.multimesh.set_instance_transform(e.slot, Transform3D(basis, e.pos + Vector3(0, lift, 0)))
	mmi.multimesh.visible_instance_count = CAPACITY

func _hide(e: Entry) -> void:
	if e.slot < 0 or not _mm.has(e.key):
		return
	var mmi: MultiMeshInstance3D = _mm[e.key]
	mmi.multimesh.set_instance_transform(e.slot, Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -1000, 0)))
	_free[e.key].append(e.slot)
	e.slot = -1
