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
	assert_between(secs, 2.0, 12.0, "60 m descent takes 2-12 s (got %.1f)" % secs)
	assert_true(ch.stun > 0.0 or ch.mode == Character.Mode.GROUND, "landing stun / ground mode")
	assert_true(absf(ch.global_position.y - world.height_at(ch.global_position.x, ch.global_position.z)) < 0.3, "on the ground")
	assert_true(ch.global_position.z < 300.0 - 20.0, "drifted forward while diving")
	world.queue_free()
	await settle(1)

func test_studio_character_holds_both_risers() -> void:
	for armed in [false, true]:
		var ch: Character = load("res://game/character/character.tscn").instantiate()
		await add_to_tree(ch)
		if armed:
			ch.inventory.give_weapon("ar15")
		ch.motor.start_parachute(Vector3(0, 200, 0), 0.0)
		await settle(35)
		var skel: Skeleton3D = ch.visual.skeleton
		await skel.skeleton_updated
		var head := skel.get_bone_global_pose(skel.find_bone("head")).origin
		assert_eq(ch.visual.arm_pose.weapon_class, "parachute", "risers override weapon poses")
		for side in ["l", "r"]:
			var hand := skel.get_bone_global_pose(skel.find_bone("hand." + side)).origin
			assert_true(hand.y > head.y + 0.08, "hand stays above the head while hanging: " + side)
		if armed:
			assert_false(ch.visual.studio_rig.weapon_root("ar15").visible, "rifle is stowed under canopy")
		ch.queue_free()
		await settle(1)

func test_ram_air_parachute_model_is_wired() -> void:
	assert_true(ResourceLoader.exists("res://assets/models/kotm/KOTM_Parachute.glb"), "Higgsfield parachute GLB ships with the game")
	var packed := load("res://assets/models/kotm/KOTM_Parachute.glb") as PackedScene
	assert_true(packed != null, "parachute GLB loads")
	var model := packed.instantiate()
	assert_true(model.find_child("KOTM_Parachute_Root", true, false) != null, "named runtime root")
	assert_true(model.find_child("HandSocket_L", true, false) != null, "left riser socket")
	assert_true(model.find_child("HandSocket_R", true, false) != null, "right riser socket")
	var players := model.find_children("*", "AnimationPlayer", true, false)
	assert_false(players.is_empty(), "parachute contains exported animation actions")
	model.free()
