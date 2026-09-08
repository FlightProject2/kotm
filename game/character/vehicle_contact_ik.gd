extends SkeletonModifier3D
## Hold both wrists on the moving controls and both ankles on the footrests after the
## fitted seated clip. Two-bone solves preserve the authored elbows/knees and fingers.

var character: Character
var rig: KOTMCharacterRig
var contact_errors: Dictionary = {}
var solve_count := 0
var _vehicle: Vehicle
var _chains: Array[Dictionary] = []
var _orientation_offsets: Dictionary = {}
var _spine_index := -1

func _ready() -> void:
	var skel := get_skeleton()
	_spine_index = skel.find_bone("spine_01")
	for side in ["l", "r"]:
		var suffix: String = side.to_upper()
		_chains.append({"bones": [skel.find_bone("upperarm." + side), skel.find_bone("lowerarm." + side), skel.find_bone("hand." + side)], "socket": "HandGrip_" + suffix})
		_chains.append({"bones": [skel.find_bone("thigh." + side), skel.find_bone("calf." + side), skel.find_bone("foot." + side)], "socket": "FootRest_" + suffix})

func _process_modification() -> void:
	if character == null or not character.in_vehicle():
		_vehicle = null
		_orientation_offsets.clear()
		contact_errors.clear()
		return
	if rig == null or not String(rig.player.current_animation).ends_with("Seated"):
		return
	if _vehicle != character.vehicle:
		_vehicle = character.vehicle
		_orientation_offsets.clear()
	var skel := get_skeleton()
	if _spine_index >= 0 and _vehicle.seated_animation() == "KOTM_Snowmobile_Seated":
		# A rider follows the bars with the shoulders while the pelvis remains planted.
		# This keeps the outside wrist reachable without lengthening either arm.
		var spine := skel.get_bone_global_pose(_spine_index)
		var turn := _vehicle.steer
		var follow := Basis.from_euler(Vector3(absf(turn) * 0.08, turn * 0.18, 0.0))
		skel.set_bone_global_pose(_spine_index, Transform3D(follow * spine.basis, spine.origin))
		skel.force_update_bone_child_transform(_spine_index)
	for chain in _chains:
		var bones: Array = chain.bones
		if -1 in bones:
			continue
		var socket: String = chain.socket
		var marker := _vehicle.contact_marker(socket)
		if marker == null:
			continue
		var target := skel.global_transform.affine_inverse() * marker.global_transform
		if not _orientation_offsets.has(socket):
			_orientation_offsets[socket] = target.basis.inverse() * skel.get_bone_global_pose(bones[2]).basis
		target.basis *= _orientation_offsets[socket]
		_solve(skel, bones, target, socket)
	solve_count += 1

func _solve(skel: Skeleton3D, bones: Array, target: Transform3D, socket: String) -> void:
	var upper := skel.get_bone_global_pose(bones[0])
	var middle := skel.get_bone_global_pose(bones[1])
	var end := skel.get_bone_global_pose(bones[2])
	var first := middle.origin - upper.origin
	var second := end.origin - middle.origin
	var a := first.length()
	var b := second.length()
	if a < 0.001 or b < 0.001:
		return
	var reach := target.origin - upper.origin
	if reach.length_squared() < 0.000001:
		return
	var distance := clampf(reach.length(), absf(a - b) + 0.00001, a + b - 0.00001)
	var direction := reach.normalized()
	var bend := first - direction * first.dot(direction)
	if bend.length_squared() < 0.000001:
		bend = upper.basis.z - direction * upper.basis.z.dot(direction)
	if bend.length_squared() < 0.000001:
		bend = direction.cross(Vector3.RIGHT)
	var along := (a * a + distance * distance - b * b) / (2.0 * distance)
	var elbow := upper.origin + direction * along + bend.normalized() * sqrt(maxf(0.0, a * a - along * along))
	var wrist := upper.origin + direction * distance
	skel.set_bone_global_pose(bones[0], Transform3D(Basis(Quaternion(first.normalized(), (elbow - upper.origin).normalized())) * upper.basis, upper.origin))
	skel.set_bone_global_pose(bones[1], Transform3D(Basis(Quaternion(second.normalized(), (wrist - elbow).normalized())) * middle.basis, elbow))
	skel.set_bone_global_pose(bones[2], Transform3D(target.basis, wrist))
	contact_errors[socket] = wrist.distance_to(target.origin)
