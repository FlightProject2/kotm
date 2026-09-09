extends TestCase

func test_local_copy_preserves_packet_and_does_not_alias() -> void:
	var input := CharacterInput.new()
	input.tick = 9451
	input.move = Vector2(.3,-.7)
	input.yaw = 1.23456789
	input.pitch = -.456789
	input.aim_dir = Vector3(.13,.24,-.89)
	input.buttons = CharacterInput.B_FIRE | CharacterInput.B_JUMP | CharacterInput.B_RELOAD
	input.slot = 6
	input.use_med = 2
	var copy := input.duplicate_input()
	assert_eq(copy.pack(),input.pack(),"Direct local copy retains the exact network packet")
	input.buttons = 0
	input.move = Vector2.ZERO
	assert_true(copy.pressed(CharacterInput.B_FIRE),"Previous tick edges remain independent")
	assert_eq(copy.move,Vector2(.3,-.7),"Copied movement does not alias live input")
