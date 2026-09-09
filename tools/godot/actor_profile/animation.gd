extends AnimationDriver
const PROFILE = preload("res://tools/godot/actor_profile/metrics.gd")

func _process(dt: float) -> void:
	if player == null:
		return
	if studio:
		_advance_lower_gait(dt)
	if character.is_bot:
		_lod_check -= dt
		if _lod_check <= 0.0:
			_lod_check = 0.5
			var d := 1.0e9
			if viewer and is_instance_valid(viewer) and viewer != character:
				d = viewer.global_position.distance_to(character.global_position)
			for tier in LOD:
				if d <= float(tier[0]):
					_every = int(tier[1])
					break
		_acc += dt
		_frame += 1
		if _frame % _every == 0:
			_pick_clip()
			var _clock_animation_player_advance := Time.get_ticks_usec()
			player.advance(_acc)
			PROFILE.record("animation.player_advance", _clock_animation_player_advance)
			if studio:
				var _clock_animation_skeleton_modifiers := Time.get_ticks_usec()
				studio.skeleton.advance(_acc)
				PROFILE.record("animation.skeleton_modifiers", _clock_animation_skeleton_modifiers)
			_acc = 0.0
		return
	_pick_clip()
