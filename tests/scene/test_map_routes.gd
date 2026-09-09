extends TestCase
## Sample traversable road lanes against fixed scenery in the completely built world.
## Terrain and movable vehicles are deliberately outside camera-blocker layer 32.

const SAMPLE_SPACING := 15.0
const LANE_RADIUS := 0.9

func test_authored_road_centers_are_clear_of_fixed_scenery() -> void:
	var world: World = load("res://game/world/world.tscn").instantiate()
	await add_to_tree(world)
	world.setup("mesh", null, true)
	await settle(4)
	assert_true(world.build_stats.get("buildings", 0) > 0, "test includes populated settlements")
	assert_true(world.build_stats.get("trees", 0) > 0, "test includes physical forest trunks")
	var capsule := CapsuleShape3D.new()
	capsule.radius = LANE_RADIUS
	capsule.height = 1.8
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 32
	query.collide_with_areas = false
	var space := world.get_world_3d().direct_space_state
	var samples := 0
	var blocked_samples := 0
	var diagnostics: Array[String] = []
	for road: Dictionary in world.layout.roads:
		if road.get("type", "") == "rail":
			continue
		var points: Array = road.get("points", [])
		var traveled := 0.0
		var next_sample := 0.0
		for index in range(points.size() - 1):
			var a := Vector2(float(points[index][0]), float(points[index][1]))
			var b := Vector2(float(points[index + 1][0]), float(points[index + 1][1]))
			var length := a.distance_to(b)
			if length < 0.001:
				continue
			while next_sample <= traveled + length:
				var p := a.lerp(b, clampf((next_sample - traveled) / length, 0.0, 1.0))
				var position := Vector3(p.x, world.road_height_at(p.x, p.y) + 1.0, p.y)
				query.transform = Transform3D(Basis.IDENTITY, position)
				var hits := space.intersect_shape(query, 8)
				samples += 1
				if not hits.is_empty():
					blocked_samples += 1
					if diagnostics.size() < 40:
						var names: Array[String] = []
						for hit: Dictionary in hits:
							var collider: Object = hit.get("collider")
							var label := "physics body " + str(hit.get("rid", "unknown"))
							if collider is Node:
								label = String((collider as Node).name)
							if not names.has(label):
								names.append(label)
						diagnostics.append("%s at (%.2f, %.2f, %.2f): %s" % [String(road.get("id", "unnamed")), position.x, position.y, position.z, ", ".join(names)])
				next_sample += SAMPLE_SPACING
			traveled += length
	assert_true(samples > 300, "lane sweep samples the road network, including settlement streets and narrow trails")
	for diagnostic: String in diagnostics:
		print("ROAD_SCENERY_BLOCKED " + diagnostic)
	print("ROAD_SCENERY_SWEEP samples=%d blocked=%d radius=%.1f m" % [samples, blocked_samples, LANE_RADIUS])
	assert_eq(blocked_samples, 0, "fixed scenery blocks a lane center; see ROAD_SCENERY_BLOCKED coordinates above")
	world.queue_free()
	await settle(2)
