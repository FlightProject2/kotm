class_name CharacterAudio
extends Node
## Authority decides WHEN a sound happens. Each peer selects/mixes a nearby 3D recording.
signal sound_requested(event: String, position: Vector3, volume: float)
const COOLDOWNS := {"hurt": 0.75, "jump": 0.25, "punch": 0.2, "fence": 1.25, "door_locked": 1.5, "exertion": 6.0}
var c: Character
var clock := 0.0
var _last: Dictionary = {}
var _step_distance := 0.0
var _left := true
var _gait_phase := -1.0
var _last_step_clock := -100.0
var _sprint_time := 0.0
var _gas_started := -100.0
var _gas_last := -100.0
var _next_cough := 0.0
var _dead := false
var _water: Dictionary = {}

func _ready() -> void:
	c = get_parent() as Character
	c.jumped.connect(func() -> void: request("jump", 0.55))
	c.died.connect(func(_killer: Character, _weapon: String, _headshot: bool) -> void: on_death())

func tick(dt: float, previous_position: Vector3) -> void:
	clock += dt
	if not c.alive() or c.in_vehicle():
		_step_distance = 0.0
		_gait_phase = -1.0
		_sprint_time = 0.0
		return
	var travelled := Vector2(c.global_position.x - previous_position.x, c.global_position.z - previous_position.z).length()
	var speed := Vector2(c.velocity.x, c.velocity.z).length()
	var walking := c.is_on_floor() and c.mode == Character.Mode.GROUND and speed > 0.2 and travelled > 0.001
	if walking and travelled < 2.0: # A teleport is never a footstep or an exertion burst.
		var sprinting := c.input.pressed(CharacterInput.B_SPRINT) and speed > float(c.cfg["walkSpeed"]) + 0.5 and not c.crouching
		_tick_steps(travelled, speed, sprinting)
		_sprint_time = _sprint_time + dt if sprinting else maxf(0.0, _sprint_time - dt * 2.0)
	else:
		_step_distance = 0.0
		_gait_phase = -1.0
		_sprint_time = maxf(0.0, _sprint_time - dt * 2.0)
	if c.motor.stamina.exhausted:
		request("exertion", 0.48)
	_check_fence()

func _tick_steps(travelled: float, speed: float, sprinting: bool) -> void:
	var state := _visual_gait_state()
	if state.has("phase"):
		# Use the evaluated gait phase, including the driver's moving-fire/reload leg
		# layer. A gait change preserves phase, so ready/aim changes do not add steps.
		var phase := fposmod(float(state.phase), 1.0)
		if _gait_phase >= 0.0:
			var delta := fposmod(phase - _gait_phase, 1.0)
			var info: Dictionary = state.get("info", {})
			var contacts: Variant = info.get("foot_contact_phases", {"left": 0.0, "right": 0.5})
			if contacts is String:
				contacts = JSON.parse_string(contacts) if contacts.strip_edges().begins_with("{") else null
			if not contacts is Dictionary:
				contacts = {"left": 0.0, "right": 0.5}
			if delta > 0.00001 and delta < 0.75: # No catch-up burst after a stalled/reset animation.
				for foot in ["left", "right"]:
					var distance := fposmod(float(contacts.get(foot, 0.0 if foot == "left" else 0.5)) - _gait_phase, 1.0)
					if distance > 0.00001 and distance <= delta + 0.00001:
						_step(foot == "left", sprinting)
		_gait_phase = phase
		_step_distance = 0.0
		return
	_gait_phase = -1.0
	# Server/visual-LOD fallback uses the same authored speed and cycle duration.
	# At native playback there are exactly two strikes per cycle.
	var stride := stride_metres(_fallback_gait_info(speed, sprinting))
	_step_distance += travelled
	if _step_distance >= stride:
		_step_distance = fmod(_step_distance, stride)
		_step(_left, sprinting)
		_left = not _left

func _step(left: bool, sprinting: bool) -> void:
	if clock - _last_step_clock < 0.08:
		return
	_last_step_clock = clock
	request(PlayerSoundBank.footstep(current_surface(), left), 0.22 if c.crouching else (0.85 if sprinting else 0.58), true)

func _visual_gait_state() -> Dictionary:
	if c.visual == null:
		return {}
	var driver: Node = c.visual.get("anim")
	if driver == null:
		return {}
	if driver.has_method("audio_gait_state"):
		return driver.call("audio_gait_state")
	var clip := str(driver.get("current"))
	var player: AnimationPlayer = driver.get("player")
	if player and (clip.ends_with("Walk") or clip.ends_with("Jog") or clip.ends_with("Run")):
		return {"clip": clip, "phase": player.current_animation_position / maxf(player.current_animation_length, 0.01), "info": KOTMCharacterRig.manifest.get("animations", {}).get(clip, {})}
	return {}

func _fallback_gait_info(speed: float, sprinting: bool) -> Dictionary:
	var key := "KOTM_Crouch_Walk" if c.crouching else ("KOTM_Run" if sprinting else ("KOTM_Jog" if speed > 2.0 else "KOTM_Walk"))
	var animations: Dictionary = KOTMCharacterRig.manifest.get("animations", {})
	if animations.has(key):
		return animations[key]
	# Temporary/legacy model fallback matches the four reviewed replacement gaits.
	var defaults := {"KOTM_Walk": [1.5, 28.0 / 30.0], "KOTM_Jog": [3.5, 22.0 / 30.0], "KOTM_Run": [6.5, 18.0 / 30.0], "KOTM_Crouch_Walk": [1.2, 24.0 / 30.0]}
	return {"speed_mps": defaults[key][0], "duration_seconds": defaults[key][1]}

static func stride_metres(info: Dictionary) -> float:
	var speed := float(info.get("recommended_controller_speed_mps", info.get("speed_mps", 1.5)))
	return maxf(0.1, speed * float(info.get("duration_seconds", 28.0 / 30.0)) * 0.5)

func request(event: String, volume := 0.7, at_feet := false) -> bool:
	if not c.is_authority() or _dead or not c.alive():
		return false
	if clock - float(_last.get(event, -100.0)) < float(COOLDOWNS.get(event, 0.0)):
		return false
	_last[event] = clock
	var pos := c.global_position + Vector3.UP * (0.12 if at_feet else c.height() * 0.8)
	sound_requested.emit(event, pos, volume)
	Net.fx_all("player_sound", [event, pos, c.character_id, volume])
	return true

func on_damage(amount: float, cause: String) -> void:
	if amount <= 0.0 or not c.alive() or c.god_mode:
		return
	if cause == "Gas":
		if clock - _gas_last > 1.8:
			_gas_started = clock
			_next_cough = clock
		_gas_last = clock
		if clock >= _next_cough:
			request("cough_heavy" if clock - _gas_started >= 4.0 else "cough", 0.7)
			_next_cough = clock + 4.5
	elif cause != "Bleeding" and cause != "Whiteout":
		request("hurt", 0.8)

func on_death() -> void:
	if _dead or not c.is_authority():
		return
	_dead = true
	var pos := c.global_position + Vector3.UP
	sound_requested.emit("death", pos, 0.95)
	Net.fx_all("player_sound", ["death", pos, c.character_id, 0.95])

static func metadata(node: Node, key: String, fallback: Variant = null) -> Variant:
	var current := node
	while current:
		if current.has_meta(key):
			return current.get_meta(key)
		current = current.get_parent()
	return fallback

func current_surface() -> String:
	var water_surface := ""
	for id in _water:
		if _water[id] == "deep_water": return "deep_water"
		water_surface = "shallow_water"
	if water_surface != "": return water_surface
	var query := PhysicsRayQueryParameters3D.create(c.global_position + Vector3.UP * 0.3, c.global_position - Vector3.UP * 0.45, 1)
	query.exclude = [c.get_rid()]
	var hit := c.get_world_3d().direct_space_state.intersect_ray(query)
	return str(metadata(hit.get("collider") as Node, "audio_surface", "hard"))

func water_enter(area: Area3D, surface: String) -> void:
	_water[area.get_instance_id()] = surface

func water_exit(area: Area3D) -> void:
	_water.erase(area.get_instance_id())

func _check_fence() -> void:
	# Requires actual body contact with a tagged fence; merely standing near metal is silent.
	if c.input.move.length_squared() < 0.01:
		return
	for i in c.get_slide_collision_count():
		var hit := c.get_slide_collision(i)
		if absf(hit.get_normal().y) < 0.5 and bool(metadata(hit.get_collider() as Node, "audio_fence", false)):
			request("fence", 0.55)
			return

func try_locked_door() -> bool:
	var origin := c.eye_position()
	var direction := c.input.aim_dir.normalized() if c.input.aim_dir.length_squared() > 0.5 else c.forward()
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * CharacterInteraction.REACH, 1)
	query.exclude = [c.get_rid()]
	var hit := c.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and bool(metadata(hit.get("collider") as Node, "audio_locked_door", false)):
		request("door_locked", 0.6)
		return true
	return false
