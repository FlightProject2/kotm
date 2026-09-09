extends CharacterAudio
const PROFILE = preload("res://tools/godot/actor_profile/metrics.gd")

func current_surface() -> String:
	var clock := Time.get_ticks_usec()
	var result = super.current_surface()
	PROFILE.record("audio.surface_ray", clock)
	return result

func _check_fence() -> void:
	var clock := Time.get_ticks_usec()
	super._check_fence()
	PROFILE.record("audio.fence_contacts", clock)
