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

func play_melee() -> void:
	melee_until = Time.get_ticks_msec() / 1000.0 + 0.45

func _process(_dt: float) -> void:
	if player == null:
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
