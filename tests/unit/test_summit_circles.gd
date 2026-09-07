extends TestCase

const PICKER := preload("res://game/match/summit_circle_picker.gd")
const RADII := [700.0, 420.0, 230.0, 130.0, 70.0, 25.0, 0.0]
const LIMIT := 933.0

func _random(value: int) -> RandomNumberGenerator:
	var random := RandomNumberGenerator.new()
	random.seed = value
	return random

func _chain(value: int, focus := Vector2.ZERO) -> Array[Vector2]:
	var random := _random(value)
	var points: Array[Vector2] = [PICKER.first(focus, RADII[0], LIMIT, 630.0, random)]
	for i in range(1, RADII.size()):
		points.append(PICKER.next(points[-1], RADII[i - 1], focus, RADII[i], LIMIT, random))
	return points

func test_seeded_determinism() -> void:
	assert_eq(_chain(2016), _chain(2016))
	assert_false(_chain(7) == _chain(8), "different seeds should retain early rotation variety")

func test_one_thousand_seeds_stay_nested_and_keep_summit() -> void:
	for value in 1000:
		var points := _chain(value)
		for i in points.size():
			assert_true(PICKER.fits(points[i], RADII[i], LIMIT), "map containment, seed %d phase %d" % [value, i])
			assert_true(points[i].length() <= RADII[i] + 0.001, "summit is always safe before collapse")
			if i > 0:
				assert_true(points[i].distance_to(points[i - 1]) + RADII[i] <= RADII[i - 1] + 0.001, "circle containment")
				assert_true(points[i].length() <= points[i - 1].length() + 0.001, "centre never moves away from the summit")
		assert_true(points[-1].is_equal_approx(Vector2.ZERO), "final collapse is exactly at the summit")

func test_offset_summit_and_map_edge_fallback() -> void:
	var focus := Vector2(233.0, -233.0)
	for value in 200:
		var points := _chain(value, focus)
		for i in points.size():
			assert_true(PICKER.fits(points[i], RADII[i], LIMIT))
			assert_true(points[i].distance_to(focus) <= RADII[i] + 0.001)
			if i > 0:
				assert_true(points[i].distance_to(points[i - 1]) + RADII[i] <= RADII[i - 1] + 0.001)
		assert_true(points[-1].is_equal_approx(focus))

func test_equal_radii_do_not_shift_the_zone() -> void:
	var previous := Vector2(50.0, -20.0)
	var next := PICKER.next(previous, 200.0, Vector2.ZERO, 200.0, LIMIT, _random(42))
	assert_true(next.is_equal_approx(previous))

func test_focus_on_previous_boundary_is_retained() -> void:
	var previous := Vector2(100.0, 0.0)
	var next := PICKER.next(previous, 100.0, Vector2.ZERO, 90.0, LIMIT, _random(13))
	assert_true(next.distance_to(previous) + 90.0 <= 100.001)
	assert_true(next.length() <= 90.001)

func test_zero_radius_and_zero_sampling() -> void:
	var focus := Vector2(-30.0, 70.0)
	assert_eq(PICKER.first(focus, 100.0, LIMIT, 0.0, _random(1)), focus)
	assert_eq(PICKER.next(focus, 0.0, focus, 0.0, LIMIT, _random(1)), focus)
