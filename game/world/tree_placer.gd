class_name TreePlacer
extends RefCounted
## Baked tree list -> MultiMesh chunks per species (Kenney Nature Kit, metallic fixed) plus
## node-less PhysicsServer3D trunk bodies so characters and bullets collide with trunks.

const SPECIES_SCALE := 8.0
const CHUNK := 256.0
const TRUNK_RADIUS := 0.32
const TRUNK_HEIGHT := 6.0
const VIS_RANGE := 700.0

static var _snow_foliage_material: ShaderMaterial

static func build(world: World, parent: Node3D) -> Dictionary:
	var trees: Array = world.layout.trees
	var by_key: Dictionary = {}     # "species|cx|cz" -> Array[Transform3D]
	var meshes: Dictionary = {}
	var placed := 0
	var trunk_bodies: Dictionary = {}
	for t in trees:
		var x := float(t[0])
		var z := float(t[1])
		var species: String = t[2]
		var s := float(t[3]) * SPECIES_SCALE
		var rot := float(t[4])
		if not meshes.has(species):
			meshes[species] = _mesh_for(species)
		if meshes[species] == null:
			continue
		var y := world.height_at(x, z)
		var key := "%s|%d|%d" % [species, floori(x / CHUNK), floori(z / CHUNK)]
		if not by_key.has(key):
			by_key[key] = []
		var xf := Transform3D(Basis(Vector3.UP, rot).scaled(Vector3.ONE * s), Vector3(x, y + 0.05 * s * 0.5, z))
		by_key[key].append(xf)
		var trunk_cell := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
		if not trunk_bodies.has(trunk_cell):
			var origin := Vector3(trunk_cell.x * CHUNK, 0.0, trunk_cell.y * CHUNK)
			trunk_bodies[trunk_cell] = {"body": _create_trunk_body(world, origin), "origin": origin}
		var trunk_info: Dictionary = trunk_bodies[trunk_cell]
		_trunk_shape(world, trunk_info["body"], Vector3(x, y, z) - trunk_info["origin"], s)
		placed += 1
	for key in by_key:
		var species: String = key.split("|")[0]
		var xfs: Array = by_key[key]
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Trees_" + key.replace("|", "_")
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[species]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		mmi.multimesh = mm
		mmi.visibility_range_end = VIS_RANGE
		mmi.visibility_range_end_margin = 60.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(mmi)
	return {"trees": placed, "chunks": by_key.size()}

static func _mesh_for(species: String) -> Mesh:
	var source_path := "res://assets/kenney/nature/%s.glb" % species
	var selected_path := KOTMWorldStyle.path(source_path)
	var scene: PackedScene = load(selected_path)
	if scene == null:
		return null
	var inst := scene.instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		inst.free()
		return null
	var mi := mis[0] as MeshInstance3D
	var mesh: Mesh = mi.mesh.duplicate()
	if selected_path != source_path:
		# Styled glTF bakes the winter palette and upper-branch snow into vertex colours.
		inst.free()
		return mesh
	# Kenney Nature Kit ships metallicFactor 1: force plain lit surfaces.
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m is BaseMaterial3D:
			var mm := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			mm.metallic = 0.0
			mm.roughness = 0.95
			# The kit's colours arrive as odd vertex/base colours (cyan foliage on WebGL): classify the
			# surface by hue and give it a plain, renderer-independent palette colour.
			var c := mm.albedo_color
			var arrays := mesh.surface_get_arrays(i)
			var cols = arrays[Mesh.ARRAY_COLOR]
			if cols != null and cols.size() > 0:
				var acc := Color(0, 0, 0, 0)
				for vc in cols:
					acc += vc
				acc /= float(cols.size())
				c = Color(acc.r, acc.g, acc.b, 1.0) * c
			mm.vertex_color_use_as_albedo = false
			if c.g >= c.r and c.g >= c.b * 0.9 and c.g > 0.3:
				mesh.surface_set_material(i, _foliage_material())
				continue
			elif c.r > c.g and c.g > c.b:
				mm.albedo_color = Color(0.33, 0.25, 0.18)      # trunk / wood
			else:
				mm.albedo_color = Color(0.55, 0.53, 0.50)      # rock / other
			mesh.surface_set_material(i, mm)
	inst.free()
	return mesh

static func _foliage_material() -> ShaderMaterial:
	if _snow_foliage_material:
		return _snow_foliage_material
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode diffuse_lambert;

uniform vec3 spruce : source_color = vec3(0.12, 0.23, 0.18);
uniform vec3 snow : source_color = vec3(0.88, 0.93, 0.97);
varying vec3 local_normal;

void vertex() {
	// Trees rotate only around Y and scale uniformly, so local up remains world up.
	local_normal = NORMAL;
}

void fragment() {
	// Accumulation follows the upper branch faces; undersides retain dark needles.
	float coverage = smoothstep(0.10, 0.48, normalize(local_normal).y);
	ALBEDO = mix(spruce, snow, coverage);
	METALLIC = 0.0;
	ROUGHNESS = 0.97;
	SPECULAR = 0.18;
}
"""
	_snow_foliage_material = ShaderMaterial.new()
	_snow_foliage_material.shader = shader
	return _snow_foliage_material

static func _create_trunk_body(world: World, origin: Vector3) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(body, 1 | 32)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis.IDENTITY, origin))
	PhysicsServer3D.body_set_space(body, world.get_world_3d().space)
	world.tree_bodies.append(body)
	return body

static func _trunk_shape(world: World, body: RID, pos: Vector3, s: float) -> void:
	var shape := PhysicsServer3D.cylinder_shape_create()
	PhysicsServer3D.shape_set_data(shape, {"radius": TRUNK_RADIUS * s / SPECIES_SCALE, "height": TRUNK_HEIGHT})
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(), pos + Vector3(0, TRUNK_HEIGHT * 0.5, 0)))
	world.tree_shapes.append(shape)
