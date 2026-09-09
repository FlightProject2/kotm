extends Match
const PROFILE = preload("res://tools/godot/actor_profile/metrics.gd")

func _spawn_character(display_name: String, is_bot: bool, pos: Vector3, yaw: float, peer_id: int) -> Character:
	var ch: Character = CHARACTER_SCENE.instantiate()
	ch.set_script(preload("res://tools/godot/actor_profile/character.gd"))
	ch.get_node("Motor").set_script(preload("res://tools/godot/actor_profile/motor.gd"))
	ch.get_node("Visual").set_script(preload("res://tools/godot/actor_profile/visual.gd"))
	ch.get_node("Hitboxes").set_script(preload("res://tools/godot/actor_profile/hitbox.gd"))
	ch.display_name = display_name
	ch.is_bot = is_bot
	ch.owner_peer_id = peer_id
	ch.character_id = _next_id
	_next_id += 1
	ch.world = world
	ch.cosmetics = SkinSystem.random_loadout(rng_bots) if is_bot else Settings.cosmetics.duplicate(true)
	ch.name = "C%03d_%s" % [ch.character_id, display_name.validate_node_name()]
	world.characters.add_child(ch)
	ch.motor.start_parachute(pos, yaw)
	ch.input.yaw = yaw
	ch.died.connect(_on_character_died.bind(ch))
	ch.landed.connect(func() -> void: landed_count += 1, CONNECT_ONE_SHOT)
	if is_bot:
		var brain := preload("res://tools/godot/actor_profile/brain.gd").new()
		brain.name = "Brain"
		brain.rng = rng_bots
		ch.add_child(brain)
	characters.append(ch)
	return ch

## Admin/testing: drop [count] bots already on the ground around [centre].
