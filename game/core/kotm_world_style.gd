class_name KOTMWorldStyle
extends RefCounted
## Visual derivatives only. Source assets, gameplay pivots and colliders retain their contracts.

const PATHS := "res://assets/styled/paths.json"
static var _paths: Dictionary = {}
static var _loaded := false
static var _materials: Dictionary = {}
static var _textures: Dictionary = {}

static func path(source: String) -> String:
	if not _loaded:
		_loaded = true
		if FileAccess.file_exists(PATHS):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATHS))
			if parsed is Dictionary:
				_paths = parsed
	var derived := String(_paths.get(source, ""))
	return derived if not derived.is_empty() and ResourceLoader.exists(derived) else source

static func surface(source: StandardMaterial3D, role: String) -> StandardMaterial3D:
	var key := str(source.get_rid()) + ":" + role
	if _materials.has(key):
		return _materials[key]
	var material := source.duplicate() as StandardMaterial3D
	var kind := {"white": "paint", "wood": "timber", "bell": "metal", "asphalt": "ground"}.get(role, role) as String
	if not kind in ["snow", "paint", "timber", "metal", "ground", "stone", "concrete", "fabric", "rubber", "glass", "foliage"]:
		kind = "concrete"
	material.resource_name = "KOTM_" + kind + "_procedural"
	material.metallic = 0.55 if kind == "metal" else 0.0
	material.roughness = 1.0
	var rough_path := "res://assets/styled/textures/" + kind + "_roughness.png"
	var color_path := "res://assets/styled/textures/" + kind + "_variation.png"
	if ResourceLoader.exists(rough_path):
		if not _textures.has(rough_path):
			_textures[rough_path] = load(rough_path)
		material.roughness_texture = _textures[rough_path]
		material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	if material.albedo_texture == null and ResourceLoader.exists(color_path):
		if not _textures.has(color_path):
			_textures[color_path] = load(color_path)
		material.albedo_texture = _textures[color_path]
	material.uv1_triplanar = true
	material.uv1_scale = Vector3.ONE * 0.9
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_materials[key] = material
	return material
