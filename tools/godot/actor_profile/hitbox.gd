extends HitboxRig
const PROFILE = preload("res://tools/godot/actor_profile/metrics.gd")

func _update_transforms() -> void:
	var clock := Time.get_ticks_usec()
	super._update_transforms()
	PROFILE.record("hitbox.pose_to_areas", clock)
