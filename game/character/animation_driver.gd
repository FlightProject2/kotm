class_name AnimationDriver
extends Node
## Picks mannequin clips from the character's state (no AnimationTree authored yet):
## idle / fight_idle (armed) / run scaled by speed / air clips / air_land / fight_punch.

var character: Character
var player: AnimationPlayer
var current: String = ""
var armed: bool = false
var melee_until: float = 0.0
var landing_until: float = 0.0

const LOOPING := ["idle", "run", "fight_idle", "air_jump"]
## Bot animation LOD: [max distance to the viewer, advance every N frames].
const LOD := [[12.0, 1], [28.0, 2], [60.0, 4], [120.0, 8], [260.0, 15], [1.0e9, 30]]
static var viewer: Node3D
var _acc := 0.0
var _frame := 0
var _lod_check := 0.0
var _every := 1
var studio: KOTMCharacterRig
var fire_until := 0.0
var reload_started := false
var reload_speed := 1.0
var draw_pending := false
var lower_gait_clip := ""
var lower_gait_phase := 0.0
var _clip_durations: Dictionary = {}
var _authored_speeds: Dictionary = {}

func audio_gait_state() -> Dictionary:
	if lower_gait_clip.is_empty():
		return {}
	return {"clip": lower_gait_clip, "phase": lower_gait_phase, "info": KOTMCharacterRig.manifest.animations.get(lower_gait_clip, {})}

func _advance_lower_gait(dt: float) -> void:
	var velocity_mps := Vector2(character.velocity.x, character.velocity.z).length()
	if character.mode != Character.Mode.GROUND or character.in_vehicle() or velocity_mps <= 0.15:
		lower_gait_clip = ""
		return
	var gait := "Crouch_Walk" if character.crouching else ("Run" if velocity_mps > 4.8 else ("Jog" if velocity_mps > 2.0 and studio.clips.has("KOTM_Jog") else "Walk"))
	lower_gait_clip = "KOTM_" + gait
	if studio.clips.has(lower_gait_clip):
		var duration := _clip_duration(lower_gait_clip)
		lower_gait_phase = fposmod(lower_gait_phase + dt * _native_speed_scale(lower_gait_clip, velocity_mps) / duration, 1.0)

func weapon_changed() -> void:
	draw_pending = true
	fire_until = 0.0
	reload_started = false
	if studio:
		_pick_studio_clip()
		player.advance(0)

func _ready() -> void:
	character = get_parent() as Character
	var found := character.get_node("Visual").find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		push_warning("AnimationDriver: no AnimationPlayer")
		return
	player = found[0]
	studio = character.visual.get("studio_rig")
	character.fired.connect(_shot)
	for n in LOOPING:
		if player.has_animation(n):
			player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	character.landed.connect(func() -> void: landing_until = Time.get_ticks_msec() / 1000.0 + 0.5)
	if character.is_bot:
		# bots advance their clips manually at a distance-based rate (skeleton modifiers and
		# hitbox transforms only run when the pose changes, so this scales the whole stack)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if studio:
			studio.skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	if viewer == null or not is_instance_valid(viewer):
		Events.local_character_changed.connect(func(ch: Node) -> void: viewer = ch as Node3D)

func play_melee() -> void:
	melee_until = Time.get_ticks_msec() / 1000.0 + 0.45

func _process(dt: float) -> void:
	if player == null:
		return
	if studio:
		_advance_lower_gait(dt)
	if character.is_bot:
		_lod_check -= dt
		if _lod_check <= 0.0:
			_lod_check = 0.5
			var d := 1.0e9
			if viewer and is_instance_valid(viewer) and viewer != character:
				d = viewer.global_position.distance_to(character.global_position)
			for tier in LOD:
				if d <= float(tier[0]):
					_every = int(tier[1])
					break
		_acc += dt
		_frame += 1
		if _frame % _every == 0:
			_pick_clip()
			player.advance(_acc)
			if studio:
				studio.skeleton.advance(_acc)
			_acc = 0.0
		return
	_pick_clip()

func _pick_clip() -> void:
	if studio:
		_pick_studio_clip()
		return
	var now := Time.get_ticks_msec() / 1000.0
	var planar := Vector2(character.velocity.x, character.velocity.z).length()
	var clip := "idle"
	var speed_scale := 1.0
	if character.mode == Character.Mode.PARACHUTE:
		clip = "air_jump"
		speed_scale = 0.2
	elif now < melee_until:
		clip = "fight_punch"
	elif character.mode == Character.Mode.AIR:
		clip = "air_jump"
		speed_scale = 0.5
	elif now < landing_until:
		clip = "air_land"
		speed_scale = 2.0
	elif planar > 0.4:
		clip = "run"
		speed_scale = clampf(planar / 6.5, 0.45, 1.15)
	else:
		clip = "fight_idle" if armed else "idle"
	if clip != current and player.has_animation(clip):
		player.play(clip, 0.15)
		current = clip
	player.speed_scale = speed_scale

func _shot(_vertical: float, _horizontal: float) -> void:
	if studio == null or not KOTMCharacterRig.WEAPONS.has(studio.weapon_id):
		return
	fire_until = Time.get_ticks_msec() / 1000.0 + 0.23
	# A repeated automatic shot restarts recoil, independent of the combat RPM/ammo rules.
	if current.ends_with("Fire"):
		player.seek(0.0, false)

func _pick_studio_clip() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var planar := Vector2(character.velocity.x, character.velocity.z).length()
	var prefix := "KOTM_"
	var fitted := KOTMCharacterRig.WEAPONS.has(studio.weapon_id)
	if fitted:
		prefix += KOTMCharacterRig.WEAPONS[studio.weapon_id] + "_"
	var aiming := character.input.pressed(CharacterInput.B_AIM)
	var moving := planar > 0.15
	var sprinting := character.motor.sprinting and planar > 4.8 and not aiming
	var clip := "KOTM_Idle"
	var speed := 1.0
	if character.in_vehicle():
		clip = character.vehicle.seated_animation()
	elif character.mode == Character.Mode.PARACHUTE:
		# Keep the torso hanging steadily while the arm modifier holds both risers.
		clip = "KOTM_Idle"
		speed = 0.5
	elif fitted and character.combat.reload_t > 0:
		clip = prefix + "Reload"
		if not reload_started:
			reload_speed = _clip_duration(clip) / maxf(character.combat.reload_t, 0.1)
			reload_started = true
		speed = reload_speed
	elif character.mode == Character.Mode.AIR:
		clip = prefix + "Jump"
	elif fitted and now < fire_until:
		clip = prefix + ("Crouch_Fire" if character.crouching else "Fire")
	elif character.crouching:
		if fitted:
			clip = prefix + ("Crouch_Aim_Walk" if aiming else "Crouch_Walk") if moving else prefix + ("Crouch_Aim" if aiming else "Crouch_Ready")
		else:
			clip = "KOTM_Crouch_Walk" if moving else "KOTM_Crouch_Idle"
		if moving:
			speed = _native_speed_scale(clip, planar)
	elif moving:
		var gait := "Run" if sprinting else ("Jog" if planar > 2.0 and studio.clips.has(prefix + "Jog") else "Walk")
		clip = prefix + ("Aim_" if fitted and aiming else "") + gait
		speed = _native_speed_scale(clip, planar)
	elif fitted:
		clip = prefix + ("Aim" if aiming else "Ready")
	if character.combat.reload_t <= 0:
		reload_started = false
	if not studio.clips.has(clip):
		clip = "KOTM_Idle"
	if clip != current or draw_pending:
		var was_gait := current.ends_with("Walk") or current.ends_with("Jog") or current.ends_with("Run")
		var is_gait := clip.ends_with("Walk") or clip.ends_with("Jog") or clip.ends_with("Run")
		var phase := fposmod(player.current_animation_position / maxf(player.current_animation_length, 0.01), 1.0) if was_gait else 0.0
		# Seat clips define the fitted pelvis position; blending from standing would put
		# the body through the roof or track until the interpolation finishes.
		studio.play(clip, 0.0 if draw_pending or clip.ends_with("Seated") else (0.08 if clip.ends_with("Fire") else 0.2))
		if was_gait and is_gait:
			player.seek(phase * _clip_duration(clip), false)
		current = clip
		draw_pending = false
	if clip.ends_with("Walk") or clip.ends_with("Jog") or clip.ends_with("Run"):
		player.seek(lower_gait_phase * player.get_animation(studio.clips[clip]).length, true)
		speed = 0.0
	player.speed_scale = speed

func _clip_duration(clip: String) -> float:
	if not _clip_durations.has(clip):
		_clip_durations[clip] = player.get_animation(studio.clips[clip]).length
	return float(_clip_durations[clip])

func _native_speed_scale(clip: String, velocity_mps: float) -> float:
	if not _authored_speeds.has(clip):
		var info: Dictionary = KOTMCharacterRig.manifest.get("animations", {}).get(clip, {})
		_authored_speeds[clip] = float(info.get("recommended_controller_speed_mps", info.get("speed_mps", 0)))
	var authored := float(_authored_speeds[clip])
	return clampf(velocity_mps / authored, 0.25, 1.5) if authored > 0.01 else 1.0
