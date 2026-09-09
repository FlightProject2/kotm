extends Character
const PROFILE = preload("res://tools/godot/actor_profile/metrics.gd")

func _physics_process(dt: float) -> void:
	if not is_authority() or not alive():
		return
	var _total_clock := Time.get_ticks_usec()
	yaw = input.yaw
	pitch = input.pitch
	var previous_position := global_position
	if vehicle != null and is_instance_valid(vehicle):
		var before := vehicle.global_position
		vehicle.drive(dt, input)
		if is_local():
			Events.local_stat.emit("drive", vehicle.global_position.distance_to(before))
		global_position = vehicle.seat_global()
		velocity = vehicle.velocity
		yaw = input.yaw
	else:
		var _clock_physics_motor := Time.get_ticks_usec()
		motor.simulate(dt)
		PROFILE.record("physics.motor", _clock_physics_motor)
		var _clock_physics_combat := Time.get_ticks_usec()
		combat.tick(dt)
		PROFILE.record("physics.combat", _clock_physics_combat)
	var _clock_physics_interaction := Time.get_ticks_usec()
	interaction.tick()
	PROFILE.record("physics.interaction", _clock_physics_interaction)
	var _clock_physics_heal := Time.get_ticks_usec()
	_tick_heal(dt)
	PROFILE.record("physics.heal", _clock_physics_heal)
	var _clock_physics_audio := Time.get_ticks_usec()
	player_audio.tick(dt, previous_position)
	PROFILE.record("physics.audio", _clock_physics_audio)
	var _clock_physics_input_copy := Time.get_ticks_usec()
	prev_input = input.duplicate_input()
	PROFILE.record("physics.input_copy", _clock_physics_input_copy)

# ---- health helpers (authority) ----
	PROFILE.record("physics.character_total", _total_clock)

func _ready() -> void:
	super._ready()
	player_audio.set_script(preload("res://tools/godot/actor_profile/audio.gd"))
	player_audio.c = self
