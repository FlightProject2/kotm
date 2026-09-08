class_name MeshTerrainBackend
extends RefCounted
## The game's terrain: a HeightMapShape3D collider from the baked heightmap plus chunked visual
## meshes with the snow-biome shader. Same on desktop, web and headless.
## The material is fully procedural: a generated noise texture drives grass patches, dirt on
## roads (from the baked colour map carried in vertex colours), rock on slopes and snow on top.

const VISUAL_STEP := 1   # one visual vertex per height sample: the mesh IS the collider

static func build(world: World) -> Node3D:
	var root := Node3D.new()
	root.name = "MeshTerrain"
	var hf := world.height_field
	var body := StaticBody3D.new()
	body.name = "Collision"
	# No dedicated snow recording was supplied; use the soft grass step outdoors.
	body.set_meta("audio_surface", "grass")
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

const CHUNK_QUADS := 64   ## quads per chunk side (x sample spacing); 1024 samples -> 16 x 16 chunks of 128 m

## The visual is chunked so the renderer can frustum-cull most of it (one 263k-vertex surface is
## always fully drawn) and so no single buffer gets huge on WebGL.
static func _visual(world: World) -> Node3D:
	var hf := world.height_field
	var n := int(hf.size / VISUAL_STEP)
	var cm := world.colormap
	var root := Node3D.new()
	root.name = "Visual"
	var mat := _pick_material(world)
	var chunks := int(ceil(float(n) / CHUNK_QUADS))
	# raw heights once (Image.get_pixel per vertex is the slow path)
	var heights := hf.image.get_data().to_float32_array()
	var sz := hf.size
	var sp := hf.spacing
	var half := hf.half
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
			var stride := w + 1
			var count := stride * (h + 1)
			var verts := PackedVector3Array(); verts.resize(count)
			var norms := PackedVector3Array(); norms.resize(count)
			var uvs := PackedVector2Array(); uvs.resize(count)
			var uv2s := PackedVector2Array(); uv2s.resize(count)
			var cols := PackedColorArray(); cols.resize(count)
			var k := 0
			for j in range(j0, j1 + 1):
				var pz := mini(j * VISUAL_STEP, sz - 1)
				var z := pz * sp - half
				for i in range(i0, i1 + 1):
					var px := mini(i * VISUAL_STEP, sz - 1)
					var x := px * sp - half
					var y := heights[pz * sz + px]
					# central-difference normal from the same samples the collider uses
					var xl := heights[pz * sz + maxi(px - 1, 0)]
					var xr := heights[pz * sz + mini(px + 1, sz - 1)]
					var zl := heights[maxi(pz - 1, 0) * sz + px]
					var zr := heights[mini(pz + 1, sz - 1) * sz + px]
					var nrm := Vector3(xl - xr, 2.0 * sp, zl - zr).normalized()
					verts[k] = Vector3(x, y, z)
					norms[k] = nrm
					uvs[k] = Vector2(x, z) * 0.05
					uv2s[k] = Vector2(1.0 - clampf(nrm.y, 0.0, 1.0), y / 256.0)
					cols[k] = cm.get_pixel(mini(px * int(cm.get_width() / sz), cm.get_width() - 1), mini(pz * int(cm.get_height() / sz), cm.get_height() - 1)) if cm else Color(0.5, 0.6, 0.35)
					k += 1
			var idx := PackedInt32Array(); idx.resize(w * h * 6)
			var q := 0
			for j in h:
				for i in w:
					var a := j * stride + i
					idx[q] = a; idx[q + 1] = a + stride; idx[q + 2] = a + 1
					idx[q + 3] = a + 1; idx[q + 4] = a + stride; idx[q + 5] = a + stride + 1
					q += 6
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_TEX_UV2] = uv2s
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.name = "Chunk_%d_%d" % [ci, cj]
			mi.mesh = mesh
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

static func _pick_material(world: World = null) -> Material:
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
			return make_material(world.colormap if world else null, world.height_field.half if world else 1024.0)

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

static var _colormap_tex: ImageTexture

static func make_material(colormap: Image = null, half_size := 1024.0) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx;   // two-sided: a camera that dips under a slope still sees ground

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D colormap_tex : filter_linear, repeat_disable;
uniform float half_size = 1024.0;
uniform float use_colormap = 0.0;
uniform float macro_scale = 0.010;
uniform float detail_scale = 0.22;
uniform vec3 snow_a : source_color = vec3(0.90, 0.93, 0.97);
uniform vec3 snow_b : source_color = vec3(0.80, 0.86, 0.94);
uniform vec3 snow_shadow : source_color = vec3(0.62, 0.72, 0.86);
uniform vec3 packed_road : source_color = vec3(0.66, 0.68, 0.72);
uniform vec3 mud_road : source_color = vec3(0.36, 0.30, 0.25);
uniform vec3 rock : source_color = vec3(0.34, 0.33, 0.34);
uniform vec3 rock_lit : source_color = vec3(0.52, 0.50, 0.48);
uniform vec3 thaw_grass : source_color = vec3(0.42, 0.45, 0.30);
uniform float thaw_below = 11.0;   // low, sheltered ground shows some dead grass through the snow

varying vec3 v_world;
varying vec2 v_slope_h;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_slope_h = UV2;   // x = slope (0 flat .. 1 vertical), y = height / 256
}

void fragment() {
	vec2 uv = v_world.xz;
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float detail_fade = 1.0 - smoothstep(90.0, 320.0, dist);
	vec3 macro = texture(noise_tex, uv * macro_scale).rgb;
	vec3 det = texture(noise_tex, uv * detail_scale).rgb;
	vec3 fine = texture(noise_tex, uv * detail_scale * 3.7).rgb;
	float slope = clamp(v_slope_h.x, 0.0, 1.0);
	float height = v_slope_h.y * 256.0;

	// snow: wind-drift streaks from the macro noise, sparkle-scale grain up close
	vec3 snow = mix(snow_a, snow_b, macro.r);
	float drift = smoothstep(0.35, 0.75, macro.g + (det.r - 0.5) * 0.35);
	snow = mix(snow, snow_shadow, drift * 0.35);
	float grain = mix(1.0, 0.92 + 0.16 * fine.g, detail_fade);
	snow *= grain;

	// roads from the baked colour map: brown = ploughed/mud track, grey = packed snow / rail bed
	vec3 tint = use_colormap > 0.5 ? texture(colormap_tex, (v_world.xz + vec2(half_size)) / (2.0 * half_size)).rgb : vec3(0.45, 0.55, 0.3);
	float roadness = clamp((tint.r - tint.g) * 7.0 + 0.45, 0.0, 1.0);
	float grey = 1.0 - clamp((abs(tint.r - tint.g) + abs(tint.g - tint.b)) * 12.0, 0.0, 1.0);
	float railness = grey * step(0.35, tint.r) * (1.0 - roadness);
	vec3 col = mix(snow, mix(packed_road, mud_road, 0.35 + 0.4 * det.r), roadness * 0.85);
	col = mix(col, packed_road * (0.9 + 0.2 * det.g), railness * 0.7);

	// thaw patches in low ground, rock where it is too steep for snow to hold
	float thaw = (1.0 - smoothstep(thaw_below - 4.0, thaw_below + 3.0, height)) * smoothstep(0.62, 0.8, macro.b + det.g * 0.15);
	col = mix(col, thaw_grass * (0.85 + 0.3 * det.b), thaw * 0.45 * (1.0 - roadness));
	float rockness = smoothstep(0.30, 0.52, slope + (det.r - 0.5) * 0.10);
	vec3 rock_col = mix(rock, rock_lit, det.g) * (0.9 + 0.2 * fine.b);
	// snow still clings to ledges: keep a dusting on rock facing up
	rock_col = mix(rock_col, snow_a, (1.0 - slope) * 0.25);
	col = mix(col, rock_col, rockness);

	ALBEDO = col;
	ROUGHNESS = mix(0.55, 0.9, rockness);   // fresh snow is slightly glossy
	SPECULAR = 0.25;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("noise_tex", noise_texture())
	mat.set_shader_parameter("half_size", half_size)
	if colormap != null:
		if _colormap_tex == null:
			var img := colormap.duplicate() as Image
			if img.get_format() != Image.FORMAT_RGB8 and img.get_format() != Image.FORMAT_RGBA8:
				img.convert(Image.FORMAT_RGBA8)
			_colormap_tex = ImageTexture.create_from_image(img)
		mat.set_shader_parameter("colormap_tex", _colormap_tex)
		mat.set_shader_parameter("use_colormap", 1.0)
	return mat
