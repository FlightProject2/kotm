extends BotBrain
const PROFILE = preload("res://tools/godot/actor_profile/metrics.gd")

func _perceive(is_melee: bool) -> void:
	var best: Character = null
	var bd := MELEE_SEARCH if is_melee else PERCEPTION_RANGE
	var eye := c.eye_position()
	var space := c.get_world_3d().direct_space_state
	for other in get_tree().get_nodes_in_group("characters"):
		var o := other as Character
		if o == null or o == c or not o.alive():
			continue
		var d := o.global_position.distance_to(c.global_position)
		if d >= bd:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, o.eye_position(), 1)
		var ray_clock := Time.get_ticks_usec()
		var ray_hit := space.intersect_ray(q)
		PROFILE.record("brain.ray_los", ray_clock)
		if not ray_hit.is_empty():
			continue
		var terrain_clock := Time.get_ticks_usec()
		var terrain_blocked := c.world and c.world.height_field.segment_hit(eye, o.eye_position(), 2.0) >= 0.0
		PROFILE.record("brain.terrain_los", terrain_clock)
		if terrain_blocked:
			continue
		bd = d
		best = o
	if best != target:
		react = rng.randf_range(0.2, 0.8)
	target = best
func _physics_process(dt: float) -> void:
	var clock := Time.get_ticks_usec()
	super._physics_process(dt)
	PROFILE.record("brain.total", clock)
func _pick_goal(pos: Vector3, need_zone: bool) -> void:
	var clock := Time.get_ticks_usec()
	super._pick_goal(pos, need_zone)
	PROFILE.record("brain.loot_goal", clock)

\r\n