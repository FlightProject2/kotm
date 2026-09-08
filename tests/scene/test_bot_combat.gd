extends TestCase
## A bot with a rifle must land hits on a standing target at 40 m within a few seconds.

func test_bot_hits_standing_target() -> void:
	var fl := StaticBody3D.new(); fl.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(400, 1, 400); cs.shape = bs; fl.add_child(cs); fl.position.y = -0.5
	await add_to_tree(fl)
	var ps := ProjectileSystem.new()
	await add_to_tree(ps)
	var target: Character = load("res://game/character/character.tscn").instantiate()
	target.position = Vector3(0, 0.05, -40)
	target.display_name = "Dummy"
	await add_to_tree(target)
	var bot: Character = load("res://game/character/character.tscn").instantiate()
	bot.is_bot = true
	bot.display_name = "Bot"
	bot.position = Vector3(0, 0.05, 0)
	var brain := BotBrain.new()
	brain.name = "Brain"
	brain.rng = RandomNumberGenerator.new()
	brain.rng.seed = 11
	bot.add_child(brain)
	await add_to_tree(bot)
	bot.inventory.give_weapon("ar15")
	bot.inventory.give_ammo("223", 120)
	await settle(30)
	var shots0 := ps.shots_fired
	for i in 360:
		await settle(1)
		if ps.hits >= 2:
			break
	print("    bot: target=%s shots=%d hits=%d dummy hp=%.0f aim=%s slot=%s" % [brain.target != null, ps.shots_fired - shots0, ps.hits, target.health.hp, bot.input.aim_dir, bot.inventory.current_id()])
	assert_true(brain.target == target, "bot sees the target")
	# two hits can arrive in two shots now that the bot aims well, so only require that it opened fire
	assert_true(ps.shots_fired - shots0 >= 1, "bot fired (%d shots)" % (ps.shots_fired - shots0))
	assert_true(ps.hits >= 1 and target.health.hp < 100.0, "bot landed a hit (hits %d, hp %.0f)" % [ps.hits, target.health.hp])
	bot.queue_free(); target.queue_free(); ps.queue_free(); fl.queue_free()
	await settle(1)
