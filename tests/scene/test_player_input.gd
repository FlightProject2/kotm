extends TestCase
## Keyboard and mouse must drive the local player even when the mouse is not captured
## (browsers refuse pointer lock until a click inside the canvas).

func test_keys_and_mouse_without_capture() -> void:
	var fl := StaticBody3D.new(); fl.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(100, 1, 100); cs.shape = bs; fl.add_child(cs); fl.position.y = -0.5
	await add_to_tree(fl)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.position = Vector3(0, 0.05, 0)
	await add_to_tree(ch)
	var rig: CameraRig = load("res://game/camera/camera_rig.tscn").instantiate()
	await add_to_tree(rig)
	rig.target = ch
	var src := PlayerInputSource.new()
	src.character = ch
	src.camera_rig = rig
	ch.add_child(src)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await settle(5)
	var yaw0 := rig.yaw
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(200, 0)
	Input.parse_input_event(ev)
	await settle(2)
	assert_true(rig.yaw < yaw0 - 0.1, "mouse motion turns the camera without capture (yaw %.3f -> %.3f)" % [yaw0, rig.yaw])
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await settle(40)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	assert_true(ch.input.move.y > 0.9, "W reaches the character input")
	assert_true(ch.input.pressed(CharacterInput.B_SPRINT), "Shift reaches the character input")
	assert_true(Vector2(ch.velocity.x, ch.velocity.z).length() > 5.0, "character sprints (%.1f m/s)" % Vector2(ch.velocity.x, ch.velocity.z).length())
	src.enabled = false
	await settle(3)
	assert_true(ch.input.move.length() < 0.01, "paused input source sends no movement")
	ch.queue_free(); rig.queue_free(); fl.queue_free()
	await settle(1)
