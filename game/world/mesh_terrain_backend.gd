class_name MeshTerrainBackend
extends RefCounted
## Fallback terrain: a HeightMapShape3D collider from the heightmap plus a coarse visual
## mesh. Used headless and if Terrain3D is unavailable.

const VISUAL_STEP := 4

static func build(world: World) -> Node3D:
	var root := Node3D.new()
	root.name = "MeshTerrain"
	var hf := world.height_field
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = hf.size
	shape.map_depth = hf.size
	shape.map_data = hf.image.get_data().to_float32_array()
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	# HeightMapShape3D is centred on the body: sample 0 sits at -(size-1)/2, our pixel 0 at -half.
	var off := -hf.half + (hf.size - 1) * hf.spacing * 0.5
	body.position = Vector3(off, 0, off)
	body.scale = Vector3(hf.spacing, 1, hf.spacing)
	root.add_child(body)
	root.add_child(_visual(world))
	return root

static func _visual(world: World) -> MeshInstance3D:
	var hf := world.height_field
	var n := int(hf.size / VISUAL_STEP)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cm := world.colormap
	for j in range(n + 1):
		for i in range(n + 1):
			var px := mini(i * VISUAL_STEP, hf.size - 1)
			var pz := mini(j * VISUAL_STEP, hf.size - 1)
			var x := px * hf.spacing - hf.half
			var z := pz * hf.spacing - hf.half
			var c := cm.get_pixel(px, pz) if cm else Color(0.5, 0.6, 0.35)
			st.set_color(c)
			st.set_normal(hf.normal_at(x, z))
			st.add_vertex(Vector3(x, hf.raw(px, pz), z))
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			st.add_index(a); st.add_index(a + n + 1); st.add_index(a + 1)
			st.add_index(a + 1); st.add_index(a + n + 1); st.add_index(a + n + 2)
	var mi := MeshInstance3D.new()
	mi.name = "Visual"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	mi.material_override = m
	return mi
