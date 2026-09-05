class_name CrouchPoseModifier
extends SkeletonModifier3D
## Procedural crouch over any clip: the pelvis drops, the spine leans forward and both legs are
## solved with two-bone IK so the feet stay planted where the animation put them (knees bend
## instead of the whole model being squashed). Blends in and out over a short ramp. Runs before
## AimSpine / ArmPose (child order) so the upper-body modifiers build on the crouched torso.

@export var drop: float = 0.42        ## how far the pelvis drops when fully crouched (m)
@export var lean: float = 0.28        ## forward spine lean (radians)
@export var ramp_speed: float = 8.0
var crouching: bool = false
var weight: float = 0.0
var pelvis: int = -1
var spine: int = -1
var l_chain: PackedInt32Array = PackedInt32Array()
var r_chain: PackedInt32Array = PackedInt32Array()
var _last_msec: int = 0

func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	pelvis = skel.find_bone("pelvis")
	spine = skel.find_bone("spine_01")
	l_chain = PackedInt32Array([skel.find_bone("thigh.l"), skel.find_bone("calf.l"), skel.find_bone("foot.l")])
	r_chain = PackedInt32Array([skel.find_bone("thigh.r"), skel.find_bone("calf.r"), skel.find_bone("foot.r")])
	_last_msec = Time.get_ticks_msec()

func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or pelvis < 0 or l_chain[0] < 0 or r_chain[0] < 0:
		return
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_msec) / 1000.0, 0.0, 0.1)
	_last_msec = now
	weight = move_toward(weight, 1.0 if crouching else 0.0, dt * ramp_speed)
	if weight <= 0.001:
		return
	var w := weight * influence
	# remember where the clip put the feet, then drop the pelvis (moves the whole body)
	var lf := skel.get_bone_global_pose(l_chain[2]).origin
	var rf := skel.get_bone_global_pose(r_chain[2]).origin
	var pg := skel.get_bone_global_pose(pelvis)
	skel.set_bone_global_pose(pelvis, Transform3D(pg.basis, pg.origin + Vector3(0, -drop * w, 0)))
	skel.force_update_bone_child_transform(pelvis)
	# lean the lower spine forward (mannequin faces +Z in skeleton space: rotate about -X)
	if spine >= 0:
		var sg := skel.get_bone_global_pose(spine)
		skel.set_bone_global_pose(spine, Transform3D(Basis(Vector3.LEFT, lean * w) * sg.basis, sg.origin))
		skel.force_update_bone_child_transform(spine)
	# legs: plant the feet back where they were, knees forward
	_solve(skel, l_chain, lf, Vector3(0, -0.2, 1.0), w)
	_solve(skel, r_chain, rf, Vector3(0, -0.2, 1.0), w)

func _solve(skel: Skeleton3D, chain: PackedInt32Array, target: Vector3, pole: Vector3, w: float) -> void:
	var a := skel.get_bone_global_pose(chain[0]).origin
	var b := skel.get_bone_global_pose(chain[1]).origin
	var c := skel.get_bone_global_pose(chain[2]).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < 0.01 or l2 < 0.01:
		return
	var to_t := target - a
	var d := clampf(to_t.length(), 0.02, (l1 + l2) * 0.995)
	var t_dir := to_t.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var ang := acos(cos_a)
	var side := (pole - t_dir * pole.dot(t_dir)).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.BACK
	var knee := a + (t_dir * cos(ang) + side * sin(ang)) * l1
	var t_pos := a + t_dir * d
	knee = b.lerp(knee, w)
	t_pos = c.lerp(t_pos, w)
	ArmPoseModifier._aim_bone(skel, chain[0], b - a, knee - a)
	var b2 := skel.get_bone_global_pose(chain[1]).origin
	var c2 := skel.get_bone_global_pose(chain[2]).origin
	ArmPoseModifier._aim_bone(skel, chain[1], c2 - b2, t_pos - b2)
