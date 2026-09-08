extends TestCase

func _spawn() -> Character:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.character_id = 8201
	tree.root.add_child(ch)
	ch.set_physics_process(false)
	ch.inventory.give_weapon("ar15")
	ch.inventory.give_ammo("223", 90)
	ch.set_meta("spread_override", 0.0)
	return ch

func _step(ch: Character, dt: float, fire := false, reload_button := false, slot := -1) -> void:
	ch.prev_input = ch.input
	ch.input = CharacterInput.new()
	ch.input.aim_dir = Vector3.FORWARD
	ch.input.slot = slot
	ch.input.set_button(CharacterInput.B_FIRE, fire)
	ch.input.set_button(CharacterInput.B_RELOAD, reload_button)
	ch.combat.tick(dt)

func test_early_click_is_retained_but_holding_is_not_automatic() -> void:
	var ch := _spawn()
	_step(ch, 0.01, true)
	assert_eq(ch.combat.shot_counter, 1)
	_step(ch, 0.04, false)
	_step(ch, 0.04, true) # 80 ms after the first shot: still inside the 100 ms gate.
	assert_eq(ch.combat.shot_counter, 1, "cadence gate remains authoritative")
	_step(ch, 0.02, false)
	assert_eq(ch.combat.shot_counter, 2, "released early click fires when the gate opens")
	_step(ch, 0.11, true)
	for i in 30:
		_step(ch, 1.0 / 60.0, true)
	assert_eq(ch.combat.shot_counter, 3, "one press stays one shot while held")
	assert_eq(ch.inventory.mags["ar15"], 27)
	ch.queue_free()
	await settle(1)

func test_reload_and_swap_cancel_queued_clicks() -> void:
	var ch := _spawn()
	_step(ch, 0.01, true)
	_step(ch, 0.02, false)
	_step(ch, 0.02, true)
	_step(ch, 0.01, false, true)
	_step(ch, 3.0)
	assert_eq(ch.combat.shot_counter, 1, "no delayed discharge after reload")
	_step(ch, 0.01, true)
	_step(ch, 0.02)
	_step(ch, 0.02, true)
	_step(ch, 0.01, false, false, 0)
	_step(ch, 1.0, false, false, 1)
	_step(ch, 1.0)
	assert_eq(ch.combat.shot_counter, 2, "no queued discharge after switching back")
	ch.queue_free()
	await settle(1)

func test_ar_taps_at_six_tick_intervals_and_level_shot() -> void:
	var ch := _spawn()
	var ps := ProjectileSystem.new()
	tree.root.add_child(ps)
	ps.set_physics_process(false)
	for i in 60:
		_step(ch, 1.0 / 60.0, i % 6 == 0)
	assert_eq(ch.combat.shot_counter, 10, "600 RPM cap accepts ten distinct presses per second")
	assert_eq(ps.projectiles.size(), 10)
	for p in ps.projectiles:
		assert_near(p.vel.y, 0.0, 0.000001, "level crosshair launches horizontally")
		assert_true(p.vel.normalized().dot(Vector3.FORWARD) > 0.9999)
	ps.queue_free()
	ch.queue_free()
	await settle(1)

func test_recoil_recovers_without_moving_mouse_aim_and_is_fps_independent() -> void:
	var a := CameraRig.new()
	var b := CameraRig.new()
	a.pitch = 0.15
	a.yaw = -0.3
	b.pitch = a.pitch
	b.yaw = a.yaw
	a.kick(0.55, 0.18)
	b.kick(0.55, 0.18)
	assert_true(a.view_pitch() > a.pitch, "shot gives immediate visible feedback")
	for i in 30:
		a._recover_recoil(1.0 / 30.0)
	for i in 144:
		b._recover_recoil(1.0 / 144.0)
	assert_near(a.pitch, 0.15, 0.000001, "recoil never permanently changes the aim pitch")
	assert_near(a.yaw, -0.3, 0.000001)
	assert_near(a.view_pitch(), a.pitch, 0.000001)
	assert_near(a.recoil_pitch, b.recoil_pitch, 0.000001)
	assert_near(a.recoil_yaw, b.recoil_yaw, 0.000001)
	a.free()
	b.free()
