class_name Match
extends Node
## Authority-side match flow: seeded spawn, characters, alive count, kill feed, win/lose.

signal ended(won: bool, placement: int, killer_name: String, weapon: String, headshot: bool)

const CHARACTER_SCENE := preload("res://game/character/character.tscn")
const NAMES := ["briocheen", "SUP3R", "EASYKILL7", "heav6n", "keverdeen", "Ninja_Turtle", "xXStormXx", "Pleasant_Val",
	"Bumjick", "Ranchito", "TacHelmetTom", "DriftKing", "ShotgunSally", "Machete_Mike", "LamArmorLarry", "Cranberry",
	"Zimms", "ATV_Andy", "PoliceCarPete", "WoodlandWill", "HotShot", "Skullz", "TopTen", "Royalty", "Frag_Out",
	"GasCan", "BoltAction", "TwoTap", "HeadPop", "Kingslayer"]

var world: World
var preset: Dictionary
var match_seed: int = 1
var characters: Array[Character] = []
var local_player: Character
var alive_count: int = 0
var match_time: float = 0.0
var started: bool = false
var is_over: bool = false
var kills_total: int = 0
var shots_total: int = 0
var landed_count: int = 0
var loot_count: int = 0
var loot_stats: Dictionary = {}
var zone: Zone
var rng_spawn := RandomNumberGenerator.new()
var rng_loot := RandomNumberGenerator.new()
var rng_zone := RandomNumberGenerator.new()
var rng_bots := RandomNumberGenerator.new()
var _next_id: int = 1

func start(p_seed: int, p_world: World, p_preset: Dictionary, bot_count: int, with_player: bool) -> void:
	assert(multiplayer.is_server())
	world = p_world
	preset = p_preset
	match_seed = p_seed
	rng_spawn.seed = p_seed
	rng_loot.seed = p_seed + 1
	rng_zone.seed = p_seed + 2
	rng_bots.seed = p_seed + 3
	loot_stats = LootSpawner.generate(world, world.loot_registry, rng_loot, preset)
	loot_count = int(loot_stats["total"])
	var total := bot_count + (1 if with_player else 0)
	var spawns: Array = SpawnSelector.pick(total, world.height_field, preset, rng_spawn)
	var i := 0
	if with_player:
		local_player = _spawn_character("You", false, spawns[i], rng_spawn.randf() * TAU, multiplayer.get_unique_id())
		i += 1
	for b in bot_count:
		var bot_name: String = NAMES[b % NAMES.size()] + ("" if b < NAMES.size() else str(b))
		_spawn_character(bot_name, true, spawns[i], rng_spawn.randf() * TAU, 0)
		i += 1
	alive_count = characters.size()
	zone = Zone.new()
	zone.name = "Zone"
	world.zone_root.add_child(zone)
	zone.start(preset["zone"], float(preset["mapHalfSizeM"]), float(preset["borderMarginM"]), rng_zone, alive_characters, world.height_at)
	started = true
	Events.match_started.emit(match_seed)
	Events.remain_changed.emit(alive_count)
	Events.banner.emit("Parachute in. Everyone spawns at a random point.")

func _spawn_character(display_name: String, is_bot: bool, pos: Vector3, yaw: float, peer_id: int) -> Character:
	var ch: Character = CHARACTER_SCENE.instantiate()
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
		var brain := BotBrain.new()
		brain.name = "Brain"
		brain.rng = rng_bots
		ch.add_child(brain)
	characters.append(ch)
	return ch

func _process(dt: float) -> void:
	if started and not is_over:
		match_time += dt

func _on_character_died(killer: Character, how: String, headshot: bool, victim: Character) -> void:
	alive_count -= 1
	CharacterInteraction.drop_bag(victim, world.loot_registry)
	if killer:
		killer.kills += 1
		if killer.is_local():
			Events.local_stat.emit("kill", 1.0)
		kills_total += 1
	var killer_name := killer.display_name if killer else "The gas"
	Events.kill_feed.emit(killer_name, victim.display_name, how, headshot)
	Events.remain_changed.emit(alive_count)
	for t in preset["zone"].get("remainingToasts", []):
		if alive_count == int(t):
			Events.toast.emit("%d players remaining" % alive_count)
	if killer and killer == local_player:
		Events.popup.emit(victim.display_name, "KILLER · +100 XP")
		Events.hit_confirmed.emit("kill", true)
	if victim == local_player:
		_finish(false, alive_count + 1, killer_name, how, headshot)
	elif local_player != null and local_player.alive() and alive_count == 1:
		_finish(true, 1, "", "", false)
	elif local_player == null and alive_count <= 1:
		_finish(false, alive_count, "", "", false)

func _finish(won: bool, placement: int, killer_name: String, how: String, headshot: bool) -> void:
	if is_over:
		return
	is_over = true
	Events.match_ended.emit(won, placement, killer_name, how, headshot)
	ended.emit(won, placement, killer_name, how, headshot)

func alive_characters() -> Array[Character]:
	var out: Array[Character] = []
	for c in characters:
		if c.alive():
			out.append(c)
	return out

func summary() -> Dictionary:
	return {"ok": true, "seed": match_seed, "time": snappedf(match_time, 0.1), "alive": alive_count,
		"landed": landed_count, "kills": kills_total, "shots": ProjectileSystem.instance.shots_fired if ProjectileSystem.instance else 0,
		"loot": loot_stats, "loot_left": world.loot_registry.count(), "zone_phase": zone.phase if zone else -1, "zone_state": zone.state if zone else ""}
