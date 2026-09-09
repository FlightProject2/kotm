extends SkeletonModifier3D
## Turn the hips into lateral travel while the chest keeps facing the camera. Backward
## movement uses a back-pedal cycle instead of rotating both legs through each other.
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
	if character == null or character.in_vehicle() or character.mode != Character.Mode.GROUND or character.prone or character.rolling:
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
	var travel_angle := atan2(local_direction.x, local_direction.z)
	# A character facing the camera back-pedals for the rear half of the input circle.
	# Folding the angle into +/-90 degrees prevents the impossible crossover produced by
	# turning a forward stride 135-180 degrees underneath a forward-facing pelvis.
	var gait_angle := asin(clampf(sin(travel_angle), -1.0, 1.0))
	var hip_angle := gait_angle * 0.72
	var hip_turn := Basis(Vector3.UP, hip_angle)
	var redirect := Basis(Vector3.UP, gait_angle - hip_angle)
	var pelvis_index := skel.find_bone("pelvis")
	var spine_index := skel.find_bone("spine_01")
	var pelvis := skel.get_bone_global_pose(pelvis_index)
	var spine_basis := skel.get_bone_global_pose(spine_index).basis
	pelvis.basis = hip_turn * pelvis.basis
	skel.set_bone_global_pose(pelvis_index, pelvis)
	skel.force_update_bone_child_transform(pelvis_index)
	# Let the hips and legs open toward travel, but keep weapons, sightline and running
	# shoulders aligned with the character's facing direction.
	var spine := skel.get_bone_global_pose(spine_index)
	spine.basis = spine_basis
	skel.set_bone_global_pose(spine_index, spine)
	skel.force_update_bone_child_transform(spine_index)
	var targets: Array[Transform3D] = []
	var pelvis_drop := 0.0
	for side in 2:
		_centres[side] = _centres[side].lerp(next_centres[side], minf(1, get_process_delta_time() * 15))
		var chain: Array = _chains[side]
		var foot := skel.get_bone_global_pose(chain[2])
		var centre: Vector3 = pelvis.origin + hip_turn * (_centres[side] - pelvis.origin)
		var delta: Vector3 = foot.origin - centre
		delta.y = 0
		var target := foot
		target.origin += redirect * delta - delta
		target.basis = redirect * target.basis
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
		var pose := skel.get_bone_global_pose(pelvis_index)
		pose.origin.y -= pelvis_drop
		skel.set_bone_global_pose(pelvis_index, pose)
		skel.force_update_bone_child_transform(pelvis_index)
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
