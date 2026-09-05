class_name PlayerInputSource
extends Node
## Turns the local player's InputMap + camera state into a CharacterInput every physics tick.

var character: Character
var camera_rig: CameraRig
var crouch_toggle: bool = false
var tick: int = 0
var enabled: bool = true

func _physics_process(_dt: float) -> void:
	if character == null or camera_rig == null:
		return
	if not enabled:
		var idle := CharacterInput.new()
		idle.yaw = character.yaw
		idle.pitch = character.pitch
		idle.aim_dir = character.forward()
		idle.set_button(CharacterInput.B_CROUCH, crouch_toggle)
		character.submit_input(idle)
		return
	if Input.is_action_just_pressed("crouch"):
		crouch_toggle = not crouch_toggle
	var i := CharacterInput.new()
	tick += 1
	i.tick = tick
	if enabled:
		i.move = Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward"))
		i.set_button(CharacterInput.B_SPRINT, Input.is_action_pressed("sprint"))
		i.set_button(CharacterInput.B_JUMP, Input.is_action_pressed("jump"))
		i.set_button(CharacterInput.B_FIRE, Input.is_action_pressed("fire"))
		i.set_button(CharacterInput.B_AIM, Input.is_action_pressed("aim"))
		i.set_button(CharacterInput.B_RELOAD, Input.is_action_pressed("reload"))
		i.set_button(CharacterInput.B_INTERACT, Input.is_action_just_pressed("interact"))
		i.set_button(CharacterInput.B_FREE_LOOK, Input.is_action_pressed("free_look"))
		for s in 6:
			if Input.is_action_just_pressed("hotbar_%d" % (s + 1)):
				i.slot = s
		if Input.is_action_just_pressed("use_bandage"):
			i.use_med = 1
		elif Input.is_action_just_pressed("use_medkit"):
			i.use_med = 2
	i.set_button(CharacterInput.B_CROUCH, crouch_toggle)
	i.yaw = camera_rig.body_yaw()
	i.pitch = camera_rig.pitch
	i.aim_dir = camera_rig.aim_direction(character)
	character.submit_input(i)
