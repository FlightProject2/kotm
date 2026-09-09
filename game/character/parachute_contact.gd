extends SkeletonModifier3D
## Fixed riser targets own the pose; ropes no longer follow loosely raised wrists.
var character: Character
var solver := ArmPoseModifier.new()
var contact_errors: Dictionary = {}

static func grip(side: String) -> Vector3:
	return Vector3(0.24 if side == "l" else -0.24, 1.86, 0.10)

func _process_modification() -> void:
	contact_errors.clear()
	if character == null or character.mode != Character.Mode.PARACHUTE: return
	var skel := get_skeleton()
	for side in ["l", "r"]:
		var sign := 1.0 if side == "l" else -1.0
		var y := Vector3(-sign, 0, 0)
		var z := Vector3.DOWN
		var basis := Basis(y.cross(z), y, z)
		var target := grip(side) - basis * HandPoses.palm(side)
		var chain := PackedInt32Array([skel.find_bone("upperarm." + side), skel.find_bone("lowerarm." + side), skel.find_bone("hand." + side)])
		solver._solve(skel, chain, target, Vector3(sign, -0.3, -0.25), 1.0)
		var hand := skel.get_bone_global_pose(chain[2])
		hand.basis = basis
		skel.set_bone_global_pose(chain[2], hand)
		HandPoses.curl(skel, side, 1.0)
		contact_errors[side] = (hand.origin + hand.basis * HandPoses.palm(side)).distance_to(grip(side))

func _exit_tree() -> void:
	solver.free()
