class_name MapLandmarks
extends RefCounted
## Bridges are authored separately from the terrain: deckY is the exact driving surface.
## Every solid rail, post, slab and pier has matching geometry and collision.

const RAIL_HEIGHT := 1.12
const RAIL_WIDTH := 0.18
const SURFACE_DEPTH := 0.055
static var _materials: Dictionary = {}

static func build(world: World) -> Dictionary:
	var stats := {"bridges": 0, "bridge_meshes": 0, "bridge_collision_shapes": 0}
	for item: Dictionary in world.layout.bridges:
		if not _valid(item):
			push_warning("MapLandmarks: invalid bridge %s" % item.get("id", "unnamed"))
			continue
		var a := Vector2(float(item["ax"]), float(item["az"]))
		var b := Vector2(float(item["bx"]), float(item["bz"]))
		var span := a.distance_to(b)
		var direction := (b - a) / span
		var center := (a + b) * 0.5
		var width := float(item["width"])
		var top := float(item["deckY"])
		var thickness := float(item.get("thickness", 0.7))
		var body := StaticBody3D.new()
		body.name = "Bridge_" + String(item.get("id", str(stats["bridges"])))
		body.collision_layer = 1 | 32
		body.set_meta("bridge_id", item.get("id", ""))
		body.set_meta("audio_surface", "concrete")
		world.props.add_child(body)
		# Local +Z follows the span; +X is its right side. The basis is orthonormal.
		var along := Vector3(direction.x, 0, direction.y)
		var across := Vector3(direction.y, 0, -direction.x)
		body.global_transform = Transform3D(Basis(across, Vector3.UP, along), Vector3(center.x, top, center.y))
		var groups: Dictionary = {}
		var surface_depth := minf(SURFACE_DEPTH, thickness * 0.25)
		var verge := minf(0.7, width * 0.12)
		# Only the deck's exterior faces are rendered. Closely stacked hidden slab tops
		# can leak through the thin asphalt under shallow, long-range camera angles.
		_box_mesh(groups, "concrete", Vector3(width, thickness - surface_depth, span),
			Vector3(0, -(thickness + surface_depth) * 0.5, 0), [Vector3.UP])
		_box_mesh(groups, "asphalt", Vector3(width - 2.0 * verge, surface_depth, span),
			Vector3(0, -surface_depth * 0.5, 0), [Vector3.DOWN, Vector3.LEFT, Vector3.RIGHT])
		for side: int in [-1, 1]:
			_box_mesh(groups, "snow", Vector3(verge, surface_depth, span),
				Vector3(side * (width - verge) * 0.5, -surface_depth * 0.5, 0),
				[Vector3.DOWN, Vector3.RIGHT if side < 0 else Vector3.LEFT])
		# One collider spans all three surface strips; all strip tops are exactly deckY.
		_box_collision(body, "Deck", Vector3(width, thickness, span), Vector3(0, -thickness * 0.5, 0))
		for fraction: float in [1.0 / 3.0, 2.0 / 3.0]:
			var longitudinal := (fraction - 0.5) * span
			for side: int in [-1, 1]:
				var lateral := side * width * 0.29
				var foot_world := body.global_transform * Vector3(lateral, 0, longitudinal)
				var ground: float = world.height_field.height_at(foot_world.x, foot_world.z)
				var bottom := ground - top - 0.35
				var pier_top := -thickness
				if bottom < pier_top:
					var size := Vector3(minf(1.1, width * 0.16), pier_top - bottom, 1.35)
					var position := Vector3(lateral, (pier_top + bottom) * 0.5, longitudinal)
					_solid_box(body, groups, "Pier", "concrete", size, position)
					_solid_box(body, groups, "PierFoot", "concrete", Vector3(size.x + 0.45, 0.45, 1.85),
						Vector3(lateral, bottom + 0.225, longitudinal))
		# Solid timber beams have open space between them: no invisible railing wall.
		var post_intervals := maxi(1, ceili(span / 5.5))
		for side: int in [-1, 1]:
			var rail_x := side * (width * 0.5 - RAIL_WIDTH * 0.5)
			for rail_y: float in [0.46, RAIL_HEIGHT]:
				_solid_box(body, groups, "Rail", "timber", Vector3(RAIL_WIDTH, 0.14, span),
					Vector3(rail_x, rail_y, 0))
			_solid_box(body, groups, "RailSnow", "snow", Vector3(RAIL_WIDTH + 0.055, 0.045, span),
				Vector3(rail_x, RAIL_HEIGHT + 0.0925, 0))
			for index in range(post_intervals + 1):
				var post_z := lerpf(-span * 0.5 + 0.12, span * 0.5 - 0.12, float(index) / post_intervals)
				_solid_box(body, groups, "RailPost", "timber", Vector3(0.23, RAIL_HEIGHT + 0.07, 0.23),
					Vector3(rail_x, (RAIL_HEIGHT + 0.07) * 0.5, post_z))
		var mesh := ArrayMesh.new()
		for material_key: String in groups:
			var surface: SurfaceTool = groups[material_key]
			surface.commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, _material(material_key))
		var visual := MeshInstance3D.new()
		visual.name = "BridgeMesh"
		visual.mesh = mesh
		body.add_child(visual)
		stats["bridges"] += 1
		stats["bridge_meshes"] += 1
		stats["bridge_collision_shapes"] += body.get_child_count() - 1
	return stats

## Rectangular deck footprint, including both abutment end lines. Positive margin expands it.
static func bridge_contains(bridge: Dictionary, x: float, z: float, margin: float = 0.0) -> bool:
	if not _valid(bridge):
		return false
	var a := Vector2(float(bridge["ax"]), float(bridge["az"]))
	var span := Vector2(float(bridge["bx"]), float(bridge["bz"])) - a
	var length := span.length()
	var direction := span / length
	var relative := Vector2(x, z) - a
	var longitudinal := relative.dot(direction)
	var lateral := absf(relative.cross(direction))
	return longitudinal >= -margin and longitudinal <= length + margin and lateral <= float(bridge["width"]) * 0.5 + margin

## Highest deck at this point, or NAN when no bridge footprint contains it.
static func bridge_top_at(bridges: Array, x: float, z: float) -> float:
	var top := NAN
	for bridge: Dictionary in bridges:
		if bridge_contains(bridge, x, z):
			var candidate := float(bridge["deckY"])
			top = candidate if is_nan(top) else maxf(top, candidate)
	return top

static func _valid(bridge: Dictionary) -> bool:
	for key: String in ["ax", "az", "bx", "bz", "width", "deckY"]:
		if not bridge.has(key) or not is_finite(float(bridge[key])):
			return false
	var a := Vector2(float(bridge["ax"]), float(bridge["az"]))
	var b := Vector2(float(bridge["bx"]), float(bridge["bz"]))
	var thickness := float(bridge.get("thickness", 0.7))
	return a.distance_to(b) > 0.25 and float(bridge["width"]) >= 1.0 and is_finite(thickness) and thickness > 0.0

static func _solid_box(body: StaticBody3D, groups: Dictionary, label: String, material_key: String,
		size: Vector3, position: Vector3) -> void:
	_box_mesh(groups, material_key, size, position)
	_box_collision(body, label, size, position)

static func _box_mesh(groups: Dictionary, key: String, size: Vector3, position: Vector3,
		omit_normals: Array[Vector3] = []) -> void:
	if not groups.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		groups[key] = surface
	var primitive := BoxMesh.new()
	primitive.size = size
	var source: Mesh = primitive
	if not omit_normals.is_empty():
		var arrays := primitive.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var exterior := PackedInt32Array()
		for offset in range(0, indices.size(), 3):
			var hidden := false
			for normal: Vector3 in omit_normals:
				if normals[indices[offset]].dot(normal) > 0.99:
					hidden = true
					break
			if not hidden:
				exterior.append(indices[offset])
				exterior.append(indices[offset + 1])
				exterior.append(indices[offset + 2])
		arrays[Mesh.ARRAY_INDEX] = exterior
		var exposed := ArrayMesh.new()
		exposed.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		source = exposed
	var surface: SurfaceTool = groups[key]
	# BoxMesh supplies Godot's correct clockwise faces and outward normals.
	surface.append_from(source, 0, Transform3D(Basis.IDENTITY, position))

static func _box_collision(body: StaticBody3D, label: String, size: Vector3, position: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.name = label + "Collision"
	collision.shape = shape
	collision.position = position
	body.add_child(collision)

static func _material(key: String) -> StandardMaterial3D:
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.roughness = 0.96
	match key:
		"snow": material.albedo_color = Color(0.88, 0.93, 0.97)
		"asphalt": material.albedo_color = Color(0.19, 0.23, 0.26)
		"timber": material.albedo_color = Color(0.27, 0.23, 0.19)
		_: material.albedo_color = Color(0.48, 0.51, 0.51)
	material = KOTMWorldStyle.surface(material, key)
	_materials[key] = material
	return material
