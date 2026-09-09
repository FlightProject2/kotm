extends CharacterMotor
const PROFILE = preload("res://tools/godot/actor_profile/metrics.gd")

func _ground_air(dt: float) -> void:
	var inp := c.input
	var f := c.forward()
	var r := c.right()
	var want_crouch := inp.pressed(CharacterInput.B_CROUCH)
	if want_crouch != c.crouching:
		set_crouch(want_crouch)
	var aiming := inp.pressed(CharacterInput.B_AIM)
	var forward_ish: bool = inp.move.y > 0.1 and inp.move.y >= absf(inp.move.x)
	var can_sprint := inp.pressed(CharacterInput.B_SPRINT) and not aiming and not c.crouching and not c.healing_blocks_sprint() and forward_ish
	var speed: float
	if c.stun > 0.0 or c.healing_blocks_movement():
		speed = 0.0
	elif c.crouching:
		speed = float(cfg["crouchSpeed"])
	elif can_sprint:
		speed = float(cfg["sprintSpeed"])
	else:
		speed = float(cfg["walkSpeed"])
	var wish_dir := f * inp.move.y + r * inp.move.x
	var has_wish: bool = wish_dir.length_squared() > 0.0001 and speed > 0.0
	var wish := wish_dir.normalized() * speed if has_wish else Vector3.ZERO
	var on_floor := c.is_on_floor()
	var planar := Vector3(c.velocity.x, 0.0, c.velocity.z)
	if on_floor:
		# Linear, tick-rate independent: full speed in ~0.1 s, stop in ~0.1 s (H1Z1 snappiness).
		var rate: float = float(cfg["groundAccel"]) if has_wish else float(cfg["groundDecel"])
		planar = planar.move_toward(wish, rate * dt)
	elif has_wish:
		# Air: steer a little, never brake, never exceed sprint speed.
		planar = planar.move_toward(wish, float(cfg["airAccel"]) * dt)
		var cap := float(cfg["sprintSpeed"])
		if planar.length_squared() > cap * cap:
			planar = planar.normalized() * cap
	c.velocity.x = planar.x
	c.velocity.z = planar.z
	# Jump with input buffer and coyote time.
	if inp.pressed(CharacterInput.B_JUMP) and not c.prev_input.pressed(CharacterInput.B_JUMP):
		_jump_buffer_t = float(cfg["jumpBufferSec"])
	else:
		_jump_buffer_t = maxf(0.0, _jump_buffer_t - dt)
	_coyote_t = float(cfg["coyoteSec"]) if on_floor else maxf(0.0, _coyote_t - dt)
	if _jump_buffer_t > 0.0 and (on_floor or _coyote_t > 0.0) and c.stun <= 0.0 and c.velocity.y <= 0.5:
		c.velocity.y = float(cfg["jumpVelocity"])
		c.jumped.emit()
		_jump_buffer_t = 0.0
		_coyote_t = 0.0
		if c.crouching:
			set_crouch(false)
		on_floor = false
	if not on_floor:
		c.velocity.y -= float(cfg["gravity"]) * dt
	if _was_on_floor and not on_floor:
		_fall_start_y = c.global_position.y
	_prev_vy = c.velocity.y
	var _clock_motor_move_and_slide := Time.get_ticks_usec()
	c.move_and_slide()
	PROFILE.record("motor.move_and_slide", _clock_motor_move_and_slide)
	_floor_clamp()
	var now_on_floor := c.is_on_floor()
	if now_on_floor and not _was_on_floor:
		_land(_prev_vy)
	_was_on_floor = now_on_floor
	c.mode = Character.Mode.GROUND if now_on_floor else Character.Mode.AIR

func _parachute(dt: float) -> void:
	var inp := c.input
	var f := c.forward()
	var fwd := inp.move.y
	var speed: float
	var descent: float
	if fwd > 0.1:
		speed = float(pcfg["forwardSpeed"]); descent = float(pcfg["forwardDescent"])
	elif fwd < -0.1:
		speed = float(pcfg["flareSpeed"]); descent = float(pcfg["flareDescent"])
	else:
		speed = float(pcfg["neutralSpeed"]); descent = float(pcfg["neutralDescent"])
	var k := minf(1.0, float(pcfg["horizontalLerp"]) * dt)
	var r := c.right()
	var side := inp.move.x * float(pcfg.get("strafeSpeed", 5.0))
	c.velocity.x = lerpf(c.velocity.x, f.x * speed + r.x * side, k)
	c.velocity.z = lerpf(c.velocity.z, f.z * speed + r.z * side, k)
	c.velocity.y = lerpf(c.velocity.y, -descent, minf(1.0, 3.0 * dt))
	var _clock_motor_move_and_slide := Time.get_ticks_usec()
	c.move_and_slide()
	PROFILE.record("motor.move_and_slide", _clock_motor_move_and_slide)
	var ground := c.world.height_at(c.global_position.x, c.global_position.z) if c.world else 0.0
	if c.is_on_floor() or c.global_position.y <= ground + 0.05:
		if c.global_position.y < ground + 0.08:
			c.global_position.y = ground + 0.08
		c.velocity = Vector3.ZERO
		c.mode = Character.Mode.GROUND
		c.stun = float(cfg["landingStunSec"])
		_was_on_floor = true
		c.landed.emit()

func _floor_clamp() -> void:
	var clock := Time.get_ticks_usec()
	super._floor_clamp()
	PROFILE.record("motor.floor_height", clock)
func _clamp_to_map() -> void:
	var clock := Time.get_ticks_usec()
	super._clamp_to_map()
	PROFILE.record("motor.map_clamp", clock)

\r\n