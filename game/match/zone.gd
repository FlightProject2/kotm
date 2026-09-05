class_name Zone
extends Node3D
## Safe zone / toxic gas (docs 09): reveal banner, shrinking circles picked inside the previous
## one, linear closing, per-phase damage ticks. Logic is authority-side; visuals run everywhere.

signal state_changed(phase: int, state: String, seconds_left: float)

var schedule: Dictionary
var phases: Array = []
var half_size: float = 1000.0
var border: float = 60.0
var rng: RandomNumberGenerator
var time: float = 0.0
var phase: int = -1
var state: String = "wait"        # wait | reveal | warn | close | done
var t: float = 0.0
var center: Vector2 = Vector2.ZERO
var radius: float = 4000.0
var next_center: Vector2 = Vector2.ZERO
var next_radius: float = 4000.0
var dps: float = 0.0
var _start_r: float = 0.0
var _start_c: Vector2 = Vector2.ZERO
var _tick: float = 0.0
var _get_characters: Callable
var height_at: Callable
var wall: MeshInstance3D
var ring: MeshInstance3D

func start(p_schedule: Dictionary, p_half: float, p_border: float, p_rng: RandomNumberGenerator, characters: Callable, p_height_at: Callable) -> void:
	schedule = p_schedule
	phases = schedule["phases"]
	half_size = p_half
	border = p_border
	rng = p_rng
	_get_characters = characters
	height_at = p_height_at
	radius = half_size * 2.0
	next_radius = radius
	_build_visuals()

func _process(dt: float) -> void:
	if schedule.is_empty():
		return
	if multiplayer.is_server():
		advance(dt)
	_update_visuals()

## The timeline; separated from _process so tests can drive it deterministically.
func advance(dt: float) -> void:
	time += dt
	t += dt
	match state:
		"wait":
			if time >= float(schedule["revealBannerAtSec"]):
				_set_state("reveal")
		"reveal":
			var left := float(schedule["firstCircleShownAtSec"]) - time
			if left <= 0.0:
				phase = 0
				_pick_first_circle()
				_set_state("warn")
		"warn":
			var p: Dictionary = phases[phase]
			if t >= float(p["warningSec"]):
				_start_r = radius
				_start_c = center
				dps = float(p["dps"])
				_set_state("close")
		"close":
			var p: Dictionary = phases[phase]
			var k := clampf(t / maxf(float(p["closeSec"]), 0.001), 0.0, 1.0)
			radius = lerpf(_start_r, next_radius, k)
			center = _start_c.lerp(next_center, k)
			if k >= 1.0:
				if phase < phases.size() - 1:
					phase += 1
					_pick_next_circle()
					_set_state("warn")
				else:
					_set_state("done")
		"done":
			pass
	_damage_tick(dt)

func seconds_left() -> float:
	match state:
		"reveal": return maxf(0.0, float(schedule["firstCircleShownAtSec"]) - time)
		"warn": return maxf(0.0, float(phases[phase]["warningSec"]) - t)
		"close": return maxf(0.0, float(phases[phase]["closeSec"]) - t)
	return 0.0

func _set_state(s: String) -> void:
	state = s
	t = 0.0
	state_changed.emit(phase, state, seconds_left())
	Events.zone_state.emit(phase, state, seconds_left())
	if s == "reveal":
		Events.banner.emit("Revealing safe zone")
	elif s == "warn" and phase == 0:
		Events.banner.emit("Safe zone revealed. Check the compass.")

func _pick_first_circle() -> void:
	var r := float(phases[0]["radiusM"])
	var sample := float(schedule.get("firstCircleSampleRadiusM", half_size * 0.6))
	for i in 60:
		var a := rng.randf() * TAU
		var d := rng.randf() * sample
		var c := Vector2(cos(a) * d, sin(a) * d)
		if _fits(c, r):
			next_center = c
			next_radius = r
			return
	next_center = Vector2.ZERO
	next_radius = r

func _pick_next_circle() -> void:
	var r := float(phases[phase]["radiusM"])
	var prev_c := next_center
	var prev_r := next_radius
	for i in 60:
		var a := rng.randf() * TAU
		var d := rng.randf() * maxf(0.0, prev_r - r)
		var c := prev_c + Vector2(cos(a) * d, sin(a) * d)
		if _fits(c, r):
			next_center = c
			next_radius = r
			return
	next_center = prev_c
	next_radius = r

func _fits(c: Vector2, r: float) -> bool:
	var lim := half_size - border
	return absf(c.x) + r <= lim and absf(c.y) + r <= lim

func is_outside(p: Vector3) -> bool:
	return Vector2(p.x, p.z).distance_to(center) > radius

func distance_to_next_edge(p: Vector3) -> float:
	return Vector2(p.x, p.z).distance_to(next_center) - next_radius

func _damage_tick(dt: float) -> void:
	if phase < 0 or not _get_characters.is_valid():
		return
	_tick += dt
	if _tick < 1.0:
		return
	_tick -= 1.0
	var d := maxf(dps, 0.5)
	for ch in _get_characters.call():
		var c := ch as Character
		if c and c.alive() and is_outside(c.global_position):
			c.take_plain_damage(d, null, "Gas")

# ---- visuals ----
func _build_visuals() -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 320.0
	cyl.radial_segments = 96
	cyl.cap_top = false
	cyl.cap_bottom = false
	wall = MeshInstance3D.new()
	wall.name = "GasWall"
	wall.mesh = cyl
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform vec4 tint : source_color = vec4(0.38, 0.79, 0.29, 0.28);
void fragment() {
	float n = sin(UV.x * 120.0 + TIME * 0.6) * 0.5 + 0.5;
	float m = sin(UV.y * 40.0 - TIME * 0.9 + UV.x * 30.0) * 0.5 + 0.5;
	float a = tint.a * (0.7 + 0.3 * n * m);
	ALBEDO = tint.rgb;
	ALPHA = a;
}
"""
	sm.shader = sh
	wall.material_override = sm
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)
	ring = MeshInstance3D.new()
	ring.name = "NextRing"
	ring.mesh = cyl
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.albedo_color = Color(1, 1, 1, 0.14)
	rm.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	add_child(ring)

func _update_visuals() -> void:
	if wall == null:
		return
	var hy := float(height_at.call(center.x, center.y)) if height_at.is_valid() else 0.0
	wall.position = Vector3(center.x, hy + 60.0, center.y)
	wall.scale = Vector3(maxf(radius, 0.1), 1.0, maxf(radius, 0.1))
	wall.visible = phase >= 0
	ring.visible = state == "warn"
	if ring.visible:
		var ny := float(height_at.call(next_center.x, next_center.y)) if height_at.is_valid() else 0.0
		ring.position = Vector3(next_center.x, ny + 60.0, next_center.y)
		ring.scale = Vector3(maxf(next_radius, 0.1), 1.0, maxf(next_radius, 0.1))
