class_name TreePlacer
extends RefCounted
## Baked tree list -> MultiMesh chunks per species (Kenney Nature Kit, metallic fixed) plus
## node-less PhysicsServer3D trunk bodies so characters and bullets collide with trunks.

const SPECIES_SCALE := 8.0
const CHUNK := 256.0
const TRUNK_RADIUS := 0.32
const TRUNK_HEIGHT := 6.0
const VIS_RANGE := 700.0

static func build(world: World, parent: Node3D) -> Dictionary:
	var trees: Array = world.layout.trees
	var by_key: Dictionary = {}     # "species|cx|cz" -> Array[Transform3D]
	var meshes: Dictionary = {}
	var placed := 0
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
		_trunk_body(world, Vector3(x, y, z), s)
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
	var scene: PackedScene = load("res://assets/kenney/nature/%s.glb" % species)
	if scene == null:
		return null
	var inst := scene.instantiate()
	var mis := inst.find_children("*", "MeshInstance3D", true, false)
	if mis.is_empty():
		inst.free()
		return null
	var mi := mis[0] as MeshInstance3D
	var mesh: Mesh = mi.mesh.duplicate()
	# Kenney Nature Kit ships metallicFactor 1: force plain lit surfaces.
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m is BaseMaterial3D:
			var mm := (m as BaseMaterial3D).duplicate() as BaseMaterial3D
			mm.metallic = 0.0
			mm.roughness = 0.95
			# Vertex colours are decoded differently by the Compatibility (WebGL) renderer and wash
			# out to cyan-white; bake the surface's mean vertex colour into a plain albedo instead.
			if mm.vertex_color_use_as_albedo:
				var arrays := mesh.surface_get_arrays(i)
				var cols = arrays[Mesh.ARRAY_COLOR]
				if cols != null and cols.size() > 0:
					var acc := Color(0, 0, 0, 0)
					for c in cols:
						acc += c
					acc /= float(cols.size())
					mm.vertex_color_use_as_albedo = false
					mm.albedo_color = Color(acc.r, acc.g, acc.b, 1.0) * mm.albedo_color
			mesh.surface_set_material(i, mm)
	inst.free()
	return mesh

static func _trunk_body(world: World, pos: Vector3, s: float) -> void:
	var space := world.get_world_3d().space
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	var shape := PhysicsServer3D.cylinder_shape_create()
	PhysicsServer3D.shape_set_data(shape, {"radius": TRUNK_RADIUS * s / SPECIES_SCALE, "height": TRUNK_HEIGHT})
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(), Vector3(0, TRUNK_HEIGHT * 0.5, 0)))
	PhysicsServer3D.body_set_collision_layer(body, 1 | 32)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), pos))
	PhysicsServer3D.body_set_space(body, space)
	world.tree_bodies.append(body)
	world.tree_shapes.append(shape)
