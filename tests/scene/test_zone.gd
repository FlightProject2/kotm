extends TestCase

func _zone() -> Zone:
	var z := Zone.new()
	await add_to_tree(z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	z.start(DataLib.preset("slice_2km")["zone"], 1000.0, 67.0, rng, func() -> Array: return [], func(_x: float, _z: float) -> float: return 0.0)
	z.set_process(false)   # drive advance() by hand
	return z

func test_timeline_and_containment() -> void:
	var z: Zone = await _zone()
	var sched: Dictionary = DataLib.preset("slice_2km")["zone"]
	for i in int(sched["revealBannerAtSec"] * 10) - 1:
		z.advance(0.1)
	assert_eq(z.state, "wait")
	z.advance(0.2)
	assert_eq(z.state, "reveal")
	while z.state == "reveal":
		z.advance(0.1)
	assert_eq(z.phase, 0)
	assert_eq(z.state, "warn")
	var first_r: float = z.next_radius
	assert_near(first_r, float(sched["phases"][0]["radiusM"]))
	assert_true(absf(z.next_center.x) + first_r <= 1000.0 - 67.0, "first circle fits the map")
	var prev_c := z.next_center
	var prev_r := first_r
	var phases_seen := 1
	var guard := 0
	while z.state != "done" and guard < 100000:
		guard += 1
		var before_phase := z.phase
		z.advance(0.1)
		if z.phase != before_phase:
			phases_seen += 1
			var d := z.next_center.distance_to(prev_c)
			assert_true(d + z.next_radius <= prev_r + 0.01, "phase %d circle inside the previous (d %.1f r %.1f prev %.1f)" % [z.phase, d, z.next_radius, prev_r])
			assert_true(z.next_radius < prev_r, "radius shrinks")
			prev_c = z.next_center
			prev_r = z.next_radius
	assert_eq(z.state, "done")
	assert_eq(phases_seen, sched["phases"].size())
	assert_near(z.radius, 0.0, 0.01, "gas fully closed")
	assert_near(z.dps, float(sched["phases"][-1]["dps"]))
	var total := z.time
	assert_between(total, 250.0, 420.0, "compressed match length ~5-7 min (%.0f s)" % total)
	z.queue_free()
	await settle(1)

func test_gas_damage_only_outside() -> void:
	var z: Zone = await _zone()
	var scene: PackedScene = load("res://game/character/character.tscn")
	var a: Character = scene.instantiate()
	var b: Character = scene.instantiate()
	tree.root.add_child(a); tree.root.add_child(b)
	a.set_physics_process(false); b.set_physics_process(false)
	var inside := a.health
	var outside := b.health
	var chars: Array = [a, b]
	z._get_characters = func() -> Array: return chars
	z.phase = 0
	z.state = "close"
	z.center = Vector2.ZERO
	z.radius = 100.0
	z.dps = 2.0
	a.global_position = Vector3(10, 0, 10)
	b.global_position = Vector3(300, 0, 0)
	for i in 31:
		z._damage_tick(0.1)
	assert_near(inside.hp, 100.0, 0.001, "inside the circle takes nothing")
	assert_near(outside.hp, 100.0 - 3 * 2.0, 0.001, "3 ticks of 2 dps outside")
	a.queue_free(); b.queue_free(); z.queue_free()
	await settle(1)
