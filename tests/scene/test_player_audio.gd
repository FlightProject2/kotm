extends TestCase
## Real Character/physics/Net events, plus recording selection and voice arbitration.
var heard: Array = []

func _floor() -> StaticBody3D:
	var floor := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 1, 300)
	collider.shape = box
	floor.add_child(collider)
	floor.position.y = -0.5
	floor.collision_layer = 1
	return floor

func _character() -> Character:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.character_id = 800 + heard.size()
	ch.position = Vector3(0, 0.05, 0)
	tree.root.add_child(ch)
	ch.player_audio.sound_requested.connect(func(event: String, pos: Vector3, volume: float) -> void: heard.append({"event": event, "pos": pos, "volume": volume}))
	return ch

func _count(prefix: String) -> int:
	var result := 0
	for item in heard:
		if item.event.begins_with(prefix): result += 1
	return result

func _drive(ch: Character, frames: int, buttons := 0, move := Vector2.ZERO) -> void:
	for i in frames:
		var input := CharacterInput.new()
		input.move = move
		input.buttons = buttons
		ch.submit_input(input)
		await tree.physics_frame

func test_recordings_variants_and_separate_rng() -> void:
	var bank := PlayerSoundBank.new()
	var paths: Dictionary = {}
	for event in PlayerSoundBank.CUES:
		for recording in PlayerSoundBank.CUES[event]:
			assert_true(recording.get_length() > 0.1, event + " decodes")
			paths[recording.resource_path] = true
	assert_eq(paths.size(), 22, "all 22 supplied WAVs referenced")
	for event in ["death", "punch", "fence", "step_water", "exertion"]:
		var previous := ""
		for i in 12:
			var path := bank.choose(event, 99).resource_path
			assert_true(path != previous, event + " avoids adjacent repeats")
			previous = path
	seed(9876)
	var expected := randi()
	seed(9876)
	bank.choose("punch", 99)
	assert_eq(randi(), expected, "audio does not consume gameplay/global RNG")

func test_grounded_steps_crouch_and_accepted_jump() -> void:
	heard.clear()
	var floor := _floor()
	await add_to_tree(floor)
	var ch := _character()
	await settle(5)
	await _drive(ch, 30)
	assert_eq(_count("step_"), 0, "idle is silent")
	await _drive(ch, 100, 0, Vector2(0, 1))
	assert_between(_count("step_"), 3, 6, "footsteps follow distance")
	var sequence: Array = []
	for item in heard:
		if item.event.begins_with("step_"): sequence.append(item.event)
	assert_true(sequence[0] != sequence[1], "left and right hard steps alternate")
	heard.clear()
	await _drive(ch, 65, CharacterInput.B_CROUCH, Vector2(0, 1))
	assert_true(_count("step_") > 0)
	for item in heard:
		if item.event.begins_with("step_"): assert_near(item.volume, 0.22, 0.001, "crouch quieter")
	heard.clear()
	await _drive(ch, 1, CharacterInput.B_JUMP)
	await _drive(ch, 20, CharacterInput.B_JUMP, Vector2(0, 1))
	assert_eq(_count("jump"), 1, "held jump produces one accepted launch")
	assert_eq(_count("step_"), 0, "airborne travel is silent")
	ch.set_physics_process(false)
	var vehicle := Vehicle.new()
	ch.vehicle = vehicle
	heard.clear()
	ch.player_audio.tick(1.0, ch.global_position - Vector3.FORWARD * 10)
	assert_eq(heard.size(), 0, "vehicle travel has no player footsteps")
	ch.vehicle = null
	vehicle.free()
	ch.health.alive = false
	ch.player_audio.tick(1.0, ch.global_position - Vector3.FORWARD * 10)
	assert_eq(heard.size(), 0, "dead body silent")
	ch.queue_free(); floor.queue_free()
	await settle(1)

func test_hurt_gas_death_and_melee_cooldowns() -> void:
	heard.clear()
	var ch := _character()
	ch.set_physics_process(false)
	ch.take_plain_damage(1.0, null, "Bleeding")
	assert_eq(heard.size(), 0, "bleeding does not sound like a bullet or gas")
	ch.take_plain_damage(2.0, null, "Bullet")
	ch.take_plain_damage(2.0, null, "Bullet")
	assert_eq(_count("hurt"), 1, "rapid hits rate limited")
	heard.clear()
	for i in 7:
		ch.player_audio.clock += 1.0
		ch.take_plain_damage(1.0, null, "Gas")
	assert_eq(_count("cough"), 2, "gas cough rate limited")
	assert_eq(_count("cough_heavy"), 1, "continued gas uses deeper cough")
	ch.player_audio.clock += 4.0
	ch.take_plain_damage(1.0, null, "Gas")
	assert_eq(_count("cough"), 3, "new exposure restarts light cough")
	heard.clear()
	assert_true(ch.combat.try_fire(true), "accepted fist swing")
	assert_false(ch.combat.try_fire(true), "swing cooldown respected")
	assert_eq(_count("punch"), 1)
	ch.take_plain_damage(1000.0, null, "Bullet")
	ch.take_plain_damage(1000.0, null, "Bullet")
	ch.player_audio.on_death()
	assert_eq(_count("death"), 1, "one death request, no duplicate grunt")
	assert_false(ch.player_audio.request("hurt"), "postmortem voice rejected")
	ch.queue_free()
	await settle(1)

func test_surfaces_water_and_explicit_locked_door() -> void:
	heard.clear()
	var floor := _floor()
	await add_to_tree(floor)
	var ch := _character()
	await settle(5)
	for surface in ["hard", "grass", "wood", "metal", "shallow_water", "deep_water"]:
		floor.set_meta("audio_surface", surface)
		assert_eq(ch.player_audio.current_surface(), surface)
		var before := heard.size()
		await _drive(ch, 28, 0, Vector2(0, 1))
		assert_true(heard.size() > before, surface + " walking emits")
		assert_true(str(heard[-1].event).begins_with(PlayerSoundBank.footstep(surface, true).trim_suffix("_left")), surface + " mapped")
	ch.global_position = Vector3(0, 0.05, 0)
	await _drive(ch, 8)
	var water := AudioWaterArea.new()
	water.audio_surface = "deep_water"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = Vector3(3, 2, 3)
	shape.shape = box; water.add_child(shape)
	await add_to_tree(water)
	assert_eq(ch.player_audio.current_surface(), "deep_water", "actual Area3D overlap overrides floor")
	water.queue_free()
	await settle(2)
	floor.set_meta("audio_surface", "hard")
	assert_eq(ch.player_audio.current_surface(), "hard", "removing water clears override")
	var door := _floor()
	(door.get_child(0).shape as BoxShape3D).size = Vector3(2, 3, 0.1)
	door.position = Vector3(0, 1.5, -1.2)
	await add_to_tree(door)
	assert_false(ch.player_audio.try_locked_door(), "ordinary walls never rattle")
	door.set_meta("audio_locked_door", true)
	heard.clear()
	await _drive(ch, 2, CharacterInput.B_INTERACT)
	assert_eq(_count("door_locked"), 1, "F facing explicit locked door")
	await _drive(ch, 5, CharacterInput.B_INTERACT)
	assert_eq(_count("door_locked"), 1, "held F does not retrigger")
	door.remove_meta("audio_locked_door")
	door.set_meta("audio_fence", true)
	heard.clear()
	await _drive(ch, 50, 0, Vector2(0, 1))
	assert_eq(_count("fence"), 1, "actual fence contact rate limited")
	ch.queue_free(); floor.queue_free(); door.queue_free()
	await settle(1)

func test_exertion_requires_sustained_actual_sprint() -> void:
	heard.clear()
	var floor := _floor()
	await add_to_tree(floor)
	var ch := _character()
	await settle(5)
	await _drive(ch, 50, CharacterInput.B_SPRINT)
	assert_eq(_count("exertion"), 0, "holding shift while idle is silent")
	await _drive(ch, 440, CharacterInput.B_SPRINT, Vector2(0, 1))
	assert_eq(_count("exertion"), 1, "breath after seven seconds of actual sprint")
	assert_near(Vector2(ch.velocity.x, ch.velocity.z).length(), 6.5, 0.15, "audio never changes movement balance")
	ch.queue_free(); floor.queue_free()
	await settle(1)

func test_voice_priority_and_bounded_pool() -> void:
	var pool := PlayerAudioPool.new()
	await add_to_tree(pool)
	var played: Array = []
	pool.played.connect(func(event: String, _id: int, _path: String, _vol: float) -> void: played.append(event))
	pool.play_event("exertion", Vector3.ZERO, 933, 0.5)
	pool.play_event("hurt", Vector3.ZERO, 933, 0.8)
	pool.play_event("exertion", Vector3.ZERO, 933, 0.5)
	pool.play_event("death", Vector3.ZERO, 933, 1.0)
	pool.play_event("jump", Vector3.ZERO, 933, 0.5)
	pool.play_event("death", Vector3.ZERO, 933, 1.0)
	assert_eq(played, ["exertion", "hurt", "death"], "death wins and cannot be interrupted/duplicated")
	for i in 100:
		pool.play_event("step_metal", Vector3.ZERO, i + 1000, 0.5)
	assert_eq(pool.slots.size(), 24, "nearby crowd uses bounded pool")
	pool.queue_free()
	await settle(1)

func test_damage_model_and_network_bus() -> void:
	heard.clear()
	var ch := _character()
	ch.set_physics_process(false)
	var received: Array = []
	var listener := func(event: String, pos: Vector3, id: int, volume: float) -> void:
		if id == ch.character_id:
			received.append({"event": event, "pos": pos, "volume": volume})
	Events.player_sound.connect(listener)
	var weapon := ItemCatalog.weapon_def("ar15")
	var result := DamageModel.hit(weapon, "upperTorso", 1.0, ch.health)
	ch.apply_hit(result, null, "AR-15")
	assert_near(ch.health.hp, 72.0, 0.01, "real DamageModel changed health")
	assert_eq(_count("hurt"), 1, "apply_hit branch sounds")
	assert_eq(received.size(), 1, "Net fx reaches Events exactly once on offline authority")
	assert_eq(received[0].event, "hurt")
	assert_true((received[0].pos as Vector3).distance_to(ch.global_position) < 2.0, "spatial character position")
	ch.god_mode = true
	ch.take_plain_damage(30.0, null, "Gas")
	assert_eq(received.size(), 1, "invulnerable character never coughs for rejected damage")
	ch.god_mode = false
	result = DamageModel.hit(weapon, "head", 1.0, ch.health)
	ch.apply_hit(result, null, "AR-15")
	assert_eq(received.size(), 2)
	assert_eq(received[1].event, "death", "lethal DamageModel hit dispatches death, not hurt")
	Events.player_sound.disconnect(listener)
	ch.queue_free()
	await settle(1)

func test_manifest_stride_and_animation_contact_phase() -> void:
	assert_near(CharacterAudio.stride_metres({"speed_mps": 1.5, "duration_seconds": 28.0 / 30.0}), 0.7, 0.0001)
	assert_near(CharacterAudio.stride_metres({"speed_mps": 3.5, "duration_seconds": 22.0 / 30.0}), 1.283333, 0.0001)
	assert_near(CharacterAudio.stride_metres({"speed_mps": 6.5, "duration_seconds": 0.6}), 1.95, 0.0001)
	assert_near(CharacterAudio.stride_metres({"speed_mps": 1.2, "duration_seconds": 0.8}), 0.48, 0.0001)
	heard.clear()
	var floor := _floor()
	await add_to_tree(floor)
	var ch := _character()
	await settle(5)
	ch.set_physics_process(false)
	var driver: AnimationDriver = ch.visual.anim
	driver.set_process(false)
	driver.current = "KOTM_Walk"
	driver.lower_gait_clip = "KOTM_Walk"
	var player: AnimationPlayer = driver.player
	player.play(ch.visual.studio_rig.clips["KOTM_Walk"], 0.0)
	player.pause()
	for phase in [0.1, 0.49, 0.51, 0.99, 0.01]:
		driver.lower_gait_phase = phase
		player.seek(phase * player.current_animation_length, true)
		ch.player_audio.clock += 0.2
		ch.player_audio._tick_steps(0.01, 1.5, false)
	assert_eq(_count("step_"), 2, "exactly two strikes across the authored right/left contact crossings")
	if heard.size() >= 2:
		assert_eq(heard[0].event, "step_hard_right", "right strike at half-cycle")
		assert_eq(heard[1].event, "step_hard_left", "left strike at cycle wrap")
	ch.queue_free(); floor.queue_free()
	await settle(1)
