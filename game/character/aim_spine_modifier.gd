class_name AimSpineModifier
extends SkeletonModifier3D
## Bends spine_01 / spine_02 / head around the character's right axis by fractions of the view
## pitch so the upper body (and the weapon in the hand) follows where the player looks.
## Rotations are applied to the local poses (parent first) so they accumulate down the chain.

@export var pitch: float = 0.0
@export var weights := {"spine_01": 0.35, "spine_02": 0.45, "head": 0.2}
var _bones: Array = []   # [[bone_idx, weight], ...] in parent-first order
var calls: int = 0

func _ready() -> void:
	var skel := get_skeleton()
	if skel:
		for b in ["spine_01", "spine_02", "head"]:
			var bi := skel.find_bone(b)
			if bi >= 0:
				_bones.append([bi, float(weights.get(b, 0.0))])

func _process_modification() -> void:
	calls += 1
	var skel := get_skeleton()
	if skel == null or absf(pitch) < 0.0001:
		return
	# Skeleton space: the mannequin faces +Z there (Visual rotates it 180 deg), so its right
	# axis is -X. Rotating about -X by +pitch tilts the torso backwards = looking up.
	var axis := Vector3.LEFT
	for entry in _bones:
		var bi: int = entry[0]
		var angle: float = pitch * entry[1] * influence
		var g: Basis = skel.get_bone_global_pose(bi).basis
		var r := Basis(axis, angle)
		var local := Basis(skel.get_bone_pose_rotation(bi))
		var new_local := local * (g.inverse() * r * g)
		skel.set_bone_pose_rotation(bi, new_local.get_rotation_quaternion())
		skel.force_update_bone_child_transform(bi)
