extends TestCase
## Enter a parked car, drive forward, exit beside it; wrecks stop taking a driver.

func test_drive_and_exit() -> void:
	var fl := StaticBody3D.new(); fl.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(400, 1, 400); cs.shape = bs; fl.add_child(cs); fl.position.y = -0.5
	await add_to_tree(fl)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.position = Vector3(0, 0.05, 0)
	await add_to_tree(ch)
	var veh := Vehicle.new()
	tree.root.add_child(veh)
	veh.setup("offroader", null)
	veh.global_position = Vector3(2.0, 0.0, 0.0)
	await settle(5)
	assert_true(veh.def.get("name", "") == "Off-Roader", "vehicle def loaded")
	var inp := CharacterInput.new()
	inp.set_button(CharacterInput.B_INTERACT, true)
	ch.submit_input(inp)
	await settle(1)
	assert_true(ch.in_vehicle(), "entered the car with F")
	assert_true(veh.occupied())
	var drive := CharacterInput.new()
	drive.move = Vector2(0, 1)
	var start := veh.global_position
	for i in 120:
		ch.submit_input(drive)
		await settle(1)
	var moved := veh.global_position.distance_to(start)
	assert_true(moved > 8.0, "drove forward (%.1f m in 2 s)" % moved)
	assert_true(veh.speed > 5.0, "gained speed (%.1f m/s)" % veh.speed)
	assert_true(ch.global_position.distance_to(veh.seat_global()) < 0.05, "driver rides the seat")
	var turn := CharacterInput.new()
	turn.move = Vector2(1, 1)
	var yaw0 := veh.rotation.y
	for i in 30:
		ch.submit_input(turn)
		await settle(1)
	assert_true(absf(wrapf(veh.rotation.y - yaw0, -PI, PI)) > 0.15, "steering turns the car")
	var idle := CharacterInput.new()
	ch.submit_input(idle)
	await settle(1)
	var exit := CharacterInput.new()
	exit.set_button(CharacterInput.B_INTERACT, true)
	ch.submit_input(exit)
	await settle(2)
	assert_false(ch.in_vehicle(), "left the car")
	assert_true(ch.global_position.distance_to(veh.global_position) < 3.5, "exited beside the car")
	veh.apply_damage(99999.0, null)
	assert_true(veh.wrecked and not veh.can_enter(), "wreck cannot be entered")
	ch.queue_free(); veh.queue_free(); fl.queue_free()
	await settle(1)
