extends RefCounted
## Pure, seeded circle geometry. Every target is nested and keeps the summit safe.
## Kept independent of scenes/autoloads so tools/ci/test_summit.gd can test it directly.

const EPSILON := 0.0001

static func fits(center: Vector2, radius: float, limit: float) -> bool:
	return absf(center.x) + radius <= limit + EPSILON \
		and absf(center.y) + radius <= limit + EPSILON

static func first(focus: Vector2, radius: float, limit: float,
		sample_radius: float, random: RandomNumberGenerator) -> Vector2:
	# The caller validates that a circle centred on the summit fits the map.
	var scatter := minf(maxf(sample_radius, 0.0), radius * 0.42)
	for attempt in 60:
		var candidate := focus + _disk(random, scatter)
		if fits(candidate, radius, limit):
			return candidate
	return focus

static func next(previous: Vector2, previous_radius: float, focus: Vector2,
		radius: float, limit: float, random: RandomNumberGenerator) -> Vector2:
	var travel := maxf(0.0, previous_radius - radius)
	var previous_distance := previous.distance_to(focus)
	# Random early rotations, but never move the centre farther from the summit.
	var scatter := minf(radius * 0.42, previous_distance)
	for attempt in 60:
		var candidate := focus + _disk(random, scatter)
		if candidate.distance_to(previous) + radius > previous_radius + EPSILON:
			continue
		if fits(candidate, radius, limit):
			return candidate
	# This point is in the previous circle, retains the summit and cannot leave
	# the map. It also handles equal radii and the zero-radius final collapse.
	return previous.move_toward(focus, travel)

static func _disk(random: RandomNumberGenerator, radius: float) -> Vector2:
	var angle := random.randf() * TAU
	var distance := sqrt(random.randf()) * radius
	return Vector2(cos(angle), sin(angle)) * distance
