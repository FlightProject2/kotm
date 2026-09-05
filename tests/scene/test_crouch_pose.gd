extends TestCase
## Crouching must bend the knees: the head drops, the feet stay planted, nothing is squashed.

func test_crouch_bends_knees() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(50, 1, 50); cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position.y = -0.5
	await add_to_tree(floor_body)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.position = Vector3(0, 0.05, 0)
	await add_to_tree(ch)
	await settle(30)
	var vis: CharacterVisuals = ch.visual
	var skel := vis.skeleton
	await skel.skeleton_updated
	var head := skel.find_bone("head")
	var foot_l := skel.find_bone("foot.l")
	var head_up: Vector3 = skel.global_transform * skel.get_bone_global_pose(head).origin
	var foot_up: Vector3 = skel.global_transform * skel.get_bone_global_pose(foot_l).origin
	var inp := CharacterInput.new()
	inp.set_button(CharacterInput.B_CROUCH, true)
	for i in 40:
		ch.submit_input(inp)
		await settle(1)
	await skel.skeleton_updated
	assert_true(ch.crouching, "motor is crouching")
	assert_true(vis.crouch_pose.weight > 0.95, "crouch pose blended in (%.2f)" % vis.crouch_pose.weight)
	var head_down: Vector3 = skel.global_transform * skel.get_bone_global_pose(head).origin
	var foot_down: Vector3 = skel.global_transform * skel.get_bone_global_pose(foot_l).origin
	assert_true(head_up.y - head_down.y > 0.3, "head dropped (%.2f m)" % (head_up.y - head_down.y))
	assert_true(absf(foot_down.y - foot_up.y) < 0.08, "foot stays planted (dy %.2f)" % (foot_down.y - foot_up.y))
	assert_true(is_equal_approx(vis.scale.y, 1.0), "no scale squash")
	ch.queue_free(); floor_body.queue_free()
	await settle(1)
