class_name AlpineAtmosphere
extends Node3D
## Local presentation only. Never changes damage, collisions, AI or the zone RNG.
## Owned by World, so snow, beacon and the private Environment leave with the match.

var world: World
var zone: SummitZone
var viewer: Character
var snow: CPUParticles3D
var _environment: Environment
var _exposure := 0.0
var _roof_timer := 0.0
var _sheltered := false
var _fog_allowed := true

func _ready() -> void:
	name = "AlpineAtmosphere"
	if DisplayServer.get_name() == "headless" or world == null or zone == null:
		set_process(false)
		set_physics_process(false)
		return
	var holder := world.get_node_or_null("Env") as WorldEnvironment
	if holder and holder.environment:
		_environment = holder.environment.duplicate(true) as Environment
		holder.environment = _environment
		# Honour the existing --env=nofog / --env=plain diagnostic switches.
		_fog_allowed = _environment.fog_enabled
		_environment.fog_mode = Environment.FOG_MODE_DEPTH
		_environment.fog_density = 1.0
		_environment.fog_depth_curve = 1.0
	if zone.has_summit_finish():
		_build_beacon()
	_build_snow()

func _build_beacon() -> void:
	var target := zone.summit_target()
	var beacon := MeshInstance3D.new()
	beacon.name = "SummitBeacon"
	var beam := CylinderMesh.new()
	beam.top_radius = 0.6
	beam.bottom_radius = 1.3
	beam.height = 240.0
	beam.radial_segments = 12
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1.0, 0.045, 0.12, 0.72)
	beacon.mesh = beam
	beacon.material_override = material
	beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beacon.position = Vector3(target.x, world.height_at(target.x, target.y) + 122.0, target.y)
	add_child(beacon)

func _build_snow() -> void:
	snow = CPUParticles3D.new()
	snow.name = "LocalSnow"
	snow.emitting = false
	snow.amount = 160 if OS.has_feature("web") else 320
	snow.lifetime = 6.0
	snow.preprocess = 2.0
	snow.fixed_fps = 30
	snow.local_coords = false
	snow.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	snow.emission_box_extents = Vector3(13.0, 3.0, 13.0)
	snow.direction = Vector3(0.3, -1.0, 0.1).normalized()
	snow.spread = 18.0
	snow.gravity = Vector3(0.2, -0.35, 0.05)
	snow.initial_velocity_min = 1.4
	snow.initial_velocity_max = 2.8
	snow.scale_amount_min = 0.5
	snow.scale_amount_max = 1.3
	snow.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 16
	texture.height = 16
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.albedo_color = Color(0.92, 0.97, 1.0, 0.72)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.09)
	quad.material = material
	snow.mesh = quad
	add_child(snow)
	if is_instance_valid(viewer):
		snow.global_position = viewer.global_position + Vector3.UP * 7.0
	snow.emitting = true

func _physics_process(dt: float) -> void:
	if not is_instance_valid(viewer) or snow == null:
		return
	_roof_timer -= dt
	if _roof_timer > 0.0:
		return
	_roof_timer = 0.2
	# One short overhead test at 5 Hz; no flakes rendered through a roof.
	var start := viewer.global_position + Vector3.UP * 1.6
	var query := PhysicsRayQueryParameters3D.create(start, start + Vector3.UP * 30.0, 1)
	query.exclude = [viewer.get_rid()]
	_sheltered = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	snow.visible = not _sheltered
	snow.emitting = not _sheltered

func _process(dt: float) -> void:
	if not is_instance_valid(viewer) or not is_instance_valid(zone) or snow == null:
		return
	_exposure = lerpf(_exposure, zone.exposure_at(viewer.global_position), 1.0 - exp(-dt * 2.5))
	var camera := get_viewport().get_camera_3d()
	if camera:
		snow.global_position = camera.global_position + Vector3.UP * 7.0
	snow.speed_scale = lerpf(0.85, 1.9, _exposure)
	if _environment and _fog_allowed:
		_environment.fog_depth_begin = lerpf(220.0, 5.0, _exposure)
		_environment.fog_depth_end = lerpf(1900.0, 85.0, _exposure)
		_environment.fog_light_color = Color(0.69, 0.79, 0.87).lerp(Color(0.84, 0.9, 0.95), _exposure)
		_environment.fog_sky_affect = lerpf(0.25, 0.85, _exposure)
