extends RefCounted
## Profiling resources load only through the explicit actor profile entry point.
static var active := false
static var values: Dictionary = {}

static func record(key: String, start: int) -> void:
	if not active:
		return
	var duration := Time.get_ticks_usec() - start
	if not values.has(key):
		values[key] = [0, 0, 0]
	var value: Array = values[key]
	value[0] += duration
	value[1] += 1
	value[2] = maxi(value[2], duration)

static func reset() -> void:
	values.clear()
	active = true

static func report(frames: int) -> Dictionary:
	active = false
	var result := {}
	for key in values:
		var value: Array = values[key]
		result[key] = {"ms_per_physics_frame": float(value[0]) / frames / 1000.0, "calls_per_frame": float(value[1]) / frames, "mean_call_us": float(value[0]) / maxi(value[1], 1), "max_call_us": value[2]}
	return result
