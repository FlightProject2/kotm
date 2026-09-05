extends TestCase
## Rays fired at bone positions must report the expected hit region.

func test_regions_from_bones() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(50, 1, 50)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position.y = -0.5
	await add_to_tree(floor_body)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.position = Vector3(0, 0.05, 0)
	await add_to_tree(ch)
	await settle(30)
	var rig: HitboxRig = ch.get_node("Hitboxes")
	await rig.skeleton.skeleton_updated
	assert_eq(rig.areas.size(), 14, "all hit regions created")
	var skel := rig.skeleton
	var checks := {"head": "head", "spine_02": "upperTorso", "spine_01": "lowerTorso", "thigh.l": "upperLegs", "calf.r": "lowerLegs", "lowerarm.l": "arms"}
	var space := ch.get_world_3d().direct_space_state
	for bone in checks:
		var bi := skel.find_bone(bone)
		var p: Vector3 = skel.global_transform * skel.get_bone_global_pose(bi).origin
		# for segment bones probe the middle of the segment
		var child: String = {"spine_02": "neck_01", "spine_01": "spine_02", "thigh.l": "calf.l", "calf.r": "foot.r", "lowerarm.l": "hand.l"}.get(bone, "")
		if child != "":
			var c: Vector3 = skel.global_transform * skel.get_bone_global_pose(skel.find_bone(child)).origin
			p = p.lerp(c, 0.5)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3(0, 0, -3), p + Vector3(0, 0, 3), 4)
		q.collide_with_areas = true
		q.collide_with_bodies = false
		var hit := space.intersect_ray(q)
		assert_false(hit.is_empty(), "ray through %s hits a hitbox" % bone)
		if not hit.is_empty():
			assert_eq(HitboxRig.region_of(hit["collider"]), checks[bone], "region for " + bone)
			assert_true(HitboxRig.character_of(hit["collider"]) == ch)
	# the mannequin faces -Z: toes are in front of ankles
	var foot := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("foot.l")).origin
	var ball := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("ball.l")).origin
	assert_true(ball.z < foot.z, "model faces -Z (ball.z %.2f < foot.z %.2f)" % [ball.z, foot.z])
	# aim spine bends the head back when looking up
	var vis: CharacterVisuals = ch.visual
	await skel.skeleton_updated
	var head_before: Vector3 = skel.get_bone_global_pose(skel.find_bone("head")).origin
	for i in 6:
		var inp := CharacterInput.new()
		inp.pitch = 0.8
		ch.submit_input(inp)
		await tree.physics_frame
	await skel.skeleton_updated
	var head_after: Vector3 = skel.get_bone_global_pose(skel.find_bone("head")).origin
	# skeleton space: the mannequin faces +Z there (Visual rotates it), so leaning back is -Z
	assert_true(head_after.z < head_before.z - 0.05, "looking up leans the head back (dz %.3f)" % (head_after.z - head_before.z))
	ch.queue_free()
	floor_body.queue_free()
	await settle(1)
