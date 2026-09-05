class_name ArmPoseModifier
extends SkeletonModifier3D
## Holds a gun with both hands: an analytic two-bone IK per arm pulls the right hand to a grip
## point in front of the chest along the aim direction and the left hand to the fore-grip, over
## whatever clip is playing (the mannequin has no armed animations). Blends in and out over a
## short ramp so drawing or holstering doesn't pop. Runs after AimSpine (child order), before the
## hitbox rig reads the final poses.

## Per weapon class: {grip: offset from the chest along aim (m), right: sideways (m), up: (m),
## support: distance from grip to the left hand along the barrel (m)}.
## The mannequin's arms are short (about 0.47 m shoulder to wrist), so the grip sits close to
## the chest and the torso twists toward the gun side so the support hand can reach.
const POSES := {
	"rifle": {"grip": 0.24, "right": 0.03, "up": -0.10, "support": 0.15, "sup_right": -0.04, "sup_up": -0.01},
	"sniper": {"grip": 0.24, "right": 0.03, "up": -0.10, "support": 0.17, "sup_right": -0.04, "sup_up": -0.01},
	"shotgun": {"grip": 0.24, "right": 0.03, "up": -0.10, "support": 0.16, "sup_right": -0.04, "sup_up": -0.01},
	"smg": {"grip": 0.25, "right": 0.03, "up": -0.09, "support": 0.11, "sup_right": -0.04, "sup_up": -0.01},
	"pistol": {"grip": 0.30, "right": 0.04, "up": -0.04, "support": 0.03, "sup_right": -0.04, "sup_up": -0.02},
	"bow": {"grip": 0.30, "right": 0.02, "up": 0.0, "support": 0.02, "sup_right": -0.03, "sup_up": 0.0},
}
## Torso yaw toward the gun side while armed (radians; the head counter-rotates to keep aim).
const TORSO_TWIST := -0.35

var weapon_class: String = ""
## Aim direction in skeleton space; set by the owner each frame. Zero = use +Z (mannequin forward).
var aim_dir: Vector3 = Vector3.ZERO
var weight: float = 0.0
var ramp_speed: float = 7.0
var chest_bone: int = -1
var head_bone: int = -1
var r_chain: PackedInt32Array = PackedInt32Array()
var l_chain: PackedInt32Array = PackedInt32Array()
var _last_msec: int = 0

func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	chest_bone = skel.find_bone("spine_02")
	head_bone = skel.find_bone("head")
	r_chain = PackedInt32Array([skel.find_bone("upperarm.r"), skel.find_bone("lowerarm.r"), skel.find_bone("hand.r")])
	l_chain = PackedInt32Array([skel.find_bone("upperarm.l"), skel.find_bone("lowerarm.l"), skel.find_bone("hand.l")])
	_last_msec = Time.get_ticks_msec()

func wants_pose() -> bool:
	return POSES.has(weapon_class)

func _process_modification() -> void:
	var skel := get_skeleton()
	if skel == null or chest_bone < 0 or r_chain[0] < 0 or l_chain[0] < 0:
		return
	var now := Time.get_ticks_msec()
	var dt := clampf(float(now - _last_msec) / 1000.0, 0.0, 0.1)
	_last_msec = now
	var target_w := 1.0 if wants_pose() else 0.0
	weight = move_toward(weight, target_w, dt * ramp_speed)
	if weight <= 0.001:
		return
	var pose: Dictionary = POSES.get(weapon_class, POSES["rifle"])
	var dir := aim_dir.normalized() if aim_dir.length_squared() > 0.5 else Vector3.BACK
	# skeleton space: mannequin faces +Z, so its right is -X
	var right := Vector3.UP.cross(dir).normalized() * -1.0
	if right.length_squared() < 0.01:
		right = Vector3.LEFT
	var up := dir.cross(right).normalized() * -1.0
	# shooting stance: twist the upper spine toward the gun side, keep the head on the aim
	var twist := Basis(Vector3.UP, TORSO_TWIST * weight * influence)
	var cg := skel.get_bone_global_pose(chest_bone)
	skel.set_bone_global_pose(chest_bone, Transform3D(twist * cg.basis, cg.origin))
	skel.force_update_bone_child_transform(chest_bone)
	if head_bone >= 0:
		var hg := skel.get_bone_global_pose(head_bone)
		skel.set_bone_global_pose(head_bone, Transform3D(twist.inverse() * hg.basis, hg.origin))
		skel.force_update_bone_child_transform(head_bone)
	var chest := skel.get_bone_global_pose(chest_bone).origin + Vector3(0, 0.12, 0)
	var grip := chest + dir * float(pose["grip"]) + right * float(pose["right"]) + up * float(pose["up"])
	var support := grip + dir * float(pose["support"]) + right * float(pose["sup_right"]) + up * float(pose["sup_up"])
	# elbows: right elbow out and down, left elbow down and slightly out
	_solve(skel, r_chain, grip, right * 0.6 - up * 0.5 - dir * 0.3, weight * influence)
	_solve(skel, l_chain, support, -right * 0.5 - up * 0.7 - dir * 0.2, weight * influence)

## Two-bone IK by rotating the global poses: point the upper arm so the elbow lands on the
## law-of-cosines circle nearest the pole, then point the forearm at the target.
func _solve(skel: Skeleton3D, chain: PackedInt32Array, target: Vector3, pole: Vector3, w: float) -> void:
	var a := skel.get_bone_global_pose(chain[0]).origin
	var b := skel.get_bone_global_pose(chain[1]).origin
	var c := skel.get_bone_global_pose(chain[2]).origin
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(c)
	if l1 < 0.01 or l2 < 0.01:
		return
	var to_t := target - a
	var d := clampf(to_t.length(), 0.02, (l1 + l2) * 0.985)
	var t_dir := to_t.normalized()
	# elbow position on the plane spanned by target dir and pole
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var ang := acos(cos_a)
	var side := (pole - t_dir * pole.dot(t_dir)).normalized()
	if side.length_squared() < 0.01:
		side = Vector3.DOWN
	var elbow := a + (t_dir * cos(ang) + side * sin(ang)) * l1
	var t_pos := a + t_dir * d
	# blend targets with the animated positions
	elbow = b.lerp(elbow, w)
	t_pos = c.lerp(t_pos, w)
	# upper arm: rotate so (b - a) becomes (elbow - a)
	_aim_bone(skel, chain[0], b - a, elbow - a)
	var b2 := skel.get_bone_global_pose(chain[1]).origin
	var c2 := skel.get_bone_global_pose(chain[2]).origin
	_aim_bone(skel, chain[1], c2 - b2, t_pos - b2)

static func _aim_bone(skel: Skeleton3D, bone: int, from_dir: Vector3, to_dir: Vector3) -> void:
	if from_dir.length_squared() < 1e-6 or to_dir.length_squared() < 1e-6:
		return
	var f := from_dir.normalized()
	var t := to_dir.normalized()
	var axis := f.cross(t)
	var s := axis.length()
	var cth := clampf(f.dot(t), -1.0, 1.0)
	if s < 1e-5:
		return
	var rot := Basis(axis / s, atan2(s, cth))
	var g := skel.get_bone_global_pose(bone)
	var new_global := Transform3D(rot * g.basis, g.origin)
	skel.set_bone_global_pose(bone, new_global)
	skel.force_update_bone_child_transform(bone)
