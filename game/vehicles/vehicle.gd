class_name Vehicle
extends CharacterBody3D
## Arcade kinematic car (docs/game-plan/08): throttle/steer from the driver's CharacterInput,
## follows the terrain (height + slope from the HeightField), slides along buildings and trees,
## takes projectile damage and burns out at 0 HP. Server-authoritative: only the authority
## simulates; the driver character rides the seat and stays shootable.

const KMH := 1.0 / 3.6
const MODELS := {"offroader": "res://assets/kenney/car/suv.glb", "police_car": "res://assets/kenney/car/police.glb",
	"pickup_truck": "res://assets/kenney/car/truck.glb", "atv": "res://assets/kenney/car/sedan.glb"}
const MODEL_SCALE := 1.6

var vehicle_id: String = "offroader"
var def: Dictionary = {}
var world: World
var hp: float = 1000.0
var hp_max: float = 1000.0
var wrecked: bool = false
var driver: Character
var speed: float = 0.0          ## signed, m/s along the car's forward
var steer: float = 0.0          ## -1..1 smoothed
var top_speed: float = 30.0
var accel: float = 8.0
var brake: float = 18.0
var reverse_max: float = 8.0
var turn_rate: float = 1.6      ## rad/s at low speed
var grip: float = 0.8
var model: Node3D
var wheels: Array[Node3D] = []
var wheel_spin: float = 0.0
var seat_offset := Vector3(-0.45, 0.6, 0.0)
var _ground_normal := Vector3.UP
var _burn_t := 0.0

func setup(id: String, p_world: World) -> void:
	vehicle_id = id
	world = p_world
	for v in DataLib.vehicles()["vehicles"]:
		if v["id"] == id:
			def = v
	hp_max = float(def.get("hp", 1000))
	hp = hp_max
	top_speed = float(def.get("topSpeedKmh", 110)) * KMH
	accel = maxf(6.0, (60.0 * KMH) / float(def.get("accel0to60Sec", 6.0)) * 2.6)
	grip = float(def.get("gripDirt", 0.6))
	name = "Vehicle_%s_%d" % [id, get_instance_id() % 10000]
	add_to_group("vehicles")
	collision_layer = 16
	collision_mask = 1 | 16
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.1, 1.3, 4.4)
	cs.shape = bs
	cs.position = Vector3(0, 0.75, 0)
	add_child(cs)
	var path: String = MODELS.get(id, MODELS["offroader"])
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		model = scene.instantiate()
		model.scale = Vector3.ONE * MODEL_SCALE
		add_child(model)
		for n in model.find_children("*", "Node3D", true, false):
			if String(n.name).to_lower().contains("wheel"):
				wheels.append(n)
	set_meta("vehicle", true)

func display_name() -> String:
	return String(def.get("name", vehicle_id))

func occupied() -> bool:
	return driver != null and is_instance_valid(driver)

func can_enter() -> bool:
	return not wrecked and not occupied()

func enter(ch: Character) -> void:
	driver = ch

func exit() -> Vector3:
	driver = null
	speed = 0.0
	# exit point: left of the car, on the ground
	var out := global_transform * Vector3(-1.8, 0.2, 0.0)
	if world:
		out.y = world.height_at(out.x, out.z) + 0.05
	return out

func seat_global() -> Vector3:
	return global_transform * seat_offset

## Called by the driver's Character during its physics step (same tick, deterministic order).
func drive(dt: float, inp: CharacterInput) -> void:
	if wrecked:
		_coast(dt)
		return
	var throttle := clampf(inp.move.y, -1.0, 1.0)
	var want_steer := clampf(-inp.move.x, -1.0, 1.0)
	var handbrake := inp.pressed(CharacterInput.B_JUMP)
	steer = move_toward(steer, want_steer, dt * 4.0)
	if handbrake:
		speed = move_toward(speed, 0.0, brake * 1.4 * dt)
	elif throttle > 0.05:
		if speed < -0.5:
			speed = move_toward(speed, 0.0, brake * dt)
		else:
			speed = move_toward(speed, top_speed * throttle, accel * dt)
	elif throttle < -0.05:
		if speed > 0.5:
			speed = move_toward(speed, 0.0, brake * dt)
		else:
			speed = move_toward(speed, -reverse_max * -throttle, accel * 0.6 * dt)
	else:
		speed = move_toward(speed, 0.0, 3.0 * dt)
	# slope: gravity pulls along the forward axis on hills
	var fwd := -global_transform.basis.z
	speed -= fwd.y * 9.81 * 0.35 * dt
	speed = clampf(speed, -reverse_max, top_speed * 1.1)
	# steering scales down with speed so it doesn't spin at top speed
	var speed_k := clampf(absf(speed) / 6.0, 0.0, 1.0) * (1.0 - 0.55 * clampf(absf(speed) / top_speed, 0.0, 1.0))
	var yaw_rate := steer * turn_rate * speed_k * (1.0 if speed >= 0.0 else -1.0)
	rotate_y(yaw_rate * dt)
	_step(dt)

func _coast(dt: float) -> void:
	speed = move_toward(speed, 0.0, 6.0 * dt)
	_step(dt)

func _step(dt: float) -> void:
	var fwd := -global_transform.basis.z
	var planar := Vector3(fwd.x, 0.0, fwd.z).normalized() * speed
	velocity.x = planar.x
	velocity.z = planar.z
	var ground := world.height_at(global_position.x, global_position.z) if world else 0.0
	var above := global_position.y - ground
	if above > 0.15:
		velocity.y -= 20.0 * dt
	else:
		velocity.y = maxf(velocity.y, 0.0)
		global_position.y = ground
	var before := global_position
	move_and_slide()
	# hitting something solid bleeds speed
	var moved := global_position.distance_to(before)
	var expected := absf(speed) * dt
	if expected > 0.05 and moved < expected * 0.5:
		var loss := (expected - moved) / dt
		if loss > 8.0:
			apply_damage(loss * 4.0, null)
		speed = move_toward(speed, 0.0, absf(loss) * 3.0)
	# follow the slope
	if world:
		var n := world.height_field.normal_at(global_position.x, global_position.z)
		_ground_normal = _ground_normal.lerp(n, minf(1.0, dt * 6.0)).normalized()
		var f := -global_transform.basis.z
		var right := f.cross(_ground_normal).normalized()
		var nf := _ground_normal.cross(right).normalized()
		global_transform.basis = Basis(right, _ground_normal, -nf).orthonormalized()
	wheel_spin += speed * dt / 0.35
	for w in wheels:
		w.rotation.x = wheel_spin

func apply_damage(amount: float, from: Character) -> void:
	if wrecked:
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		_wreck(from)

func _wreck(from: Character) -> void:
	wrecked = true
	hp = 0.0
	if occupied():
		var d := driver
		d.take_plain_damage(100.0, from, "Explosion")
		if d.alive():
			d.leave_vehicle()
	Events.hit_fx.emit(global_position + Vector3(0, 1.0, 0), Vector3.UP, "explosion")
	if model:
		for m in model.find_children("*", "MeshInstance3D", true, false):
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.12, 0.1, 0.09)
			mat.roughness = 0.95
			(m as MeshInstance3D).material_override = mat

func _physics_process(dt: float) -> void:
	if not multiplayer.is_server():
		return
	if not occupied() and absf(speed) > 0.01:
		_coast(dt)
