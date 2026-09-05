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
const LOD := [[45.0, 1], [120.0, 3], [260.0, 6], [1.0e9, 12]]
static var viewer: Node3D
var _acc := 0.0
var _frame := 0
var _lod_check := 0.0
var _every := 1

func _ready() -> void:
	character = get_parent() as Character
	var found := character.get_node("Visual").find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		push_warning("AnimationDriver: no AnimationPlayer")
		return
	player = found[0]
	for n in LOOPING:
		if player.has_animation(n):
			player.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	character.landed.connect(func() -> void: landing_until = Time.get_ticks_msec() / 1000.0 + 0.5)
	if character.is_bot:
		# bots advance their clips manually at a distance-based rate (skeleton modifiers and
		# hitbox transforms only run when the pose changes, so this scales the whole stack)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if viewer == null or not is_instance_valid(viewer):
		Events.local_character_changed.connect(func(ch: Node) -> void: viewer = ch as Node3D)

func play_melee() -> void:
	melee_until = Time.get_ticks_msec() / 1000.0 + 0.45

func _process(dt: float) -> void:
	if player == null:
		return
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
			_acc = 0.0
		return
	_pick_clip()

func _pick_clip() -> void:
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
