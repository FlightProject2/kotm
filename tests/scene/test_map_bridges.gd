extends TestCase
## Bridges carry traffic above the terrain without filling the underpass or railing gaps.

func test_rotated_footprint_and_highest_deck_query() -> void:
	var bridge := {"id": "diagonal", "ax": 10, "az": -20, "bx": 40, "bz": 20, "width": 10, "deckY": 3}
	assert_true(MapLandmarks.bridge_contains(bridge, 25, 0), "diagonal deck center")
	assert_true(MapLandmarks.bridge_contains(bridge, 29, -3), "inclusive exact side edge")
	assert_false(MapLandmarks.bridge_contains(bridge, 29.08, -3.06), "point outside the side")
	assert_true(MapLandmarks.bridge_contains(bridge, 29.08, -3.06, 0.2), "explicit footprint margin")
	assert_false(MapLandmarks.bridge_contains(bridge, 9.4, -20.8), "past the first abutment")
	assert_true(is_nan(MapLandmarks.bridge_top_at([bridge], 0, 0)), "no deck returns NAN")
	assert_near(MapLandmarks.bridge_top_at([bridge], 25, 0), 3.0)
	var higher := bridge.duplicate()
	higher["deckY"] = 4
	assert_near(MapLandmarks.bridge_top_at([bridge, higher], 25, 0), 4.0, 0.0001, "overlapping deck query uses the highest")
	var degenerate := bridge.duplicate()
	degenerate["bx"] = degenerate["ax"]
	degenerate["bz"] = degenerate["az"]
	assert_false(MapLandmarks.bridge_contains(degenerate, 10, -20), "zero length bridge is invalid")

func test_bridge_deck_underpass_and_open_rails_collide_as_drawn() -> void:
	var world: World = load("res://game/world/world.tscn").instantiate()
	await add_to_tree(world)
	world.setup("mesh")
	var maximum_ground := -INF
	for x in range(60, 141, 4):
		for z in range(688, 713, 4):
			maximum_ground = maxf(maximum_ground, world.height_field.height_at(x, z))
	var top := maximum_ground + 8.0
	var ground := world.height_at(100, 700)
	world.layout.bridges = [{"id": "physics_test", "ax": 70, "az": 700, "bx": 130, "bz": 700,
		"width": 10, "deckY": top, "thickness": 0.7}]
	var stats := MapLandmarks.build(world)
	await settle(3)
	assert_eq(stats["bridges"], 1)
	assert_eq(stats["bridge_meshes"], 1, "one merged mesh keeps bridge draw calls bounded")
	var body := world.props.get_node("Bridge_physics_test") as StaticBody3D
	var deck := body.get_node("DeckCollision") as CollisionShape3D
	assert_near(deck.position.y + (deck.shape as BoxShape3D).size.y * 0.5, 0.0, 0.0001, "local slab top is exactly zero")
	assert_near((deck.shape as BoxShape3D).size.x, 10.0)
	assert_near((deck.shape as BoxShape3D).size.z, 60.0)
	assert_near(body.global_transform.basis.determinant(), 1.0)
	var visual := body.get_node("BridgeMesh") as MeshInstance3D
	assert_eq(visual.mesh.get_surface_count(), 4, "concrete, asphalt, snow and timber share one mesh")
	var space := world.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(Vector3(100, top + 3, 700), Vector3(100, ground - 2, 700), 1)
	var hit := space.intersect_ray(ray)
	assert_false(hit.is_empty(), "deck supports a downward physics ray")
	if not hit.is_empty():
		assert_eq(hit["collider"], body)
		assert_near(hit["position"].y, top, 0.001, "collider top equals authored driving surface")
	# A point beyond the deck edge must still hit the original terrain height.
	ray = PhysicsRayQueryParameters3D.create(Vector3(100, top + 3, 706), Vector3(100, -50, 706), 1)
	hit = space.intersect_ray(ray)
	assert_false(hit.is_empty())
	if not hit.is_empty():
		assert_near(hit["position"].y, world.height_field.height_at(100, 706), 0.06, "bridge does not enlarge the ground")
	assert_near(world.height_at(100, 700), ground, 0.001, "ground queries below the bridge remain terrain queries")
	# Midspan is between the support piers. Crossing below the slab is genuinely open.
	ray = PhysicsRayQueryParameters3D.create(Vector3(100, top - 2, 692), Vector3(100, top - 2, 708), 1)
	assert_true(space.intersect_ray(ray).is_empty(), "underpass has no hidden solid wall")
	ray = PhysicsRayQueryParameters3D.create(Vector3(100, top + 0.8, 692), Vector3(100, top + 0.8, 708), 1)
	assert_true(space.intersect_ray(ray).is_empty(), "visible railing gaps pass rays")
	ray = PhysicsRayQueryParameters3D.create(Vector3(100, top + MapLandmarks.RAIL_HEIGHT, 692), Vector3(100, top + MapLandmarks.RAIL_HEIGHT, 708), 1)
	hit = space.intersect_ray(ray)
	assert_false(hit.is_empty(), "solid timber railing blocks rays")
	if not hit.is_empty():
		assert_eq(hit["collider"], body)
	# A human-sized capsule can occupy the space beneath the center of the bridge.
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.8
	var occupancy := PhysicsShapeQueryParameters3D.new()
	occupancy.shape = capsule
	occupancy.collision_mask = 1
	occupancy.transform = Transform3D(Basis.IDENTITY, Vector3(100, ground + 1.1, 700))
	assert_true(space.intersect_shape(occupancy).is_empty(), "player capsule fits beneath the deck above the original ground")
	world.queue_free()
	await settle(1)

func test_authored_crossings_join_roads_and_span_frozen_water() -> void:
	var world: World = load("res://game/world/world.tscn").instantiate()
	await add_to_tree(world)
	world.setup("mesh")
	var layout := world.layout
	assert_true(layout.pois.size() >= 12, "enhanced map includes the new peripheral destinations")
	for id: String in ["frostmere_lodge", "riverside_mill", "north_radar", "east_ranger_camp"]:
		assert_false(layout.poi(id).is_empty(), "authored destination exists: " + id)
	assert_true(layout.bridges.size() >= 2, "both river crossings have authored bridge decks")
	var stats := MapLandmarks.build(world)
	assert_eq(stats["bridges"], layout.bridges.size(), "all authored crossings are built")
	await settle(3)
	var mask := world.surface_mask.get_image()
	if mask.is_compressed():
		mask.decompress()
	var space := world.get_world_3d().direct_space_state
	for bridge: Dictionary in layout.bridges:
		var label := String(bridge["id"])
		var a := Vector2(float(bridge["ax"]), float(bridge["az"]))
		var b := Vector2(float(bridge["bx"]), float(bridge["bz"]))
		var span := a.distance_to(b)
		var direction := (b - a) / span
		var across := Vector2(direction.y, -direction.x)
		var midpoint := (a + b) * 0.5
		var top := float(bridge["deckY"])
		var width := float(bridge["width"])
		var ground := world.height_field.height_at(midpoint.x, midpoint.y)
		assert_near(world.road_height_at(midpoint.x, midpoint.y), top, 0.001, label + ": vehicles spawn on the deck")
		assert_near(world.height_at(midpoint.x, midpoint.y), ground, 0.001, label + ": ordinary ground query remains below the deck")
		assert_true(top - float(bridge.get("thickness", 0.7)) - ground > 2.0, label + ": usable clearance below the deck")
		var px := clampi(int(midpoint.x + layout.half_size), 0, mask.get_width() - 1)
		var pz := clampi(int(midpoint.y + layout.half_size), 0, mask.get_height() - 1)
		assert_true(mask.get_pixel(px, pz).b > 0.8, label + ": crossing spans authored ice")
		assert_near(ground, 18.0, 0.3, label + ": frozen river remains at its original water level")
		for end: Vector2 in [a, b]:
			for lane: float in [-0.22, 0.0, 0.22]:
				var p := end + across * width * lane
				assert_near(world.height_field.height_at(p.x, p.y), top, 0.3, label + ": terrain and deck join at abutment")
		# Probe both traffic lanes and the center from each approach over the whole span.
		# No content is built besides bridges, so hits here must be road terrain or deck.
		for distance: float in [-8.0, -4.0, -1.0, 0.0, 1.0, 4.0, span * 0.25, span * 0.5, span * 0.75, span - 4.0, span - 1.0, span, span + 1.0, span + 4.0, span + 8.0]:
			for lane: float in [-0.22, 0.0, 0.22]:
				var p := a + direction * distance + across * width * lane
				var expected := world.road_height_at(p.x, p.y)
				var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x, expected + 8.0, p.y), Vector3(p.x, expected - 15.0, p.y), 1)
				var hit := space.intersect_ray(ray)
				assert_false(hit.is_empty(), label + ": approach/deck has continuous collision at %.1f m" % distance)
				if not hit.is_empty():
					# At an exact box edge Jolt may select the adjoining terrain triangle.
					# Those two surfaces use the same 0.3 m abutment-seam budget above.
					var tolerance := 0.3 if is_zero_approx(distance) or is_equal_approx(distance, span) else 0.06
					assert_near(hit["position"].y, expected, tolerance, label + ": physics follows road surface at %.1f m" % distance)
		for seam: float in [0.0, span]:
			var before := a + direction * (seam - 0.5)
			var after := a + direction * (seam + 0.5)
			assert_near(world.road_height_at(before.x, before.y), world.road_height_at(after.x, after.y), 0.3, label + ": no step at deck seam")
	world.queue_free()
	await settle(1)
