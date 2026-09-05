class_name MeshTerrainBackend
extends RefCounted
## Fallback terrain: a HeightMapShape3D collider from the heightmap plus a textured visual mesh.
## Used headless, on the web build (Terrain3D has no wasm binary) and if Terrain3D fails.
## The material is fully procedural: a generated noise texture drives grass patches, dirt on
## roads (from the baked colour map carried in vertex colours), rock on slopes and snow on top.

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

const CHUNK_QUADS := 32   ## quads per chunk side (x VISUAL_STEP m); 2048 m -> 16 x 16 chunks

## The visual is chunked so the renderer can frustum-cull most of it (one 263k-vertex surface is
## always fully drawn) and so no single buffer gets huge on WebGL.
static func _visual(world: World) -> Node3D:
	var hf := world.height_field
	var n := int(hf.size / VISUAL_STEP)
	var cm := world.colormap
	var root := Node3D.new()
	root.name = "Visual"
	var mat := _pick_material()
	var chunks := int(ceil(float(n) / CHUNK_QUADS))
	for cj in chunks:
		for ci in chunks:
			var i0 := ci * CHUNK_QUADS
			var j0 := cj * CHUNK_QUADS
			var i1 := mini(i0 + CHUNK_QUADS, n)
			var j1 := mini(j0 + CHUNK_QUADS, n)
			var w := i1 - i0
			var h := j1 - j0
			if w <= 0 or h <= 0:
				continue
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var px := mini(i * VISUAL_STEP, hf.size - 1)
					var pz := mini(j * VISUAL_STEP, hf.size - 1)
					var x := px * hf.spacing - hf.half
					var z := pz * hf.spacing - hf.half
					var c := cm.get_pixel(px, pz) if cm else Color(0.5, 0.6, 0.35)
					st.set_color(c)
					st.set_normal(hf.normal_at(x, z))
					st.set_uv(Vector2(x, z) * 0.05)
					st.add_vertex(Vector3(x, hf.raw(px, pz), z))
			var stride := w + 1
			for j in h:
				for i in w:
					var a := j * stride + i
					st.add_index(a); st.add_index(a + stride); st.add_index(a + 1)
					st.add_index(a + 1); st.add_index(a + stride); st.add_index(a + stride + 1)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [ci, cj]
			mi.mesh = st.commit()
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			root.add_child(mi)
	print("MeshTerrain: visual chunks=%d material=%s" % [root.get_child_count(), _material_mode()])
	return root

static func _material_mode() -> String:
	var mode := "shader"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--terrain-mat="):
			mode = a.substr(14)
	return mode

static func _pick_material() -> Material:
	match _material_mode():
		"standard":
			var sm := StandardMaterial3D.new()
			sm.vertex_color_use_as_albedo = true
			sm.roughness = 1.0
			return sm
		"flat":
			var fm := StandardMaterial3D.new()
			fm.albedo_color = Color(0.35, 0.5, 0.2)
			fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			return fm
		"none":
			return null
		_:
			return make_material()

static var _noise_tex: ImageTexture

static func noise_texture() -> ImageTexture:
	if _noise_tex:
		return _noise_tex
	var n := 256
	var img := Image.create_empty(n, n, true, Image.FORMAT_RGB8)
	var a := FastNoiseLite.new(); a.seed = 11; a.frequency = 0.02; a.fractal_octaves = 3
	var b := FastNoiseLite.new(); b.seed = 23; b.frequency = 0.07; b.fractal_octaves = 4
	var c := FastNoiseLite.new(); c.seed = 37; c.noise_type = FastNoiseLite.TYPE_CELLULAR; c.frequency = 0.12
	for y in n:
		for x in n:
			img.set_pixel(x, y, Color((a.get_noise_2d(x, y) + 1.0) * 0.5, (b.get_noise_2d(x, y) + 1.0) * 0.5, (c.get_noise_2d(x, y) + 1.0) * 0.5))
	img.generate_mipmaps()
	_noise_tex = ImageTexture.create_from_image(img)
	return _noise_tex

static func make_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float macro_scale = 0.012;
uniform float detail_scale = 0.28;
uniform vec3 grass_a : source_color = vec3(0.33, 0.47, 0.19);
uniform vec3 grass_b : source_color = vec3(0.52, 0.58, 0.25);
uniform vec3 grass_dry : source_color = vec3(0.62, 0.58, 0.30);
uniform vec3 dirt : source_color = vec3(0.47, 0.37, 0.25);
uniform vec3 gravel : source_color = vec3(0.55, 0.53, 0.49);
uniform vec3 rock : source_color = vec3(0.47, 0.45, 0.43);
uniform vec3 snow : source_color = vec3(0.93, 0.94, 0.97);
uniform float snow_start = 116.0;
uniform float snow_full = 130.0;

varying vec3 v_world;
varying vec3 v_normal;
varying vec4 v_color;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_color = COLOR;
}

void fragment() {
	vec2 uv = v_world.xz;
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float detail_fade = 1.0 - smoothstep(120.0, 400.0, dist);
	vec3 macro = texture(noise_tex, uv * macro_scale).rgb;
	vec3 det = texture(noise_tex, uv * detail_scale).rgb;
	vec3 fine = texture(noise_tex, uv * detail_scale * 3.3).rgb;
	float slope = 1.0 - clamp(v_normal.y, 0.0, 1.0);

	// grass: patches from the macro noise, blades from the detail cells
	vec3 grass = mix(grass_a, grass_b, macro.r);
	grass = mix(grass, grass_dry, smoothstep(0.62, 0.8, macro.g));
	float blades = mix(1.0, 0.72 + 0.56 * det.b, detail_fade);
	grass *= blades * (0.9 + 0.2 * fine.g * detail_fade);

	// roads from the baked colour map (brown = dirt road, neutral grey = rail bed)
	vec3 tint = v_color.rgb;
	float roadness = clamp((tint.r - tint.g) * 7.0 + 0.45, 0.0, 1.0);
	float grey = 1.0 - clamp((abs(tint.r - tint.g) + abs(tint.g - tint.b)) * 12.0, 0.0, 1.0);
	float railness = grey * step(0.35, tint.r) * (1.0 - roadness);
	vec3 dirt_col = dirt * (0.8 + 0.4 * det.r) * (0.92 + 0.16 * fine.r);
	vec3 col = mix(grass, dirt_col, roadness);
	col = mix(col, gravel * (0.85 + 0.3 * det.g), railness * 0.8);

	// rock on slopes, snow on the peak
	float rockness = smoothstep(0.22, 0.48, slope + (det.r - 0.5) * 0.12);
	vec3 rock_col = rock * (0.75 + 0.5 * det.g) * (0.9 + 0.2 * fine.b);
	col = mix(col, rock_col, rockness);
	float snowness = smoothstep(snow_start, snow_full, v_world.y + (macro.b - 0.5) * 10.0) * (1.0 - smoothstep(0.35, 0.6, slope));
	col = mix(col, snow * (0.94 + 0.06 * det.b), snowness);

	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.8, snowness);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("noise_tex", noise_texture())
	return mat
