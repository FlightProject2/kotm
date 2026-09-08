extends TestCase

func test_empty_running_arms_oppose_the_knees_without_stretching() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.mode = Character.Mode.GROUND
	ch.velocity = Vector3.FORWARD * 5.2
	var rig: KOTMCharacterRig = ch.visual.studio_rig
	ch.visual.anim.set_process(false)
	ch.visual.anim.lower_gait_clip = "KOTM_Run"
	rig.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var skel := rig.skeleton
	var samples := {"count": 0, "worst_length_error": 0.0, "opposition": true}
	var observe := func():
		for side in ["l", "r"]:
			var upper := skel.find_bone("upperarm." + side)
			var lower := skel.find_bone("lowerarm." + side)
			var hand := skel.find_bone("hand." + side)
			var a := skel.get_bone_global_pose(upper).origin
			var b := skel.get_bone_global_pose(lower).origin
			var c := skel.get_bone_global_pose(hand).origin
			var ra := skel.get_bone_global_rest(upper).origin
			var rb := skel.get_bone_global_rest(lower).origin
			var rc := skel.get_bone_global_rest(hand).origin
			samples.worst_length_error = maxf(samples.worst_length_error, maxf(absf(a.distance_to(b) - ra.distance_to(rb)), absf(b.distance_to(c) - rb.distance_to(rc))))
			var thigh := skel.get_bone_global_pose(skel.find_bone("thigh." + side)).origin
			var knee := skel.get_bone_global_pose(skel.find_bone("calf." + side)).origin
			samples.opposition = samples.opposition and (b.z - a.z) * (knee.z - thigh.z) <= 0.00001
			samples.count += 1
	skel.get_node("RunningArms").modification_processed.connect(observe)
	for step in 12:
		ch.visual.anim.lower_gait_phase = float(step) / 12.0
		rig.play("KOTM_Run", 0)
		rig.player.seek(ch.visual.anim.lower_gait_phase * 0.6, true)
		await settle(2)
	assert_true(samples.count >= 24)
	assert_true(samples.opposition, "upper arms swing opposite each same-side advancing knee")
	assert_true(samples.worst_length_error < 0.001, "natural swing preserves upper/forearm bone lengths")
	ch.queue_free()
	await settle(1)

func test_parachute_hands_grip_fixed_risers_and_release_after_landing() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.mode = Character.Mode.PARACHUTE
	var skel: Skeleton3D = ch.visual.skeleton
	var contact: SkeletonModifier3D = skel.get_node("ParachuteContact")
	for yaw in [0.0, 1.2, -2.0]:
		ch.yaw = yaw
		ch.pitch = 0.7
		ch.input.aim_dir = Vector3(0, 0.6, -0.8)
		await settle(4)
		var errors: Dictionary = contact.contact_errors
		assert_eq(errors.size(), 2, "both parachute hands are wired to targets")
		for distance in errors.values(): assert_true(distance < 0.002, "palm touches riser at yaw %.2f: %.4f m" % [yaw, distance])
		assert_true(ch.visual.canopy.get_node("Riser_l").visible)
	ch.mode = Character.Mode.GROUND
	ch.velocity = Vector3.ZERO
	await settle(4)
	assert_true(contact.contact_errors.is_empty(), "landing releases the grip solver")
	assert_false(ch.visual.canopy.visible)
	ch.queue_free()
	await settle(1)
