extends TestCase
## Prone is authored on the same skeleton and selected by the runtime driver.

func test_prone_animation_family_and_selection() -> void:
	var floor := StaticBody3D.new(); floor.collision_layer = 1
	var collision := CollisionShape3D.new(); var shape := BoxShape3D.new()
	shape.size = Vector3(30, 1, 30); collision.shape = shape; floor.add_child(collision); floor.position.y = -0.5
	await add_to_tree(floor)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.position = Vector3(0, 0.05, 0)
	await add_to_tree(ch)
	await settle(8)
	for clip in ["KOTM_Prone_Idle", "KOTM_Prone_Crawl", "KOTM_Prone_Roll_L", "KOTM_Prone_Roll_R",
			"KOTM_AR75_Prone_Ready", "KOTM_AR75_Prone_Aim_Crawl"]:
		assert_true(ch.visual.studio_rig.clips.has(clip), "exported prone clip: " + clip)
	var prone := CharacterInput.new(); prone.set_button(CharacterInput.B_PRONE, true)
	ch.submit_input(prone)
	await settle(5)
	assert_eq(ch.visual.anim.current, "KOTM_Prone_Idle", "prone idle selected")
	var crawl := CharacterInput.new(); crawl.set_button(CharacterInput.B_PRONE, true); crawl.move = Vector2(0, 1)
	ch.submit_input(crawl)
	await settle(8)
	assert_eq(ch.visual.anim.current, "KOTM_Prone_Crawl", "crawl selected")
	var skel: Skeleton3D = ch.visual.skeleton
	await skel.skeleton_updated
	var pelvis := skel.get_bone_global_pose(skel.find_bone("pelvis")).origin
	var head := skel.get_bone_global_pose(skel.find_bone("head")).origin
	assert_true(absf(head.y - pelvis.y) < 0.65, "prone head stays low with the torso")
	ch.queue_free(); floor.queue_free()
	await settle(1)
