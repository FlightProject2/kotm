class_name Character
extends CharacterBody3D
## The shared player/bot body. Simulation runs only on the authority (server); the same
## CharacterInput drives it whether it came from a local player, the network, or a bot.

enum Mode { GROUND, AIR, PARACHUTE, LANDING }

signal died(killer: Character, weapon_name: String, headshot: bool)
signal landed
signal fired(recoil_vertical: float, recoil_horizontal: float)

@export var display_name: String = "Player"
var owner_peer_id: int = 1
var is_bot: bool = false
var character_id: int = 0
var world: World

var input: CharacterInput = CharacterInput.new()
var prev_input: CharacterInput = CharacterInput.new()
var yaw: float = 0.0
var pitch: float = 0.0
var mode: int = Mode.GROUND
var crouching: bool = false
var stun: float = 0.0
var health: HealthState = HealthState.new()
var inventory: Inventory = Inventory.new()
var cosmetics: Dictionary = {}
var kills: int = 0
var damage_dealt: float = 0.0
var last_hit_by: Character
var heal_timer: float = 0.0
var heal_pending: Dictionary = {}
var heal_amount: float = 0.0
var heal_rate: float = 0.0
var bleed_timer: float = 0.0
var gas_timer: float = 0.0
var vehicle: Vehicle = null

@onready var motor: CharacterMotor = $Motor
@onready var collision: CollisionShape3D = $Collision
@onready var visual: Node3D = $Visual
@onready var combat: CharacterCombat = $Combat
@onready var interaction: CharacterInteraction = $Interaction

var cfg: Dictionary = DataLib.movement()

func _ready() -> void:
	add_to_group("characters")
	set_collision_layer_value(2, true)
	collision_mask = 1 | 2 | 16

func is_authority() -> bool:
	return multiplayer.is_server()

func is_local() -> bool:
	return not is_bot and owner_peer_id == multiplayer.get_unique_id()

func alive() -> bool:
	return health.alive

func height() -> float:
	return float(cfg["crouchHeight"]) if crouching else float(cfg["standHeight"])

func eye_position() -> Vector3:
	return global_position + Vector3(0, height() - 0.2, 0)

func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))

func right() -> Vector3:
	var f := forward()
	return Vector3(-f.z, 0, f.x)   # facing -Z gives +X, Godot's right

## Local player / bot entry point. On a client this will become an RPC to the server.
func submit_input(i: CharacterInput) -> void:
	if is_authority():
		input = i
	else:
		_rx_input.rpc_id(1, i.pack())

@rpc("any_peer", "call_local", "unreliable_ordered")
func _rx_input(bytes: PackedByteArray) -> void:
	if multiplayer.get_remote_sender_id() != owner_peer_id:
		return
	input = CharacterInput.unpack(bytes)

func _physics_process(dt: float) -> void:
	if not is_authority() or not alive():
		return
	yaw = input.yaw
	pitch = input.pitch
	if vehicle != null and is_instance_valid(vehicle):
		var before := vehicle.global_position
		vehicle.drive(dt, input)
		if is_local():
			Events.local_stat.emit("drive", vehicle.global_position.distance_to(before))
		global_position = vehicle.seat_global()
		velocity = vehicle.velocity
		yaw = input.yaw
	else:
		motor.simulate(dt)
		combat.tick(dt)
	interaction.tick()
	_tick_heal(dt)
	prev_input = input.duplicate_input()

# ---- health helpers (authority) ----
func apply_hit(result: DamageModel.HitResult, from: Character, weapon_name := "") -> void:
	if from:
		var dealt := minf(result.damage, health.hp + result.damage)
		from.damage_dealt += dealt
		last_hit_by = from
		if from.is_local():
			Events.local_stat.emit("damage", dealt)
			if result.headshot:
				Events.local_stat.emit("headshot", 1.0)
	heal_timer = 0.0
	heal_pending = {}
	if result.killed:
		_die(from, weapon_name, result.headshot)

func take_plain_damage(amount: float, from: Character, how: String) -> void:
	if not alive():
		return
	if from:
		from.damage_dealt += minf(amount, health.hp)
		last_hit_by = from
	if health.apply_damage(amount):
		_die(from, how, false)

func in_vehicle() -> bool:
	return vehicle != null and is_instance_valid(vehicle)

func enter_vehicle(v: Vehicle) -> bool:
	if v == null or not v.can_enter() or mode != Mode.GROUND:
		return false
	vehicle = v
	v.enter(self)
	set_collision_layer_value(2, false)   # players layer off: the car's body does the pushing
	collision.disabled = true
	crouching = false
	return true

func leave_vehicle() -> void:
	if not in_vehicle():
		return
	var out := vehicle.exit()
	vehicle = null
	collision.disabled = false
	set_collision_layer_value(2, alive())
	global_position = out
	velocity = Vector3.ZERO
	mode = Mode.GROUND

func _die(killer: Character, how: String, headshot: bool) -> void:
	if in_vehicle():
		var v := vehicle
		vehicle = null
		v.driver = null
	health.alive = false
	set_collision_layer_value(2, false)
	visual.visible = false
	var rig := get_node_or_null("Hitboxes") as HitboxRig
	if rig:
		rig.set_enabled(false)
	Events.hit_fx.emit(global_position + Vector3(0, 1.2, 0), Vector3.UP, "death")
	died.emit(killer, how, headshot)

func start_heal(med_id: String) -> bool:
	if heal_timer > 0.0 or heal_amount > 0.0:
		return false
	for m in DataLib.armor()["medical"]:
		if m["id"] == med_id:
			heal_timer = float(m["useSec"])
			heal_pending = m
			return true
	return false

func _tick_heal(dt: float) -> void:
	if heal_timer > 0.0:
		heal_timer -= dt
		if heal_timer <= 0.0 and not heal_pending.is_empty():
			health.bleeding = false
			heal_amount = float(heal_pending["heal"])
			heal_rate = heal_amount / float(heal_pending["healOverSec"])
			heal_pending = {}
	if heal_amount > 0.0:
		var h := minf(heal_amount, heal_rate * dt)
		health.heal(h)
		heal_amount -= h
	if health.bleeding:
		bleed_timer += dt
		if bleed_timer >= float(DataLib.armor()["bleeding"]["tickSec"]):
			bleed_timer = 0.0
			take_plain_damage(1.0, last_hit_by, "Bleeding")

func show_weapon(id: String, weapon_class: String) -> void:
	if visual and visual.has_method("show_weapon"):
		visual.show_weapon(id, weapon_class)

func current_weapon_scoped() -> bool:
	return combat != null and combat.current_is_scoped()

func healing_blocks_sprint() -> bool:
	return heal_timer > 0.0

func healing_blocks_movement() -> bool:
	return heal_timer > 0.0 and not heal_pending.is_empty() and not bool(heal_pending.get("canWalk", true))
