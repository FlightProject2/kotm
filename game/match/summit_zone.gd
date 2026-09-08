class_name SummitZone
extends Zone
## Opt-in whiteout rules on the existing authority-side zone timeline.
## This is summit-directed radial pressure, not an altitude damage plane.

const CIRCLES := preload("res://game/match/summit_circle_picker.gd")
const WALL_SHADER := preload("res://game/match/whiteout_wall.gdshader")

func is_whiteout() -> bool:
	return str(schedule.get("theme", "gas")) == "whiteout"

func summit_target() -> Vector2:
	var point: Array = schedule.get("endgameCenterM", [0.0, 0.0])
	if point.size() != 2:
		return Vector2.ZERO
	return Vector2(float(point[0]), float(point[1]))

func has_summit_finish() -> bool:
	if not is_whiteout() or not bool(schedule.get("summitFinish", false)) or phases.is_empty():
		return false
	var focus := summit_target()
	return focus.is_finite() and CIRCLES.fits(focus, float(phases[0]["radiusM"]), half_size - border)

func is_outside(point: Vector3) -> bool:
	if is_whiteout() and state == "done" and radius <= 0.001:
		return true
	return super.is_outside(point)

func exposure_at(point: Vector3) -> float:
	if not is_whiteout() or phase < 0:
		return 0.0
	if state == "done" and radius <= 0.001:
		return 1.0
	var edge := Vector2(point.x, point.z).distance_to(center) - radius
	# A gentle warning fringe inside the wall; full visibility loss 65 m outside.
	return smoothstep(-12.0, 65.0, edge)

func _pick_first_circle() -> void:
	if not has_summit_finish():
		super._pick_first_circle()
		return
	next_radius = float(phases[0]["radiusM"])
	next_center = CIRCLES.first(summit_target(), next_radius, half_size - border,
		float(schedule.get("firstCircleSampleRadiusM", 630.0)), rng)

func _pick_next_circle() -> void:
	if not has_summit_finish():
		super._pick_next_circle()
		return
	var target_radius := clampf(float(phases[phase]["radiusM"]), 0.0, next_radius)
	next_center = CIRCLES.next(next_center, next_radius, summit_target(),
		target_radius, half_size - border, rng)
	next_radius = target_radius

func _set_state(value: String) -> void:
	if not is_whiteout():
		super._set_state(value)
		return
	state = value
	t = 0.0
	state_changed.emit(phase, state, seconds_left())
	Events.zone_state.emit(phase, state, seconds_left())
	match value:
		"reveal":
			Events.banner.emit("The whiteout is forming. Watch the map.")
		"warn":
			Events.banner.emit("Next safe zone marked. Move toward the summit."
				if has_summit_finish() else "Next safe zone marked. Check the map.")
		"close":
			Events.banner.emit("WHITEOUT CLOSING. Reach the marked safe zone.")
		"done":
			Events.banner.emit("FINAL WHITEOUT. No safe ground remains.")

func _damage_tick(dt: float) -> void:
	if not is_whiteout():
		super._damage_tick(dt)
		return
	if phase < 0 or not _get_characters.is_valid():
		return
	_tick += maxf(dt, 0.0)
	var ticks := floori(_tick)
	if ticks == 0:
		return
	_tick -= float(ticks)
	var damage := maxf(dps, 0.5) * float(ticks)
	for item in _get_characters.call():
		var character := item as Character
		if is_instance_valid(character) and character.alive() and is_outside(character.global_position):
			character.take_plain_damage(damage, null, "Whiteout")

func _build_visuals() -> void:
	super._build_visuals()
	if not is_whiteout():
		return
	wall.name = "WhiteoutWall"
	var material := ShaderMaterial.new()
	material.shader = WALL_SHADER
	wall.material_override = material
	# A tall curtain spans the valley and summit rather than clipping into slopes.
	var cylinder := wall.mesh as CylinderMesh
	cylinder.height = 900.0
	var marker_material := ring.material_override as StandardMaterial3D
	marker_material.albedo_color = Color(0.76, 0.91, 1.0, 0.11)

func _update_visuals() -> void:
	super._update_visuals()
	if not is_whiteout() or wall == null:
		return
	var focus := summit_target()
	var summit_height := float(height_at.call(focus.x, focus.y)) if height_at.is_valid() else 0.0
	wall.position.y = summit_height * 0.5 + 150.0
	ring.position.y = wall.position.y
