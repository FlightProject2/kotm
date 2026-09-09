extends Node3D
## Original procedural KOTM muzzle effect. Local +Z always points out of the barrel.
## Meshes, vertex colors and a short unshadowed light work in Compatibility and Vulkan.

var transform_provider: Callable
var active_weapon := ""
var shot_count := 0
var elapsed := 1.0
var flash_duration := 0.065
var smoke_duration := 0.26
var peak_light_energy := 1.6
var flame_length := 0.25
var flame_radius := 0.045
var flame: Node3D
var smoke: MeshInstance3D
var light: OmniLight3D
var core: MeshInstance3D
var outer: MeshInstance3D
var rays: MeshInstance3D
var _smoke_material: StandardMaterial3D
var _core_material: StandardMaterial3D
var _outer_material: StandardMaterial3D
var _ray_material: StandardMaterial3D
var _rng := RandomNumberGenerator.new()
var _built := false
static var _core_mesh: ArrayMesh
static var _outer_mesh: ArrayMesh
static var _ray_mesh: ArrayMesh
static var _smoke_mesh: SphereMesh

func _ready() -> void:
	# Keep bone and weapon scale from stretching the burst, and update after animations.
	top_level = true
	process_priority = 100
	_rng.seed = get_instance_id() * 7919
	_build()
	stop()

func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = false
	return material

func _flame_mesh(outer_layer: bool) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var sides := 16
	# Narrow hot base, expanding shoulder, then uneven flame tips fading to nothing.
	var rings := [Vector2(0.012, 0.19), Vector2(0.20, 0.52), Vector2(0.52, 0.38), Vector2(1.0, 0.015)]
	if outer_layer:
		rings = [Vector2(0.006, 0.26), Vector2(0.23, 0.93), Vector2(0.54, 0.59), Vector2(1.0, 0.005)]
	for ring in range(rings.size()):
		for side in sides:
			var angle := float(side) * TAU / sides
			var lobe := 0.70 + 0.30 * cos(angle * 4.0 + 0.35) if outer_layer else 1.0
			var radius: float = rings[ring].y * lobe
			var along: float = rings[ring].x
			if outer_layer and ring >= 2:
				along *= 0.88 + 0.12 * cos(angle * 3.0)
			vertices.append(Vector3(cos(angle) * radius, sin(angle) * radius, along))
			var color := Color(1.0, 0.95, 0.67, 0.90)
			if outer_layer:
				color = [Color(1, 0.67, 0.18, 0.65), Color(1, 0.46, 0.06, 0.52), Color(1, 0.22, 0.015, 0.25), Color(0.9, 0.08, 0.005, 0.0)][ring]
			else:
				color = [Color(1, 0.99, 0.83, 1), Color(1, 0.94, 0.57, 0.98), Color(1, 0.64, 0.16, 0.70), Color(1, 0.30, 0.02, 0.0)][ring]
			colors.append(color)
	for ring in range(rings.size() - 1):
		for side in sides:
			var a := ring * sides + side
			var b := ring * sides + (side + 1) % sides
			indices.append_array(PackedInt32Array([a, b, b + sides, a, b + sides, a + sides]))
	return _array_mesh(vertices, colors, indices)

func _rays_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	# Four tapered gas tongues, never a camera-facing square.
	for ray in 4:
		var a := TAU * float(ray) / 4.0
		var axis := Vector3(cos(a), sin(a), 0)
		var side := Vector3(-sin(a), cos(a), 0)
		var first := vertices.size()
		vertices.append_array(PackedVector3Array([axis * 0.20 + Vector3(0, 0, 0.07), axis * 0.57 + side * 0.15 + Vector3(0, 0, 0.19), axis * 1.48 + Vector3(0, 0, 0.37), axis * 0.57 - side * 0.15 + Vector3(0, 0, 0.19)]))
		colors.append_array(PackedColorArray([Color(1, 0.95, 0.5, 0.8), Color(1, 0.50, 0.04, 0.50), Color(1, 0.17, 0, 0.0), Color(1, 0.50, 0.04, 0.50)]))
		indices.append_array(PackedInt32Array([first, first + 1, first + 2, first, first + 2, first + 3]))
	return _array_mesh(vertices, colors, indices)

func _array_mesh(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _mesh_node(node_name: String, mesh: Mesh, material: Material, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _build() -> void:
	if _built:
		return
	_built = true
	if _core_mesh == null:
		_core_mesh = _flame_mesh(false)
		_outer_mesh = _flame_mesh(true)
		_ray_mesh = _rays_mesh()
		_smoke_mesh = SphereMesh.new()
		_smoke_mesh.radius = 0.5
		_smoke_mesh.height = 1.0
		_smoke_mesh.radial_segments = 12
		_smoke_mesh.rings = 6
	flame = Node3D.new()
	flame.name = "LayeredFlame"
	add_child(flame)
	_core_material = _material()
	_outer_material = _material()
	_ray_material = _material()
	_core_material.cull_mode = BaseMaterial3D.CULL_BACK
	_outer_material.cull_mode = BaseMaterial3D.CULL_BACK
	core = _mesh_node("WhiteYellowCore", _core_mesh, _core_material, flame)
	core.scale = Vector3(0.78, 0.78, 0.67)
	outer = _mesh_node("OrangeEnvelope", _outer_mesh, _outer_material, flame)
	rays = _mesh_node("SideGasTongues", _ray_mesh, _ray_material, flame)
	_smoke_material = StandardMaterial3D.new()
	_smoke_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_material.albedo_color = Color(0.29, 0.31, 0.33, 0)
	smoke = _mesh_node("BriefSmoke", _smoke_mesh, _smoke_material, self)
	light = OmniLight3D.new()
	light.name = "WarmMuzzleLight"
	light.light_color = Color(1, 0.58, 0.17)
	light.light_energy = 0
	light.omni_range = 1.8
	light.shadow_enabled = false
	add_child(light)

func trigger(weapon_id: String, muzzle_world: Transform3D) -> void:
	_build()
	active_weapon = weapon_id
	shot_count += 1
	elapsed = 0
	var is_ak := weapon_id == "ak47"
	flash_duration = 0.082 if is_ak else 0.065
	flame_length = 0.34 if is_ak else 0.25
	flame_radius = 0.069 if is_ak else 0.046
	peak_light_energy = 2.1 if is_ak else 1.6
	if weapon_id not in ["ar15", "ak47", "hunting_rifle"]:
		flame_length = 0.16
		flame_radius = 0.035
		peak_light_energy = 1.1
	var variation := _rng.randf_range(0.88, 1.12)
	flame_length *= variation
	flame_radius *= variation
	global_transform = Transform3D(muzzle_world.basis.orthonormalized(), muzzle_world.origin)
	flame.rotation.z = _rng.randf_range(0, TAU)
	outer.scale = Vector3(1.0, 1.0, 1.12 if is_ak else 0.97)
	rays.rotation.z = 0.45 if is_ak else 0.0
	light.light_color = Color(1.0, 0.47, 0.10) if is_ak else Color(1.0, 0.66, 0.25)
	visible = true
	set_process(true)
	advance_effect(0)

func follow_muzzle() -> void:
	if is_flashing() and transform_provider.is_valid():
		var sampled: Transform3D = transform_provider.call()
		global_transform = Transform3D(sampled.basis.orthonormalized(), sampled.origin)

func is_flashing() -> bool:
	return visible and elapsed < flash_duration

func _process(delta: float) -> void:
	advance_effect(delta)

func advance_effect(delta: float) -> void:
	if not visible:
		return
	elapsed += delta
	if elapsed >= smoke_duration:
		stop()
		return
	follow_muzzle()
	var life := clampf(elapsed / flash_duration, 0, 1)
	var pulse := pow(1.0 - life, 1.25)
	flame.visible = life < 1
	flame.scale = Vector3(flame_radius, flame_radius, flame_length) * (0.85 + 0.15 * pulse)
	_core_material.albedo_color.a = pulse
	_outer_material.albedo_color.a = pulse * 0.68
	_ray_material.albedo_color.a = pulse * (1.0 if active_weapon == "ak47" else 0.75)
	light.light_energy = peak_light_energy * pulse * pulse
	light.visible = life < 1
	light.position.z = 0.045
	var smoke_life := clampf((elapsed - 0.025) / (smoke_duration - 0.025), 0, 1)
	smoke.visible = elapsed > 0.025
	_smoke_material.albedo_color.a = sin(smoke_life * PI) * 0.10
	smoke.position = Vector3(0, smoke_life * 0.06, 0.045 + smoke_life * 0.10)
	smoke.scale = Vector3.ONE * (0.018 + smoke_life * 0.13)

func stop() -> void:
	visible = false
	elapsed = smoke_duration
	set_process(false)
	if _built:
		flame.visible = false
		smoke.visible = false
		light.visible = false
		light.light_energy = 0
