extends SkeletonModifier3D
## The lower-body clock is independent of recoil/reload. Sampling the same imported tracks
## keeps hips and feet moving through repeated shots without restarting the step cycle.
var character: Character
var rig: KOTMCharacterRig
var driver: AnimationDriver
var _tracks: Dictionary = {}
var _animations: Dictionary = {}
var _skeleton: Skeleton3D
const BONES := ["pelvis", "spine_01", "thigh.l", "calf.l", "foot.l", "ball.l", "thigh.r", "calf.r", "foot.r", "ball.r"]

func _ready() -> void:
	_skeleton = get_skeleton()

func _process_modification() -> void:
	if character == null or _skeleton == null or character.mode != Character.Mode.GROUND or character.in_vehicle() or character.prone or character.rolling:
		return
	if driver == null:
		driver = character.visual.anim
	if driver == null:
		return
	var key := driver.lower_gait_clip
	var phase := driver.lower_gait_phase
	if key.is_empty():
		if character.crouching and character.combat.reload_t > 0:
			key = "KOTM_Crouch_Idle"
			phase = 0.0
		else:
			return
	if not rig.clips.has(key):
		return
	# A forward clip played backwards gives a readable back-pedal: the lifted knee and
	# planting foot now lead travel instead of moonwalking while S is held.
	var planar := Vector3(character.velocity.x, 0.0, character.velocity.z)
	if planar.length_squared() > 0.0225:
		var local_motion := rig.skeleton.global_basis.inverse() * planar.normalized()
		if local_motion.z < -0.05:
			phase = fposmod(1.0 - phase, 1.0)
	if not _animations.has(key):
		_animations[key] = rig.player.get_animation(rig.clips[key])
	var animation: Animation = _animations[key]
	if not _tracks.has(key):
		_tracks[key] = []
		for index in animation.get_track_count():
			var path := animation.track_get_path(index)
			if path.get_subname_count() == 0:
				continue
			var bone := String(path.get_subname(path.get_subname_count() - 1))
			if bone in BONES:
				_tracks[key].append([index, _skeleton.find_bone(bone), animation.track_get_type(index)])
	var time := phase * animation.length
	for entry in _tracks[key]:
		var track: int = entry[0]
		var bone: int = entry[1]
		match entry[2]:
			Animation.TYPE_POSITION_3D: _skeleton.set_bone_pose_position(bone, animation.position_track_interpolate(track, time))
			Animation.TYPE_ROTATION_3D: _skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(track, time))
			Animation.TYPE_SCALE_3D: _skeleton.set_bone_pose_scale(bone, animation.scale_track_interpolate(track, time))
