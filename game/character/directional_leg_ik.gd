extends SkeletonModifier3D
## Redirect a forward clip's stride into velocity direction without turning the upper body
## or flipping the feet. Vertical lift, ankle roll, toe-out and the animated knee plane stay.
var character: Character
var rig: KOTMCharacterRig
var max_reach_error_m := 0.0
var calls := 0
var _clip := ""
var _centres: Array = []
var _chains: Array = []

func _ready() -> void:
	var skel := get_skeleton()
	for side in ["l", "r"]:
		_chains.append([skel.find_bone("thigh." + side), skel.find_bone("calf." + side), skel.find_bone("foot." + side)])

func _process_modification() -> void:
	if character == null or character.in_vehicle() or character.mode != Character.Mode.GROUND:
		return
	var key: String = character.visual.anim.lower_gait_clip if character.visual.anim else ""
	if not KOTMCharacterRig.stride_centres.has(key):
		_clip = ""
		return
	var velocity := Vector3(character.velocity.x, 0, character.velocity.z)
	if velocity.length_squared() < 0.0225:
		return
	var next_centres: Array = KOTMCharacterRig.stride_centres[key]
	if _centres.is_empty() or _clip == "":
		_centres = next_centres.duplicate()
	_clip = key
	var skel := get_skeleton()
	var local_direction := skel.global_basis.inverse() * velocity.normalized()
	var angle := atan2(local_direction.x, local_direction.z)
	var redirect := Basis(Vector3.UP, angle)
	var targets: Array[Transform3D] = []
	var pelvis_drop := 0.0
	for side in 2:
		_centres[side] = _centres[side].lerp(next_centres[side], minf(1, get_process_delta_time() * 15))
		var chain: Array = _chains[side]
		var foot := skel.get_bone_global_pose(chain[2])
		var delta: Vector3 = foot.origin - _centres[side]
		delta.y = 0
		var target := foot
		target.origin += redirect * delta - delta
		targets.append(target)
		var thigh := skel.get_bone_global_pose(chain[0])
		var calf := skel.get_bone_global_pose(chain[1])
		var a := thigh.origin.distance_to(calf.origin)
		var b := calf.origin.distance_to(foot.origin)
		# Redirecting a long sprint step sideways can require a lower hip than its forward
		# counterpart. Keep both ankle targets planted and retain at least14degrees of bend.
		var reach := target.origin - thigh.origin
		var allowed_squared := a * a + b * b + 2.0 * a * b * cos(deg_to_rad(14.0))
		var vertical := sqrt(maxf(0.0, allowed_squared - reach.x * reach.x - reach.z * reach.z))
		pelvis_drop = maxf(pelvis_drop, thigh.origin.y - target.origin.y - vertical)
	if pelvis_drop > 0.0:
		var pelvis := skel.find_bone("pelvis")
		var pose := skel.get_bone_global_pose(pelvis)
		pose.origin.y -= pelvis_drop
		skel.set_bone_global_pose(pelvis, pose)
		skel.force_update_bone_child_transform(pelvis)
	for side in 2:
		_solve(skel, _chains[side], targets[side])
	calls += 1

func _solve(skel: Skeleton3D, chain: Array, target: Transform3D) -> void:
	var thigh := skel.get_bone_global_pose(chain[0])
	var calf := skel.get_bone_global_pose(chain[1])
	var foot := skel.get_bone_global_pose(chain[2])
	var first := calf.origin - thigh.origin
	var second := foot.origin - calf.origin
	var a := first.length()
	var b := second.length()
	var reach := target.origin - thigh.origin
	var d := clampf(reach.length(), absf(a - b) + 0.00001, a + b - 0.00001)
	var direction := reach.normalized()
	var pole := first - direction * first.dot(direction)
	if pole.length_squared() < 0.000001:
		pole = Vector3.BACK - direction * Vector3.BACK.dot(direction)
	var along := (a * a + d * d - b * b) / (2 * d)
	var knee := thigh.origin + direction * along + pole.normalized() * sqrt(maxf(0, a * a - along * along))
	var ankle := thigh.origin + direction * d
	skel.set_bone_global_pose(chain[0], Transform3D(Basis(Quaternion(first.normalized(), (knee - thigh.origin).normalized())) * thigh.basis, thigh.origin))
	skel.set_bone_global_pose(chain[1], Transform3D(Basis(Quaternion(second.normalized(), (ankle - knee).normalized())) * calf.basis, knee))
	skel.set_bone_global_pose(chain[2], Transform3D(target.basis, ankle))
	max_reach_error_m = maxf(max_reach_error_m, ankle.distance_to(target.origin))
