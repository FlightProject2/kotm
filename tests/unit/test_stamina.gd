extends TestCase

func test_exhaustion_recovery_and_sneakers() -> void:
	var cfg: Dictionary = DataLib.movement()["stamina"]
	var stamina := SprintStamina.new()
	for i in 480:
		stamina.tick(1.0 / 60.0, true, true, false, cfg)
	assert_true(stamina.exhausted, "eight seconds exhausts the reserve")
	assert_false(stamina.tick(0.8, true, true, false, cfg), "holding sprint cannot bypass recovery delay")
	assert_near(stamina.value, 0.0, 0.0001)
	assert_false(stamina.tick(1.0, true, true, false, cfg))
	assert_true(stamina.tick(0.75, true, true, false, cfg), "resume only after 35 stamina")
	assert_true(stamina.tick(100.0, true, true, true, cfg), "sneakers avoid exhaustion")
	assert_near(stamina.value, 100.0)
	assert_false(stamina.exhausted)

func test_idle_does_not_drain_and_recovery_is_tick_independent() -> void:
	var cfg: Dictionary = DataLib.movement()["stamina"]
	var a := SprintStamina.new()
	var b := SprintStamina.new()
	a.tick(30.0, true, false, false, cfg)
	assert_near(a.value, 100.0)
	a.value = 0.0; b.value = 0.0
	a.rest_time = 0.0
	a.exhausted = true; b.exhausted = true
	for i in 90:
		a.tick(1.0 / 30.0, false, false, false, cfg)
	for i in 432:
		b.tick(1.0 / 144.0, false, false, false, cfg)
	assert_near(a.value, b.value, 0.0001)
	assert_near(a.value, 44.0, 0.0001)
