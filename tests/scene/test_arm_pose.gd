extends TestCase
## Real game character: authored ready/aim poses, attached muzzle and post-blend support contact.

func test_hands_reach_the_gun() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.mode = Character.Mode.GROUND
	var vis: CharacterVisuals = ch.visual
	var rig := vis.studio_rig
	assert_true(rig != null, "studio rig replaces the mannequin")
	assert_eq(rig.skeleton.get_bone_count(), 54)
	for clip_name in KOTMCharacterRig.manifest.animations:
		assert_true(rig.clips.has(clip_name), "exported clip imported: " + String(clip_name))
	assert_true(rig.errors.is_empty(), "all manifest meshes resolved")
	var measurement := {"error": 0.0, "samples": 0}
	rig.support_hand.modification_processed.connect(func() -> void:
		if rig.contact_enabled:
			var wrist := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone("hand.l"))
			var target: Transform3D = rig.marker_world(rig.weapon_id) * rig.wrist_offsets[rig.weapon_id]
			measurement.error = maxf(measurement.error, wrist.origin.distance_to(target.origin))
			measurement.samples += 1)
	for id in ["ar15", "hunting_rifle"]:
		ch.show_weapon(id, "rifle" if id == "ar15" else "sniper")
		for crouch in [false, true]:
			ch.crouching = crouch
			for aim in [false, true, false]:
				ch.input.set_button(CharacterInput.B_AIM, aim)
				ch.input.aim_dir = Vector3.FORWARD
				for frame in 20:
					ch.position.x += 0.01
					await settle(1)
				assert_true(vis.anim.current.ends_with("Aim") if aim else vis.anim.current.ends_with("Ready"), "stance follows game input")
				var muzzle := ch.combat.muzzle_position()
				assert_true(muzzle.distance_to(rig.marker_world(id).origin) < 0.001, "combat uses exported muzzle")
				var dir := rig.marker_world(id).basis.z
				if aim:
					assert_true(Vector2(dir.x, dir.z).normalized().dot(Vector2(0, -1)) > 0.99, "aimed muzzle yaw follows camera")
				else:
					assert_near(vis.rotation.y, ch.yaw, 0.01, "ready body faces forward with lowered diagonal carry")
		ch.input.set_button(CharacterInput.B_AIM, true)
		for pitch in [-0.5, 0.5]:
			ch.pitch = pitch
			ch.input.aim_dir = Vector3(0, sin(pitch), -cos(pitch))
			await settle(20)
			await rig.skeleton.skeleton_updated
			assert_true(rig.marker_world(id).basis.z.normalized().dot(ch.input.aim_dir) > 0.99, "muzzle follows nonzero camera pitch")
		ch.pitch = 0
		ch.input.aim_dir = Vector3.FORWARD
	assert_true(measurement.samples > 60, "sampled actual modifier updates")
	assert_true(measurement.error < 0.002, "support wrist remains on grip (%.5f m)" % measurement.error)
	ch.queue_free()
	await settle(1)
