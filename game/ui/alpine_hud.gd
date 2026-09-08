extends "res://game/ui/hud.gd"
## Reuses the combat HUD; only the whiteout presentation and ascent telemetry change.

const FROST_SHADER := preload("res://game/ui/whiteout_frost.gdshader")
const ICE := Color("9bdcff")

var _whiteout_enabled := false
var _frost := 0.0
var _location_timer := 0.0
var _ascent: PanelContainer
var _place_name: Label
var _elevation: Label
var _storm_hint: Label
var _storm_style: StyleBoxFlat

func _build() -> void:
	super._build()
	_storm_hint = _label("", _font(barlow, 14), 14, ICE)
	_storm_hint.visible = false
	zone_box.get_child(0).add_child(_storm_hint)
	_ascent = _panel(Color(0.025, 0.045, 0.07, 0.78), ICE)
	_ascent.name = "AscentTelemetry"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	_place_name = _label("BACKCOUNTRY", _font(oswald, 19, 600), 19)
	_elevation = _label("", _font(barlow, 13), 13, ICE)
	column.add_child(_place_name)
	column.add_child(_elevation)
	_ascent.add_child(column)
	_place(_ascent, Control.PRESET_TOP_LEFT, 24, 98, 252, 60)
	_ascent.visible = false

func bind(p_match: Match, p_rig: CameraRig, p_world: World) -> void:
	super.bind(p_match, p_rig, p_world)
	var storm := p_match.zone as SummitZone
	_whiteout_enabled = storm != null and storm.is_whiteout()
	if not _whiteout_enabled:
		return
	(gasfx.material as ShaderMaterial).shader = FROST_SHADER
	_storm_hint.visible = true
	_storm_style = zone_box.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	_storm_style.bg_color = Color(0.025, 0.06, 0.095, 0.88)
	_storm_style.border_width_left = 3
	_storm_style.border_color = ICE
	zone_box.add_theme_stylebox_override("panel", _storm_style)
	zone_label.add_theme_color_override("font_color", ICE)

func _process(dt: float) -> void:
	super._process(dt)
	if not _whiteout_enabled or not is_instance_valid(character) or not is_instance_valid(match_ref):
		return
	var storm := match_ref.zone as SummitZone
	if not is_instance_valid(storm):
		return
	var outside := storm.phase >= 0 and storm.is_outside(character.global_position)
	_frost = lerpf(_frost, storm.exposure_at(character.global_position), 1.0 - exp(-dt * 3.0))
	(gasfx.material as ShaderMaterial).set_shader_parameter("strength", _frost)
	zone_box.visible = true
	_storm_style.border_color = RED if outside else ICE
	var seconds := storm.seconds_left()
	match storm.state:
		"wait":
			zone_label.text = "WHITEOUT FORMING"
			seconds = maxf(0.0, float(storm.schedule.get("revealBannerAtSec", 45.0)) - storm.time)
		"reveal":
			zone_label.text = "SAFE ZONE REVEAL"
		"warn":
			zone_label.text = "WHITEOUT INCOMING  /  PHASE %d" % (storm.phase + 1)
		"close":
			zone_label.text = "WHITEOUT CLOSING  /  PHASE %d" % (storm.phase + 1)
		"done":
			zone_label.text = "FINAL WHITEOUT"
	var whole := ceili(seconds)
	zone_num.text = "%02d:%02d" % [floori(float(whole) / 60.0), whole % 60] if storm.state != "done" else "SURVIVE"
	if outside:
		_storm_hint.text = "TAKING DAMAGE  /  REACH SAFE GROUND"
		_storm_hint.add_theme_color_override("font_color", Color("ff8494"))
	elif storm.phase >= 0:
		var distance := maxf(0.0, storm.distance_to_next_edge(character.global_position))
		_storm_hint.text = "%d m TO NEXT SAFE ZONE" % ceili(distance) if distance > 0.0 else "INSIDE NEXT SAFE ZONE"
		_storm_hint.add_theme_color_override("font_color", ICE)
	else:
		_storm_hint.text = "LOOT UP. WATCH THE SUMMIT." if storm.has_summit_finish() else "LOOT UP. WATCH THE MAP."
	_ascent.visible = not map_open
	_location_timer -= dt
	if _location_timer <= 0.0:
		_location_timer = 0.2
		_update_location(storm)

func _update_location(storm: SummitZone) -> void:
	var position_xz := Vector2(character.global_position.x, character.global_position.z)
	var nearest_name := "BACKCOUNTRY"
	var nearest_distance := INF
	for poi in world.layout.pois:
		var point := Vector2(float(poi["x"]), float(poi["z"]))
		var distance := point.distance_to(position_xz)
		var reach := maxf(75.0, float(poi.get("padRadius", 75.0))) + 35.0
		if distance <= reach and distance < nearest_distance:
			nearest_distance = distance
			nearest_name = str(poi["name"]).to_upper()
			if str(poi.get("id", "")) == "the_mountain":
				nearest_name = "THE SUMMIT"
	_place_name.text = "AIRBORNE" if character.mode == Character.Mode.PARACHUTE else nearest_name
	var elevation := roundi(character.global_position.y)
	if storm.has_summit_finish():
		var distance := ceili(position_xz.distance_to(storm.summit_target()))
		_elevation.text = "%d m ELEVATION  /  %d m TO SUMMIT" % [elevation, distance]
	else:
		_elevation.text = "%d m ELEVATION" % elevation

func _draw_map() -> void:
	super._draw_map()
	if not _whiteout_enabled or not is_instance_valid(match_ref) or world == null:
		return
	var storm := match_ref.zone as SummitZone
	if storm == null or not storm.has_summit_finish():
		return
	var side := minf(map_screen.size.x, map_screen.size.y) - 80.0
	var origin := (map_screen.size - Vector2(side, side)) * 0.5
	var half := world.layout.half_size
	var focus := storm.summit_target()
	var point := origin + (focus + Vector2.ONE * half) / (2.0 * half) * side
	map_screen.draw_arc(point, 9.0, 0.0, TAU, 24, RED, 2.0)
	map_screen.draw_circle(point, 3.0, Color.WHITE)
