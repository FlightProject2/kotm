class_name CrouchPoseModifier
extends SkeletonModifier3D
## Procedural crouch over any clip, done analytically so it can never flip: both thighs swing
## forward by [angle], both calves fold back by twice that, the feet level out, and the pelvis
## drops by exactly the height the folded legs lose, so the feet stay where the clip put them.
## The lower spine leans forward for the stealth-walk silhouette. Blends in and out over a ramp.

@export var angle: float = 1.0        ## thigh swing when fully crouched (radians, ~57 degrees)
@export var lean: float = 0.30        ## forward spine lean (radians)
@export var ramp_speed: float = 8.0
var crouching: bool = false
var weight: float = 0.0
var pelvis: int = -1
var spine: int = -1
var legs: Array = []                  # [[thigh, calf, foot], ...]
var leg_len: float = 0.0              # thigh + calf length from the rest pose
var _last_msec: int = 0
var _forward_axis := Vector3.LEFT     # rotation axis that swings a thigh toward the model's front
var _axis_checked := false

func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	pelvis = skel.find_bone("pelvis")
	spine = skel.find_bone("spine_01")
	for side in ["l", "r"]:
		var chain := [skel.find_bone("thigh." + side), skel.find_bone("calf." + side), skel.find_bone("foot." + side)]
		if chain[0] >= 0 and chain[1] >= 0 and chain[2] >= 0:
			legs.append(chain)
	if not legs.is_empty():
		var c: Array = legs[0]
		var a := skel.get_bone_global_rest(c[0]).origin
		var b := skel.get_bone_global_rest(c[1]).origin
		var f := skel.get_bone_global_rest(c[2]).origin
		leg_len = a.distance_to(b) + b.distance_to(f)
	_last_msec = Time.get_ticks_msec()

func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or pelvis < 0 or legs.is_empty():
		return
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_msec) / 1000.0, 0.0, 0.1)
	_last_msec = now
	weight = move_toward(weight, 1.0 if crouching else 0.0, dt * ramp_speed)
	if weight <= 0.001:
		return
	var w := weight * influence
	var th := angle * w
	if not _axis_checked:
		_pick_axis(skel)
	# pelvis drops by the height the folded legs lose: (l1 + l2) * (1 - cos th)
	var drop := leg_len * (1.0 - cos(th))
	var pg := skel.get_bone_global_pose(pelvis)
	skel.set_bone_global_pose(pelvis, Transform3D(pg.basis, pg.origin + Vector3(0, -drop, 0)))
	skel.force_update_bone_child_transform(pelvis)
	if spine >= 0:
		var sg := skel.get_bone_global_pose(spine)
		skel.set_bone_global_pose(spine, Transform3D(Basis(_forward_axis, lean * w) * sg.basis, sg.origin))
		skel.force_update_bone_child_transform(spine)
	for chain in legs:
		_rotate(skel, chain[0], th)          # thigh forward
		_rotate(skel, chain[1], -2.0 * th)   # knee folds back
		_rotate(skel, chain[2], th)          # foot level again

func _rotate(skel: Skeleton3D, bone: int, a: float) -> void:
	var g := skel.get_bone_global_pose(bone)
	skel.set_bone_global_pose(bone, Transform3D(Basis(_forward_axis, a) * g.basis, g.origin))
	skel.force_update_bone_child_transform(bone)

## The mannequin faces +Z in skeleton space; find the sign that swings the thigh toward +Z.
func _pick_axis(skel: Skeleton3D) -> void:
	_axis_checked = true
	var c: Array = legs[0]
	var hip := skel.get_bone_global_pose(c[0]).origin
	var knee := skel.get_bone_global_pose(c[1]).origin
	var down := (knee - hip).normalized()
	var swung := Basis(Vector3.LEFT, 0.5) * down
	_forward_axis = Vector3.LEFT if swung.z > down.z else Vector3.RIGHT
