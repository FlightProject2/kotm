extends TestCase
## Steep ground must be climbable, not a wall. The mountain reaches ~50 degrees, so a player
## walking into it has to gain height instead of wedging against it (floor_max_angle on the body).

## Builds a ramp of [deg] degrees rising toward -Z, its bottom edge at the origin.
func _ramp(deg: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 2, 80)
	cs.shape = bs
	# tilt about X so the surface climbs as z decreases (y = -z * tan a) and drop the box by its
	# half-height along the tilted normal, so the top face passes exactly through the origin
	var a := deg_to_rad(deg)
	var n := Vector3(0, cos(a), sin(a))
	cs.transform = Transform3D(Basis(Vector3.RIGHT, a), -n)
	body.add_child(cs)
	return body

func _climb(deg: float) -> float:
	var ramp := _ramp(deg)
	await add_to_tree(ramp)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.position = Vector3(0, 0.2, 0)
	await add_to_tree(ch)
	await settle(10)
	var y0 := ch.global_position.y
	for i in 180:
		ch.input.move = Vector2(0.0, 1.0)     # forward is -Z at yaw 0
		ch.input.set_button(CharacterInput.B_SPRINT, true)
		await settle(1)
	var gained := ch.global_position.y - y0
	ch.queue_free(); ramp.queue_free()
	await settle(1)
	return gained

func test_walks_up_a_50_degree_slope() -> void:
	var gained := await _climb(50.0)
	print("    climb 50 deg: gained %.2f m in 3 s" % gained)
	assert_true(gained > 1.5, "climbed a 50 degree slope (gained %.2f m)" % gained)

func test_walks_up_a_35_degree_slope() -> void:
	var gained := await _climb(35.0)
	print("    climb 35 deg: gained %.2f m in 3 s" % gained)
	assert_true(gained > 3.0, "climbed a 35 degree slope (gained %.2f m)" % gained)
