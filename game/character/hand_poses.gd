class_name HandPoses
extends RefCounted
## Palm contact is offset from the wrist joint. Fingers use their authored local axes.
static func palm(side: String) -> Vector3:
	return Vector3(-0.022 if side == "l" else 0.022, 0.108, -0.005)

static func curl(skel: Skeleton3D, side: String, amount: float) -> void:
	for finger in ["index", "middle", "ring", "pinky"]:
		for joint in 3:
			var bone := skel.find_bone("%s_%02d.%s" % [finger, joint + 1, side])
			if bone < 0: continue
			var angle: float = [0.95, 1.4, 0.9][joint] * amount
			var rest := skel.get_bone_rest(bone).basis.get_rotation_quaternion()
			skel.set_bone_pose_rotation(bone, rest * Quaternion(Vector3.RIGHT, angle))
	var hand := skel.get_bone_global_pose(skel.find_bone("hand." + side))
	var sign := 1.0 if side == "l" else -1.0
	var directions := [Vector3(-0.1 * sign, 0.65, 0.75), Vector3(-0.15 * sign, 0.85, 0.5), Vector3(0, 0.8, 0.6)]
	for joint in 3:
		var bone := skel.find_bone("thumb_%02d.%s" % [joint + 1, side])
		if bone < 0: continue
		skel.set_bone_pose_rotation(bone, skel.get_bone_rest(bone).basis.get_rotation_quaternion())
		skel.force_update_bone_child_transform(bone)
		var from := skel.get_bone_global_pose(bone).basis.y
		var target: Vector3 = hand.basis * directions[joint].normalized()
		ArmPoseModifier._aim_bone(skel, bone, from, from.lerp(target, amount).normalized())

static func set_arm(skel: Skeleton3D, side: String, upper_direction: Vector3, lower_direction: Vector3) -> void:
	var upper := skel.find_bone("upperarm." + side)
	var lower := skel.find_bone("lowerarm." + side)
	var hand := skel.find_bone("hand." + side)
	var u_rest := skel.get_bone_global_rest(upper)
	var l_rest := skel.get_bone_global_rest(lower)
	var h_rest := skel.get_bone_global_rest(hand)
	var first := l_rest.origin - u_rest.origin
	var second := h_rest.origin - l_rest.origin
	var u := skel.get_bone_global_pose(upper)
	u.basis = Basis(Quaternion(first.normalized(), upper_direction.normalized())) * u_rest.basis
	skel.set_bone_global_pose(upper, u)
	skel.force_update_bone_child_transform(upper)
	var l := skel.get_bone_global_pose(lower)
	var rotation := Basis(Quaternion(second.normalized(), lower_direction.normalized()))
	l.basis = rotation * l_rest.basis
	skel.set_bone_global_pose(lower, l)
	skel.force_update_bone_child_transform(lower)
	var h := skel.get_bone_global_pose(hand)
	h.basis = rotation * h_rest.basis
	skel.set_bone_global_pose(hand, h)
