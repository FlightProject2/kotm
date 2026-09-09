extends TestCase
## Authored winter surfaces must agree with playable ground and foliage exclusions.

func test_frozen_lakes_share_the_terrain_collider() -> void:
	var world: World = load("res://game/world/world.tscn").instantiate()
	await add_to_tree(world)
	world.setup("mesh")
	await settle(3)
	assert_true(world.surface_mask != null, "explicit winter surface mask is loaded")
	# In Godot the clockwise front-face normal is the negative geometric cross product.
	# Two-sided materials would otherwise flip the lighting normal toward the ground.
	var chunk := world.terrain.get_node("Visual").get_child(0) as MeshInstance3D
	var arrays := chunk.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var face_normal := -(vertices[indices[1]] - vertices[indices[0]]).cross(vertices[indices[2]] - vertices[indices[0]]).normalized()
	assert_true(face_normal.dot(normals[indices[0]]) > 0.5, "visible terrain front faces agree with upward lighting normals")
	for p in [Vector2(-805, 155), Vector2(815, 625)]:
		var y := world.height_at(p.x, p.y)
		assert_near(y, 18.0, 0.3, "frozen lake surface elevation")
		var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x, 350, p.y), Vector3(p.x, -20, p.y), 1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
		assert_false(hit.is_empty(), "ice supports a player")
		if not hit.is_empty():
			assert_near(hit.position.y, y, 0.06, "ice drawing and physics share one surface")
	world.queue_free()
	await settle(1)

func test_pine_forest_avoids_frozen_water_and_roads() -> void:
	var layout := MapLayout.load_default()
	assert_true(layout.trees.size() <= 8500, "tree bodies leave Jolt capacity for players and props")
	assert_true(layout.surface_mask_path != "", "mask has an explicit authored path")
	var texture: Texture2D = load(layout.surface_mask_path)
	var mask := texture.get_image()
	if mask.is_compressed():
		mask.decompress()
	assert_eq(mask.get_width(), 2048)
	assert_eq(mask.get_height(), 2048)
	for i in range(0, layout.trees.size(), 53):
		var t: Array = layout.trees[i]
		assert_true(String(t[2]).begins_with("tree_pine"), "winter conifer distribution")
		var c := mask.get_pixel(clampi(int(float(t[0]) + layout.half_size), 0, 2047), clampi(int(float(t[1]) + layout.half_size), 0, 2047))
		assert_true(c.r < 0.15 and c.g < 0.15 and c.b < 0.15, "tree is clear of roads, rail and ice")
