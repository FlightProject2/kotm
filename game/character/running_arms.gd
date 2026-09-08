extends SkeletonModifier3D
## Empty hands swing opposite the advancing knee. Weapon/melee/seat poses own their arms.
var character: Character

func _process_modification() -> void:
	if character == null or character.mode != Character.Mode.GROUND or character.in_vehicle() or character.crouching:
		return
	if character.inventory.current_id() != "fists" or character.visual.anim == null:
		return
	var driver: AnimationDriver = character.visual.anim
	if driver.lower_gait_clip.is_empty() or Time.get_ticks_msec() / 1000.0 < driver.melee_until:
		return
	var skel := get_skeleton()
	for side in ["l", "r"]:
		var thigh := skel.get_bone_global_pose(skel.find_bone("thigh." + side)).origin
		var knee := skel.get_bone_global_pose(skel.find_bone("calf." + side)).origin
		var swing := clampf(-(knee.z - thigh.z) * 2.6, -0.65, 0.65)
		var lateral := 0.10 if side == "l" else -0.10
		var bend := deg_to_rad(85.0)
		HandPoses.set_arm(skel, side, Vector3(lateral, -cos(swing), sin(swing)), Vector3(0, -cos(swing + bend), sin(swing + bend)))
		HandPoses.curl(skel, side, 0.75)
