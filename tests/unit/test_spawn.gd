extends TestCase

func test_spawn_spacing_mask_and_determinism() -> void:
	var hf := HeightField.load_from("res://world/terrain/heightmap_2km.res")
	var preset: Dictionary = DataLib.preset("slice_2km")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var pts: Array = SpawnSelector.pick(31, hf, preset, rng)
	assert_eq(pts.size(), 31)
	var half := float(preset["mapHalfSizeM"]) - float(preset["borderMarginM"])
	var min_d := INF
	for i in pts.size():
		var p: Vector3 = pts[i]
		assert_true(absf(p.x) <= half and absf(p.z) <= half, "inside the border")
		var ground := hf.height_at(p.x, p.z)
		assert_near(p.y - ground, float(preset["spawnAltitudeM"]), 0.01, "at spawn altitude")
		assert_true(ground <= float(preset["spawnMaxHeightM"]), "not on the mountain top")
		for j in range(i + 1, pts.size()):
			min_d = minf(min_d, Vector2(p.x - pts[j].x, p.z - pts[j].z).length())
	assert_true(min_d >= 60.0, "spacing respected even after relaxation (min %.0f m)" % min_d)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 99
	var pts2: Array = SpawnSelector.pick(31, hf, preset, rng2)
	assert_eq(pts, pts2, "same seed, same spawns")
