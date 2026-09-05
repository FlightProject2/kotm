extends TestCase
## A character spawned under a parachute descends and lands on the terrain.

func test_parachute_lands() -> void:
	var world: World = load("res://game/world/world.tscn").instantiate()
	await add_to_tree(world)
	world.setup("mesh")
	await settle(2)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.world = world
	world.characters.add_child(ch)
	var ground := world.height_at(300, 300)
	ch.motor.start_parachute(Vector3(300, ground + 60.0, 300), 0.0)
	await settle(1)
	assert_eq(ch.mode, Character.Mode.PARACHUTE)
	var frames := 0
	while ch.mode == Character.Mode.PARACHUTE and frames < 60 * 20:
		var i := CharacterInput.new()
		i.move = Vector2(0, 1 if frames > 60 else 0)
		i.yaw = 0.0
		ch.submit_input(i)
		await tree.physics_frame
		frames += 1
	var secs := frames / 60.0
	assert_true(ch.mode != Character.Mode.PARACHUTE, "landed")
	assert_between(secs, 5.0, 12.0, "60 m descent takes 5-12 s (got %.1f)" % secs)
	assert_true(ch.stun > 0.0 or ch.mode == Character.Mode.GROUND, "landing stun / ground mode")
	assert_true(absf(ch.global_position.y - world.height_at(ch.global_position.x, ch.global_position.z)) < 0.3, "on the ground")
	assert_true(ch.global_position.z < 300.0 - 20.0, "drifted forward while diving")
	world.queue_free()
	await settle(1)
