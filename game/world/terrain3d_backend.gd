class_name Terrain3DBackend
extends RefCounted
## Builds a Terrain3D node from the baked heightmap + colour map entirely in code
## (pattern from the addon's demo/src/CodeGenerated.gd). Terrain3D creates its material,
## assets and data on ready, so everything is configured in the ready callback.

static func build(world: World) -> Node3D:
	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
	terrain.ready.connect(_configure.bind(terrain, world), CONNECT_ONE_SHOT)
	return terrain

static func _configure(terrain: Node3D, world: World) -> void:
	# Properties must be set after ready: Terrain3D creates its sub-objects on tree entry.
	terrain.set("region_size", world.layout.region_size)
	terrain.set("vertex_spacing", world.layout.vertex_spacing)
	terrain.set("collision_mode", 3)          # Terrain3DCollision.FULL_GAME: whole map, node-less
	terrain.set("collision_layer", 1)
	terrain.set("collision_mask", 0)
	terrain.set("mesh_lods", 6)
	terrain.set("mesh_size", 48)
	var mat: Resource = terrain.get("material")
	if mat == null:
		mat = ClassDB.instantiate("Terrain3DMaterial")
		terrain.set("material", mat)
	mat.set("world_background", 0)              # NONE: nothing outside regions
	mat.set("auto_shader", true)
	mat.set("show_checkered", false)
	mat.call("set_shader_param", "auto_slope", 8.0)
	mat.call("set_shader_param", "auto_height_reduction", 0.05)
	var assets: Resource = ClassDB.instantiate("Terrain3DAssets")
	assets.call("set_texture", 0, _texture_asset("grass", Color(0.42, 0.52, 0.24), Color(0.36, 0.44, 0.20), 0.9))
	assets.call("set_texture", 1, _texture_asset("rock", Color(0.48, 0.46, 0.44), Color(0.34, 0.33, 0.32), 0.7))
	terrain.set("assets", assets)
	var half := world.layout.half_size
	var color_img: Image = world.colormap
	if color_img:
		color_img = color_img.duplicate()
		if color_img.get_format() != Image.FORMAT_RGBA8:
			color_img.convert(Image.FORMAT_RGBA8)
	var data: Object = terrain.get("data")
	data.call("import_images", [world.height_field.image, null, color_img], Vector3(-half, 0, -half), 0.0, 1.0)
	var cam: Camera3D = terrain.get_viewport().get_camera_3d() if terrain.get_viewport() else null
	if cam == null:
		cam = Camera3D.new()
		cam.name = "TerrainFallbackCamera"
		cam.position = Vector3(0, 300, 0)
		terrain.add_child(cam)
	terrain.call("set_camera", cam)

static func _texture_asset(asset_name: String, a: Color, b: Color, roughness: float) -> Resource:
	var ta: Resource = ClassDB.instantiate("Terrain3DTextureAsset")
	ta.set("name", asset_name)
	var img := Image.create_empty(256, 256, true, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = asset_name.hash()
	noise.frequency = 0.06
	noise.fractal_octaves = 4
	for y in 256:
		for x in 256:
			var n := (noise.get_noise_2d(x, y) + 1.0) * 0.5
			img.set_pixel(x, y, a.lerp(b, n))
	img.generate_mipmaps()
	ta.set("albedo_texture", ImageTexture.create_from_image(img))
	ta.set("uv_scale", 0.25)
	ta.set("roughness", roughness)
	return ta
