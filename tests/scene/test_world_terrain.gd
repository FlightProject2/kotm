extends TestCase
## Physics raycasts against each terrain backend must agree with HeightField.height_at.

const WORLD_SCENE := "res://game/world/world.tscn"

func _probe(world: World, count: int, tolerance: float) -> Array:
	var space := world.get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var hits := 0
	var worst := 0.0
	for i in count:
		var x := rng.randf_range(-950, 950)
		var z := rng.randf_range(-950, 950)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400, z), Vector3(x, -50, z), 1)
		var r := space.intersect_ray(q)
		if r.is_empty():
			continue
		hits += 1
		worst = maxf(worst, absf(r.position.y - world.height_at(x, z)))
	return [hits, worst]

func test_mesh_backend_matches_heightfield() -> void:
	var world: World = load(WORLD_SCENE).instantiate()
	await add_to_tree(world)
	world.setup("mesh")
	await settle(3)
	assert_eq(world.backend_name, "mesh")
	var r := _probe(world, 60, 0.05)
	assert_eq(r[0], 60, "every downward ray hits the mesh terrain")
	assert_true(r[1] < 0.06, "worst error %.3f m" % r[1])
	world.queue_free()
	await settle(1)
