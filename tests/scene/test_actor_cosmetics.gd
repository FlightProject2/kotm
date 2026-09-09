extends TestCase
## Equivalence checks for cosmetic resource caches and the idle muzzle/recoil process.

func _spawn() -> Character:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.visual.anim.set_process(false)
	ch.visual.anim.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return ch

func test_actual_fire_events_restart_idle_holder_and_independent_flash() -> void:
	var ch: Character = await _spawn()
	var holder: WeaponHolder = ch.visual.weapon_holder
	var rig: KOTMCharacterRig = ch.visual.studio_rig
	assert_false(holder.is_processing(), "idle holders consume no process callback")
	assert_false(holder.flash.visible or holder.flash.is_processing(), "no idle flash or light")
	assert_true(ch.visual.skeleton.skeleton_updated.is_connected(holder._align), "bone alignment stays signal driven")
	for weapon_id in ["ar15", "ak47"]:
		assert_true(rig.weapon_root(weapon_id) != null and rig.muzzle_nodes.get(weapon_id) != null, weapon_id + " canonical root and muzzle exist")
		if rig.weapon_root(weapon_id) == null or rig.muzzle_nodes.get(weapon_id) == null:
			continue
		ch.show_weapon(weapon_id, "rifle")
		var before: int = holder.flash.shot_count
		ch.fired.emit(0.55, 0.18)
		assert_eq(holder.flash.shot_count, before + 1, "real Character.fired reaches " + weapon_id)
		assert_true(holder.is_processing() and holder.flash.is_processing(), "first shot wakes recoil and independent FX")
		assert_near(holder.flash.global_position.distance_to(rig.marker_world(weapon_id).origin), 0, 0.00001, "flash starts at actual muzzle")
		assert_true(holder.flash.global_basis.z.dot(rig.marker_world(weapon_id).basis.z.normalized()) > 0.9999, "burst points out of barrel")
		ch.global_position += Vector3(0.12, 0, -0.08)
		holder._align()
		assert_near(holder.flash.global_position.distance_to(rig.marker_world(weapon_id).origin), 0, 0.00001, "signal alignment follows moving muzzle")
		await tree.create_timer(0.12).timeout
		assert_false(holder.is_processing(), "recoil stops its own callback")
		assert_true(holder.flash.is_processing() and holder.flash.smoke.visible, "child smoke continues with idle parent")
		ch.fired.emit(0.55, -0.18)
		assert_eq(holder.flash.shot_count, before + 2, "next shot reuses effect")
		assert_true(holder.is_processing() and holder.flash.is_flashing(), "next shot wakes idle parent and restarts flash")
		await tree.create_timer(0.32).timeout
		assert_false(holder.is_processing() or holder.flash.is_processing(), "recoil and complete flash lifetime return to idle")
		assert_false(holder.flash.visible or holder.flash.light.visible, "no residual light")
		assert_near(holder.flash.light.light_energy, 0.0)
	ch.fired.emit(0.55, 0.0)
	ch.show_weapon("fists", "melee")
	assert_false(holder.flash.visible or holder.flash.is_processing(), "weapon change stops previous muzzle effect")
	var count: int = holder.flash.shot_count
	ch.fired.emit(0.0, 0.0)
	assert_eq(holder.flash.shot_count, count, "unarmed signal never spawns gun flash")
	ch.queue_free()
	await settle(1)

func test_contact_composition_and_equipment_state_remain_equivalent() -> void:
	var ch: Character = await _spawn()
	var rig: KOTMCharacterRig = ch.visual.studio_rig
	ch.visual.set_process(false)
	ch.visual.set_physics_process(false)
	for weapon_id in ["ar15", "ak47", "hunting_rifle"]:
		assert_true(rig.muzzle_bindings.has(weapon_id), weapon_id + " has real bone binding")
		ch.show_weapon(weapon_id, "rifle")
		for clip_suffix in ["Ready", "Aim", "Fire", "Reload", "Walk", "Crouch_Fire"]:
			var clip: String = "KOTM_" + KOTMCharacterRig.WEAPONS[weapon_id] + "_" + clip_suffix
			rig.play(clip, 0)
			for phase in [0.0, 0.3, 0.8]:
				rig.player.seek(phase * rig.player.get_animation(rig.clips[clip]).length, true)
				rig.player.advance(0)
				for location in [Vector3.ZERO, Vector3(1250.0, 42.0, -870.0)]:
					ch.global_position = location
					ch.visual.rotation = Vector3(0.12, 0.7, -0.1)
					var expected: Transform3D = rig.skeleton.global_transform.affine_inverse() * rig.marker_world(weapon_id) * rig.wrist_offsets[weapon_id]
					var actual := rig._contact_target()
					assert_near(actual.origin.distance_to(expected.origin), 0, 0.0003, "contact target including far map coordinates")
					assert_true(actual.basis.is_equal_approx(expected.basis), "contact orientation unchanged")
	for helmet in [false, true]:
		for armour in [false, true]:
			for backpack in [false, true]:
				rig.set_equipment(helmet, armour, backpack)
				assert_eq(rig.equipment, {"helmet": helmet, "armour": armour, "backpack": backpack})
				assert_eq(rig.roots.Helmet.visible, helmet)
				assert_eq(rig.roots.Armour.visible, armour)
				assert_eq(rig.roots.Backpack.visible, backpack)
				var state: Dictionary = rig.equipment
				rig.set_equipment(helmet, armour, backpack)
				assert_true(is_same(rig.equipment, state), "unchanged equipment preserves dictionary and visibility state")
	ch.queue_free()
	await settle(1)

func test_cached_clip_metadata_matches_source_and_fire_reload_transitions() -> void:
	var ch: Character = await _spawn()
	var driver: AnimationDriver = ch.visual.anim
	var rig: KOTMCharacterRig = ch.visual.studio_rig
	for clip in rig.clips:
		var animation: Animation = rig.player.get_animation(rig.clips[clip])
		assert_near(driver._clip_duration(clip), animation.length, 0.000001, clip + " duration")
		assert_near(driver._clip_duration(clip), animation.length, 0.000001, clip + " cached duration")
		var info: Dictionary = KOTMCharacterRig.manifest.get("animations", {}).get(clip, {})
		var authored := float(info.get("recommended_controller_speed_mps", info.get("speed_mps", 0)))
		for speed in [0.0, 0.3, 1.6, 3.7, 6.0, 20.0]:
			var expected := clampf(speed / authored, 0.25, 1.5) if authored > 0.01 else 1.0
			assert_near(driver._native_speed_scale(clip, speed), expected, 0.000001, clip + " speed")
	ch.mode = Character.Mode.GROUND
	ch.velocity = Vector3.ZERO
	for weapon_id in ["ar15", "ak47", "hunting_rifle"]:
		ch.show_weapon(weapon_id, "rifle")
		var prefix: String = "KOTM_" + KOTMCharacterRig.WEAPONS[weapon_id] + "_"
		assert_eq(driver.current, prefix + "Ready", "weapon change immediately updates clip")
		ch.fired.emit(0.5, 0.1)
		driver._pick_studio_clip()
		assert_eq(driver.current, prefix + "Fire", "fire event remains immediate")
		ch.combat.reload_t = 1.8
		driver._pick_studio_clip()
		assert_eq(driver.current, prefix + "Reload")
		assert_near(driver.player.speed_scale, rig.player.get_animation(rig.clips[prefix + "Reload"]).length / 1.8, 0.000001, "reload timing uses unchanged authored duration")
		ch.combat.reload_t = 0
	ch.queue_free()
	await settle(1)

func test_locomotion_cache_preserves_each_interpolated_bone_track() -> void:
	var ch: Character = await _spawn()
	var rig: KOTMCharacterRig = ch.visual.studio_rig
	var driver: AnimationDriver = ch.visual.anim
	var layer: SkeletonModifier3D
	for child in rig.skeleton.get_children():
		if child.get_script() == load("res://game/character/locomotion_layer.gd"):
			layer = child
	assert_true(layer != null, "existing locomotion modifier retained")
	ch.mode = Character.Mode.GROUND
	for key in ["KOTM_Walk", "KOTM_Jog", "KOTM_Run", "KOTM_Crouch_Walk"]:
		if not rig.clips.has(key):
			continue
		var animation: Animation = rig.player.get_animation(rig.clips[key])
		for phase in [0.0, 0.17, 0.5, 0.91]:
			driver.lower_gait_clip = key
			driver.lower_gait_phase = phase
			layer._process_modification()
			for track in animation.get_track_count():
				var path := animation.track_get_path(track)
				if path.get_subname_count() == 0:
					continue
				var bone_name := String(path.get_subname(path.get_subname_count() - 1))
				if bone_name not in layer.BONES:
					continue
				var bone := rig.skeleton.find_bone(bone_name)
				var time: float = phase * animation.length
				match animation.track_get_type(track):
					Animation.TYPE_POSITION_3D:
						assert_near(rig.skeleton.get_bone_pose_position(bone).distance_to(animation.position_track_interpolate(track, time)), 0, 0.000001, key + " position " + bone_name)
					Animation.TYPE_ROTATION_3D:
						assert_true(absf(rig.skeleton.get_bone_pose_rotation(bone).dot(animation.rotation_track_interpolate(track, time))) > 0.99999, key + " rotation " + bone_name)
					Animation.TYPE_SCALE_3D:
						assert_near(rig.skeleton.get_bone_pose_scale(bone).distance_to(animation.scale_track_interpolate(track, time)), 0, 0.000001, key + " scale " + bone_name)
	# The unused arm aim may stay cached while fitted; it must refresh on reactivation.
	ch.show_weapon("ar15", "rifle")
	ch.visual._process_studio()
	assert_false(ch.visual.arm_pose.active)
	ch.input.aim_dir = Vector3(0.3, 0.2, -1.0).normalized()
	ch.show_weapon("fists", "melee")
	ch.visual._process_studio()
	assert_true(ch.visual.arm_pose.active)
	assert_near(ch.visual.arm_pose.aim_dir.distance_to(ch.visual.skeleton.global_basis.inverse() * ch.input.aim_dir), 0, 0.000001, "reactivated aim reflects current input")
	ch.queue_free()
	await settle(1)
