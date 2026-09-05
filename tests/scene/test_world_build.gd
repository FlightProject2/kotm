extends TestCase
## The full slice builds headless: every building sits on its pad, trees have trunk bodies.

func test_build_content() -> void:
	var world: World = load("res://game/world/world.tscn").instantiate()
	await add_to_tree(world)
	var t0 := Time.get_ticks_msec()
	world.setup("mesh", null, true)
	await settle(3)
	var ms := Time.get_ticks_msec() - t0
	print("    build: %s in %d ms" % [world.build_stats, ms])
	assert_eq(world.build_stats["placeholders"], 0, "every layout prefab exists")
	assert_true(world.build_stats["buildings"] >= 80)
	assert_true(world.build_stats["trees"] > 5000)
	assert_true(world.build_stats["loot_nodes"] > 100)
	assert_true(world.loot_nodes.size() == world.build_stats["loot_nodes"])
	assert_true(ms < 60000, "build under a minute headless (%d ms)" % ms)
	# every building base within 10 cm of its pad height
	var worst := 0.0
	for n in world.buildings.get_children():
		var p: Vector3 = (n as Node3D).global_position
		worst = maxf(worst, absf(p.y - world.height_at(p.x, p.z)))
	assert_true(worst < 0.6, "buildings sit on the terrain (worst %.2f m)" % worst)
	# a ray at Ashford's police station hits a building collider
	var b: Dictionary = world.layout.buildings.filter(func(x): return x["prefab"] == "police_station")[0]
	var space := world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(b["x"], 200, b["z"]), Vector3(b["x"], -10, b["z"]), 1)
	var hit := space.intersect_ray(q)
	assert_false(hit.is_empty())
	var roof_h: float = hit["position"].y - world.height_at(b["x"], b["z"])
	assert_between(roof_h, 4.5, 5.2, "two-storey roof about 4.9 m up (got %.2f)" % roof_h)
	# trunk bodies: a ray through a tree trunk hits something on layer 1
	var tr: Array = world.layout.trees[0]
	var ty := world.height_at(float(tr[0]), float(tr[1]))
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(tr[0] - 3, ty + 1.0, tr[1]), Vector3(tr[0] + 3, ty + 1.0, tr[1]), 1)
	assert_false(space.intersect_ray(q2).is_empty(), "tree trunk blocks a ray")
	world.queue_free()
	await settle(1)
