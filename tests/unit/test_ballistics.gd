extends TestCase

func test_drop_matches_analytic_within_2_percent() -> void:
	for id in ["ar15", "ak47", "hunting_rifle", "m9"]:
		var w: Dictionary = TestDamage.weapon(id)
		for d in [100.0, 200.0, 300.0]:
			var sim := Ballistics.simulate_drop(w, d)
			var ana := Ballistics.drop_at(d, w)
			assert_true(absf(sim - ana) <= ana * 0.02 + 0.02, "%s drop at %dm: sim %.3f analytic %.3f" % [id, d, sim, ana])

func test_ar15_drop_is_visible_at_range() -> void:
	var w: Dictionary = TestDamage.weapon("ar15")
	assert_between(Ballistics.drop_at(150.0, w), 0.4, 0.6, "AR-15 drops ~0.46 m at 150 m")
	assert_between(Ballistics.drop_at(300.0, w), 1.7, 2.0, "AR-15 drops ~1.8 m at 300 m")

func test_jitter_stays_inside_cone() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var dir := Vector3(0, 0, -1)
	for i in 500:
		var j := Ballistics.jitter(dir, 3.0, rng)
		assert_true(rad_to_deg(dir.angle_to(j)) <= 3.0001, "jitter within 3 degrees")
	assert_eq(Ballistics.jitter(dir, 0.0, rng), dir)

func test_shotgun_blast_sums_to_96() -> void:
	var w: Dictionary = TestDamage.weapon("shotgun_12g")
	assert_near(float(w["pellets"]) * float(w["pelletDamage"]), float(w["bodyDamage"]), 0.001)
