extends SkeletonModifier3D
## Pins the support wrist after AnimationPlayer has blended the authored poses.
## Only upper arm, forearm and wrist transforms change; finger poses stay authored.

var target_provider: Callable
var enabled_provider: Callable
var raw_error_m := 0.0
var corrected_error_m := 0.0
var orientation_error_rad := 0.0
var last_target := Transform3D.IDENTITY
var solve_count := 0
var upper_index := -1
var forearm_index := -1
var hand_index := -1

func _bone(rig: Skeleton3D, bone_name: String) -> int:
	var index := rig.find_bone(bone_name)
	return rig.find_bone(bone_name.replace(".", "_")) if index < 0 else index

func _process_modification() -> void:
	if not target_provider.is_valid() or not enabled_provider.is_valid() or not enabled_provider.call():
		return
	solve_target(target_provider.call())

func solve_target(target: Transform3D) -> void:
	var rig := get_skeleton()
	if rig == null:
		return
	if upper_index < 0:
		upper_index = _bone(rig, "upperarm.l")
		forearm_index = _bone(rig, "lowerarm.l")
		hand_index = _bone(rig, "hand.l")
	if upper_index < 0 or forearm_index < 0 or hand_index < 0:
		return
	var hand := rig.get_bone_global_pose(hand_index)
	raw_error_m = hand.origin.distance_to(target.origin)
	if raw_error_m < 0.0002 and hand.basis.get_rotation_quaternion().angle_to(target.basis.get_rotation_quaternion()) < 0.001:
		corrected_error_m = raw_error_m
		return
	var upper := rig.get_bone_global_pose(upper_index)
	var forearm := rig.get_bone_global_pose(forearm_index)
	var first_segment := forearm.origin - upper.origin
	var second_segment := hand.origin - forearm.origin
	var first_length := first_segment.length()
	var second_length := second_segment.length()
	if first_length < 0.001 or second_length < 0.001:
		return
	last_target = target
	raw_error_m = hand.origin.distance_to(target.origin)
	var reach := target.origin - upper.origin
	var distance := clampf(reach.length(), absf(first_length - second_length) + 0.00001, first_length + second_length - 0.00001)
	var direction := reach.normalized()
	# Keep the elbow on the animated side of the arm's bend plane.
	var bend_direction := first_segment - direction * first_segment.dot(direction)
	if bend_direction.length_squared() < 0.000001:
		bend_direction = upper.basis.z - direction * upper.basis.z.dot(direction)
	bend_direction = bend_direction.normalized()
	var along := (first_length * first_length + distance * distance - second_length * second_length) / (2.0 * distance)
	var height := sqrt(maxf(0.0, first_length * first_length - along * along))
	var elbow := upper.origin + direction * along + bend_direction * height
	var wrist := upper.origin + direction * distance
	var upper_delta := Quaternion(first_segment.normalized(), (elbow - upper.origin).normalized())
	var forearm_delta := Quaternion(second_segment.normalized(), (wrist - elbow).normalized())
	rig.set_bone_global_pose(upper_index, Transform3D(Basis(upper_delta) * upper.basis, upper.origin))
	rig.set_bone_global_pose(forearm_index, Transform3D(Basis(forearm_delta) * forearm.basis, elbow))
	rig.set_bone_global_pose(hand_index, Transform3D(target.basis, wrist))
	var result := rig.get_bone_global_pose(hand_index)
	corrected_error_m = result.origin.distance_to(target.origin)
	orientation_error_rad = result.basis.get_rotation_quaternion().angle_to(target.basis.get_rotation_quaternion())
	solve_count += 1
