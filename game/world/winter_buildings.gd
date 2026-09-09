class_name WinterBuildings
extends RefCounted
## First winter silhouette pass, added before WorldBuilder merges the kit meshes.
## Existing interiors, doorways, stairs and loot markers remain inside the original prefab.

const PITCHED := {
	"house_small": Vector3(8, 2.4, 6),
	"house_two_storey": Vector3(8, 4.8, 8),
	"cabin": Vector3(6, 2.4, 6),
	"barn_small": Vector3(8, 4.8, 6),
	"church": Vector3(8, 4.8, 12),
}
const FLAT := {
	"shed": Vector3(4, 2.4, 4),
	"radio_hut": Vector3(4, 2.4, 4),
	"shop": Vector3(10, 2.4, 6),
	"diner": Vector3(12, 2.4, 6),
	"motel": Vector3(16, 4.8, 6),
	"police_station": Vector3(12, 4.8, 8),
	"warehouse": Vector3(16, 4.8, 12),
	"gas_station": Vector3(6, 2.4, 4),
}
static var _materials: Dictionary = {}

static func dress(node: Node3D, id: String) -> void:
	if not node is StaticBody3D or node.has_meta("winter_dressed"):
		return
	if not PITCHED.has(id) and not FLAT.has(id):
		return
	node.set_meta("winter_dressed", true)
	if PITCHED.has(id):
		var spec: Vector3 = PITCHED[id]
		_roof(node, spec, id == "church")
		if id == "church":
			_church_tower(node, spec.y)
	else:
		var spec: Vector3 = FLAT[id]
		# The roof slab ends at ry + 0.1; a shallow cap stays below its parapet.
		_box(node, "RoofSnow", Vector3(spec.x - 0.12, 0.08, spec.z - 0.12),
			Vector3(0, spec.y + 0.14, 0), _material("snow"))

static func _roof(node: Node3D, spec: Vector3, church: bool) -> void:
	var width := spec.x + 0.6
	var depth := spec.z + 0.6
	var base := spec.y + 0.30
	var rise := spec.x * (0.34 if church else 0.25)
	var fascia := _material("white" if church else "wood")
	# This shallow fascia seats the new roof on the existing slab and hides the parapet.
	_box(node, "RoofFascia", Vector3(width, 0.22, depth), Vector3(0, spec.y + 0.21, 0), fascia)
	var half := width * 0.5
	var end := depth * 0.5
	var points := PackedVector3Array([
		Vector3(-half, base, -end), Vector3(half, base, -end), Vector3(0, base + rise, -end),
		Vector3(-half, base, end), Vector3(half, base, end), Vector3(0, base + rise, end),
	])
	# Closed triangular prism: gables and slopes share a matching solid convex collider.
	var faces := PackedInt32Array([0, 1, 2, 3, 5, 4, 0, 5, 3, 0, 2, 5,
		1, 5, 2, 1, 4, 5, 0, 4, 1, 0, 3, 4])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in faces:
		st.add_vertex(points[index])
	st.generate_normals()
	var roof_mesh := st.commit()
	roof_mesh.surface_set_material(0, fascia)
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	_piece(node, "GableRoof", roof_mesh, shape, Transform3D.IDENTITY)
	var angle := atan2(rise, half)
	var slope_length := sqrt(half * half + rise * rise)
	for side: int in [-1, 1]:
		_box(node, "SnowSlope", Vector3(slope_length + 0.14, 0.16, depth + 0.16),
			Vector3(side * half * 0.5, base + rise * 0.5 + 0.08, 0),
			_material("snow"), -side * angle)

static func _church_tower(node: Node3D, roof_y: float) -> void:
	var white := _material("white")
	var snow := _material("snow")
	var z := 4.25
	var shaft_bottom := roof_y + 0.1
	var shaft_top := roof_y + 4.25
	_box(node, "SteepleShaft", Vector3(2.3, shaft_top - shaft_bottom, 2.3),
		Vector3(0, (shaft_bottom + shaft_top) * 0.5, z), white)
	_box(node, "BelfrySill", Vector3(2.55, 0.18, 2.55), Vector3(0, shaft_top, z), white)
	for x_sign: int in [-1, 1]:
		for z_sign: int in [-1, 1]:
			_box(node, "BelfryPost", Vector3(0.24, 1.5, 0.24),
				Vector3(x_sign * 1.04, shaft_top + 0.75, z + z_sign * 1.04), white)
	var belfry_top := shaft_top + 1.5
	_box(node, "BelfryCornice", Vector3(2.65, 0.22, 2.65), Vector3(0, belfry_top, z), white)
	var bell := CylinderMesh.new()
	bell.top_radius = 0.16
	bell.bottom_radius = 0.38
	bell.height = 0.6
	bell.radial_segments = 12
	bell.rings = 1
	bell.material = _material("bell")
	_piece(node, "Bell", bell, bell.create_convex_shape(),
		Transform3D(Basis(), Vector3(0, shaft_top + 0.78, z)))
	_box(node, "BellHanger", Vector3(0.08, 0.5, 0.08), Vector3(0, shaft_top + 1.27, z), _material("bell"))
	var spire := CylinderMesh.new()
	spire.top_radius = 0.0
	spire.bottom_radius = 1.98
	spire.height = 2.5
	spire.radial_segments = 4
	spire.rings = 1
	spire.material = snow
	_piece(node, "SnowSpire", spire, spire.create_convex_shape(),
		Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(0, belfry_top + 1.32, z)))

static func _box(node: Node3D, label: String, size: Vector3, position: Vector3, material: Material, roll := 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var shape := BoxShape3D.new()
	shape.size = size
	_piece(node, label, mesh, shape, Transform3D(Basis(Vector3.BACK, roll), position))

static func _piece(node: Node3D, label: String, mesh: Mesh, shape: Shape3D, xf: Transform3D) -> void:
	var visual := MeshInstance3D.new()
	visual.name = label
	visual.mesh = mesh
	visual.transform = xf
	node.add_child(visual)
	var collision := CollisionShape3D.new()
	collision.name = label + "Collision"
	collision.shape = shape
	collision.transform = xf
	node.add_child(collision)

static func _material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.96
	mat.metallic = 0.0
	match key:
		"snow": mat.albedo_color = Color(0.88, 0.93, 0.97)
		"white": mat.albedo_color = Color(0.72, 0.76, 0.75)
		"bell": mat.albedo_color = Color(0.22, 0.18, 0.12)
		_: mat.albedo_color = Color(0.31, 0.24, 0.19)
	mat = KOTMWorldStyle.surface(mat, key)
	_materials[key] = mat
	return mat
