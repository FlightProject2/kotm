extends TestCase

func test_directional_legs_and_stationary_pose() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.mode = Character.Mode.GROUND
	ch.show_weapon("ar15", "rifle")
	ch.input.set_button(CharacterInput.B_AIM, true)
	ch.input.aim_dir = Vector3.FORWARD
	var vis: CharacterVisuals = ch.visual
	var rig := vis.studio_rig
	await settle(20)
	vis.anim.set_process(false)
	rig.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for suffix in ["Aim_Walk", "Aim_Jog", "Aim_Run", "Crouch_Aim_Walk"]:
		var clip: String = "KOTM_AR75_" + suffix
		if not rig.clips.has(clip):
			continue
		var info: Dictionary = KOTMCharacterRig.manifest.animations[clip]
		var native_speed := float(info.get("recommended_controller_speed_mps", info.get("speed_mps", 1)))
		for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3(-1, 0, -1).normalized(), Vector3(1, 0, 1).normalized()]:
			vis.anim.lower_gait_clip = "KOTM_" + suffix.replace("Aim_", "")
			rig.play(clip, 0)
			rig.player.speed_scale = 1
			rig.player.advance(0)
			ch.velocity = direction * native_speed
			vis.leg_ik.max_reach_error_m = 0
			var duration := rig.player.current_animation_length
			for step in 36:
				vis.anim.lower_gait_phase = float(step) / 36.0
				ch.position += ch.velocity * duration / 36.0
				rig.player.advance(duration / 36.0)
				await tree.process_frame
				await tree.process_frame
			assert_true(vis.leg_ik.max_reach_error_m < 0.035, "%s direction%s reach %.4fm" % [clip, direction, vis.leg_ik.max_reach_error_m])
	assert_true(vis.leg_ik.calls > 100, "directional modifier evaluated moving clips")
	ch.velocity = Vector3.ZERO
	vis.anim.lower_gait_clip = ""
	rig.play("KOTM_AR75_Aim", 0)
	rig.player.advance(0)
	await settle(3)
	var count: int = vis.leg_ik.calls
	await settle(3)
	assert_eq(vis.leg_ik.calls, count, "stationary authored foot placement is unchanged")
	ch.queue_free()
	await settle(1)

func test_fire_reload_keep_the_leg_clock() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.mode = Character.Mode.GROUND
	ch.show_weapon("ar15", "rifle")
	ch.velocity = Vector3(0, 0, -3.5)
	var driver: AnimationDriver = ch.visual.anim
	await settle(5)
	var initial_phase := driver.lower_gait_phase
	ch.fired.emit(1, 0)
	await settle(5)
	assert_true(driver.current.ends_with("Fire"), "moving fire plays upper-body recoil")
	assert_true(driver.lower_gait_phase != initial_phase, "firing advances rather than resets the step")
	var after_fire := driver.lower_gait_phase
	ch.combat.reload_t = 2
	await settle(5)
	assert_true(driver.current.ends_with("Reload"), "moving reload follows combat state")
	assert_true(driver.lower_gait_phase != after_fire and not driver.lower_gait_clip.is_empty(), "reload retains locomotion")
	ch.velocity = Vector3.ZERO
	await settle(3)
	assert_true(driver.audio_gait_state().is_empty(), "blocked/stationary motion has no footstep clock")
	ch.queue_free()
	await settle(1)
