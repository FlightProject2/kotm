class_name TracerRenderer
extends MeshInstance3D
## Draws every bullet's trail for everyone (docs 05): a pale-yellow line from the muzzle to the
## integrated position, following the same ballistics, fading 0.15 s after it stops.

class Tracer:
	var start: Vector3
	var pos: Vector3
	var vel: Vector3
	var g: float
	var stopped: bool = false
	var fade: float = 0.15
	var dist: float = 0.0

var tracers: Array[Tracer] = []
var world: World
var _im := ImmediateMesh.new()

func _ready() -> void:
	mesh = _im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.95, 0.69, 0.9)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.9, 0.6)
	m.emission_energy_multiplier = 2.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Events.tracer.connect(_on_tracer)

func _on_tracer(_shooter_id: int, origin: Vector3, velocity: Vector3, weapon_id: String) -> void:
	var t := Tracer.new()
	t.start = origin
	t.pos = origin
	t.vel = velocity
	var def := ItemCatalog.weapon_def(weapon_id)
	t.g = Ballistics.gravity_for(def) if not def.is_empty() else 9.81
	tracers.append(t)

func _process(dt: float) -> void:
	if tracers.is_empty():
		_im.clear_surfaces()
		return
	var space := get_world_3d().direct_space_state
	for t in tracers:
		if t.stopped:
			t.fade -= dt
			continue
		var remaining := dt
		while remaining > 0.0 and not t.stopped:
			var sub := minf(remaining, Ballistics.substep_dt(t.vel))
			remaining -= sub
			t.vel.y -= t.g * sub
			var to := t.pos + t.vel * sub
			var q := PhysicsRayQueryParameters3D.create(t.pos, to, 1 | 4 | 16)
			q.collide_with_areas = true
			var hit := space.intersect_ray(q)
			var tt := world.height_field.segment_hit(t.pos, to, 1.0) if world else -1.0
			if not hit.is_empty() or tt >= 0.0:
				t.pos = hit["position"] if not hit.is_empty() else t.pos.lerp(to, tt)
				t.stopped = true
			else:
				t.dist += t.pos.distance_to(to)
				t.pos = to
				if t.dist > 800.0:
					t.stopped = true
	tracers = tracers.filter(func(x: Tracer) -> bool: return not (x.stopped and x.fade <= 0.0))
	_im.clear_surfaces()
	if tracers.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_LINES)
	for t in tracers:
		var a := clampf(t.fade / 0.15, 0.0, 1.0)
		var col := Color(1.0, 0.95, 0.69, a)
		_im.surface_set_color(col)
		_im.surface_add_vertex(t.start)
		_im.surface_set_color(col)
		_im.surface_add_vertex(t.pos)
	_im.surface_end()
