extends SkeletonModifier3D
## Align the complete authored stance to the camera's horizontal aim. The weapon is never
## moved independently of the hand/torso; the exported muzzle determines the facing offset.
var character: Character
var rig: KOTMCharacterRig
var visual: Node3D
var aim_weight := 0.0
var _last_tick := 0

func _process_modification() -> void:
	if character == null or rig == null:
		return
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_tick) / 1000000.0, 0, 0.1) if _last_tick > 0 else 0.016
	_last_tick = now
	if character.in_vehicle():
		visual.global_transform = character.vehicle.seat_transform()
		return
	# Clear the seat's local offset and terrain/body tilt when returning to foot movement.
	visual.position = Vector3.ZERO
	visual.rotation.x = 0.0
	visual.rotation.z = 0.0
	if KOTMCharacterRig.WEAPONS.has(rig.weapon_id) and character.mode != Character.Mode.PARACHUTE and character.combat.reload_t <= 0:
		var skel := get_skeleton()
		var aim_vector := character.input.aim_dir
		var aim_pitch := asin(clampf(aim_vector.normalized().y, -1, 1)) if aim_vector.length_squared() > 0.5 else character.pitch
		var aimed := character.input.pressed(CharacterInput.B_AIM) or String(rig.player.current_animation).ends_with("Fire")
		aim_weight = move_toward(aim_weight, 1.0 if aimed else 0.0, dt / 0.2)
		var muzzle_direction := (skel.global_basis.inverse() * rig.marker_world(rig.weapon_id).basis.z).normalized()
		var horizontal := Vector3(muzzle_direction.x, 0, muzzle_direction.z).normalized()
		var wanted_pitch := lerpf(-deg_to_rad(25.0), clampf(aim_pitch, -0.9, 0.9), aim_weight)
		var correction := wanted_pitch - asin(clampf(muzzle_direction.y, -1, 1))
		# One rigid upper-body rotation keeps the corrected stock/chest relationship intact.
		# Pivot below the ribs; the gun, both arms, neck and head all follow the same rotation.
		var spine := skel.find_bone("spine_01")
		var pose := skel.get_bone_global_pose(spine)
		skel.set_bone_global_pose(spine, Transform3D(Basis(horizontal.cross(Vector3.UP), correction) * pose.basis, pose.origin))
		skel.force_update_bone_child_transform(spine)
		var direction := visual.global_basis.inverse() * rig.marker_world(rig.weapon_id).basis.z
		var aim := character.input.aim_dir
		var yaw := atan2(-aim.x, -aim.z) if aim.length_squared() > 0.5 else character.yaw
		visual.rotation.y = lerp_angle(character.yaw, yaw - atan2(-direction.x, -direction.z), aim_weight)
	# Physics owns the jump trajectory. Remove just the airborne lift baked into this clip;
	# anticipation and landing knee flex remain in the animation.
	visual.position.y = 0
	if character.mode == Character.Mode.AIR and String(rig.player.current_animation).ends_with("Jump"):
		var t := rig.player.current_animation_position / 1.4
		if t > 0.28 and t < 0.80:
			var u := (t - 0.28) / 0.52
			visual.position.y = -0.34 * 4.0 * u * (1.0 - u)
