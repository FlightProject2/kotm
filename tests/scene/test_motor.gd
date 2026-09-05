extends TestCase
## Drives a Character with scripted inputs on a flat floor and checks the movement numbers.

const CHARACTER := "res://game/character/character.tscn"

func _floor(y := 0.0) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = 1
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = Vector3(400, 1, 400)
	cs.shape = s
	b.add_child(cs)
	b.position.y = y - 0.5
	return b

func _spawn(pos: Vector3) -> Character:
	var ch: Character = load(CHARACTER).instantiate()
	ch.position = pos
	tree.root.add_child(ch)
	return ch

func _drive(ch: Character, frames: int, setup: Callable) -> void:
	for i in frames:
		var inp := CharacterInput.new()
		inp.tick = i
		setup.call(inp)
		ch.submit_input(inp)
		await tree.physics_frame

func test_sprint_walk_crouch_speeds() -> void:
	var f := _floor()
	await add_to_tree(f)
	var ch := _spawn(Vector3(0, 0.1, 0))
	await settle(3)
	await _drive(ch, 90, func(i: CharacterInput) -> void: i.move = Vector2(0, 1); i.set_button(CharacterInput.B_SPRINT, true))
	assert_near(Vector2(ch.velocity.x, ch.velocity.z).length(), 6.5, 0.15, "sprint speed")
	await _drive(ch, 60, func(i: CharacterInput) -> void: i.move = Vector2(0, 1))
	assert_near(Vector2(ch.velocity.x, ch.velocity.z).length(), 3.5, 0.15, "walk speed")
	await _drive(ch, 60, func(i: CharacterInput) -> void: i.move = Vector2(0, 1); i.set_button(CharacterInput.B_CROUCH, true))
	assert_near(Vector2(ch.velocity.x, ch.velocity.z).length(), 2.0, 0.15, "crouch speed")
	assert_true(ch.crouching)
	assert_near((ch.collision.shape as CapsuleShape3D).height, 1.2, 0.001, "crouch capsule")
	assert_true(ch.forward().dot(Vector3(ch.velocity.x, 0, ch.velocity.z).normalized()) > 0.99, "moves along facing")
	await _drive(ch, 60, func(i: CharacterInput) -> void: i.move = Vector2(1, 0))
	assert_true(ch.velocity.x > 2.0 and absf(ch.velocity.z) < 0.5, "D strafes to +X when facing -Z (vel %s)" % ch.velocity)
	assert_true(ch.right().is_equal_approx(Vector3(1, 0, 0)), "right() is +X when facing -Z")
	ch.queue_free(); f.queue_free()
	await settle(1)

func test_jump_apex() -> void:
	var f := _floor()
	await add_to_tree(f)
	var ch := _spawn(Vector3(0, 0.1, 0))
	await settle(5)
	var start := ch.global_position.y
	var apex := start
	for i in 70:
		var inp := CharacterInput.new()
		inp.set_button(CharacterInput.B_JUMP, i == 2)
		ch.submit_input(inp)
		await tree.physics_frame
		apex = maxf(apex, ch.global_position.y)
	assert_between(apex - start, 1.0, 1.25, "jump apex ~1.1 m (got %.2f)" % (apex - start))
	assert_true(ch.is_on_floor(), "back on the floor")
	ch.queue_free(); f.queue_free()
	await settle(1)

func test_fall_damage() -> void:
	var f := _floor()
	await add_to_tree(f)
	var ch := _spawn(Vector3(0, 10.0, 0))
	await settle(1)
	await _drive(ch, 150, func(_i: CharacterInput) -> void: pass)
	assert_true(ch.is_on_floor())
	assert_between(ch.health.hp, 40.0, 52.0, "10 m fall costs ~55 hp (hp %.1f)" % ch.health.hp)
	var ch2 := _spawn(Vector3(5, 3.0, 0))
	await settle(1)
	await _drive(ch2, 90, func(_i: CharacterInput) -> void: pass)
	assert_near(ch2.health.hp, 100.0, 0.01, "3 m fall is free")
	ch.queue_free(); ch2.queue_free(); f.queue_free()
	await settle(1)

func test_input_roundtrip() -> void:
	var i := CharacterInput.new()
	i.tick = 12345; i.move = Vector2(0.5, -1); i.yaw = 1.25; i.pitch = -0.3; i.aim_dir = Vector3(0.1, 0.2, -0.97).normalized()
	i.buttons = CharacterInput.B_FIRE | CharacterInput.B_AIM | CharacterInput.B_PRONE; i.slot = 3; i.use_med = 2
	var j := CharacterInput.unpack(i.pack())
	assert_eq(j.tick, 12345); assert_eq(j.buttons, i.buttons); assert_eq(j.slot, 3); assert_eq(j.use_med, 2)
	assert_near(j.yaw, 1.25, 1e-6); assert_true(j.aim_dir.distance_to(i.aim_dir) < 1e-6)
	assert_true(i.pack().size() <= 40, "packed input is small")
