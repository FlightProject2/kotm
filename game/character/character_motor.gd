class_name CharacterMotor
extends Node
## Locomotion: ground/air movement, jump, fall damage, parachute descent (docs 02 and 04).
## Constants come from design/data/movement.json. Runs on the authority only.

var c: Character
var cfg: Dictionary
var pcfg: Dictionary
var _prev_vy: float = 0.0
var _was_on_floor: bool = false
var _fall_start_y: float = 0.0
var _jump_buffer_t: float = 0.0
var _coyote_t: float = 0.0

func _ready() -> void:
	c = get_parent() as Character
	cfg = DataLib.movement()
	pcfg = cfg["parachute"]

func simulate(dt: float) -> void:
	c.stun = maxf(0.0, c.stun - dt)
	if c.mode == Character.Mode.PARACHUTE:
		_parachute(dt)
	else:
		_ground_air(dt)
	_clamp_to_map()

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
	c.move_and_slide()
	_floor_clamp()
	var now_on_floor := c.is_on_floor()
	if now_on_floor and not _was_on_floor:
		_land(_prev_vy)
	_was_on_floor = now_on_floor
	c.mode = Character.Mode.GROUND if now_on_floor else Character.Mode.AIR

func _land(vy_before: float) -> void:
	var g := float(cfg["gravity"])
	var speed := -vy_before
	var h := (speed * speed) / (2.0 * g)
	var dmg := DamageModel.fall_damage(h, c.health)
	if dmg > 0.0:
		c.take_plain_damage(dmg, null, "Fall")
	c.landed.emit()

## Terrain is the floor of last resort: never let a body sink below the height field.
func _floor_clamp() -> void:
	if c.world == null:
		return
	var g := c.world.height_at(c.global_position.x, c.global_position.z)
	if c.global_position.y < g - 0.02:
		c.global_position.y = g
		if c.velocity.y < 0.0:
			c.velocity.y = 0.0

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
	c.velocity.x = lerpf(c.velocity.x, f.x * speed, k)
	c.velocity.z = lerpf(c.velocity.z, f.z * speed, k)
	c.velocity.y = -descent
	c.move_and_slide()
	var ground := c.world.height_at(c.global_position.x, c.global_position.z) if c.world else 0.0
	if c.is_on_floor() or c.global_position.y <= ground + 0.05:
		if c.global_position.y < ground:
			c.global_position.y = ground
		c.velocity = Vector3.ZERO
		c.mode = Character.Mode.GROUND
		c.stun = float(cfg["landingStunSec"])
		_was_on_floor = true
		c.landed.emit()

func _clamp_to_map() -> void:
	if c.world == null:
		return
	var half := c.world.half_size() - 2.0
	c.global_position.x = clampf(c.global_position.x, -half, half)
	c.global_position.z = clampf(c.global_position.z, -half, half)

func set_crouch(on: bool) -> void:
	c.crouching = on
	var shape := c.collision.shape as CapsuleShape3D
	var h := c.height()
	shape.height = h
	c.collision.position.y = h * 0.5

## Puts the character in the air under a parachute (match start).
func start_parachute(pos: Vector3, yaw: float) -> void:
	c.global_position = pos
	c.yaw = yaw
	c.velocity = Vector3.ZERO
	c.mode = Character.Mode.PARACHUTE
	_was_on_floor = false
	_jump_buffer_t = 0.0
	_coyote_t = 0.0
	if c.is_inside_tree():
		c.reset_physics_interpolation()
