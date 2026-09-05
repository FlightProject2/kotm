extends Node
## Entry point: menus -> match -> end screen -> menus; or headless simulation with --sim (README).

const WORLD_SCENE := preload("res://game/world/world.tscn")
const CAMERA_SCENE := preload("res://game/camera/camera_rig.tscn")
const HUD_SCRIPT := preload("res://game/ui/hud.gd")
const MENUS_SCRIPT := preload("res://game/ui/menus.gd")

var args: Dictionary = {}
var world: World
var match_node: Match
var camera_rig: CameraRig
var hud: HUD
var menus: Menus
var sim: bool = false
var sim_seconds: float = 60.0
var preset: Dictionary
var paused: bool = false
var in_match: bool = false
var _debug_t: float = 0.0

func _ready() -> void:
	args = _parse_args(OS.get_cmdline_user_args())
	preset = DataLib.preset(str(args.get("map", "slice_2km")))
	sim = args.has("sim")
	if sim:
		sim_seconds = float(args.get("sim-seconds", 60))
		start_match(int(args.get("seed", 1)), int(args.get("bots", preset["botCount"])), not args.has("no-player"), str(args.get("terrain", "auto")))
		return
	menus = MENUS_SCRIPT.new()
	menus.name = "Menus"
	add_child(menus)
	menus.play_pressed.connect(_on_play)
	menus.resume_pressed.connect(func() -> void: _set_paused(false))
	menus.quit_to_menu_pressed.connect(_quit_to_menu)
	menus.quit_game_pressed.connect(func() -> void: get_tree().quit())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_play() -> void:
	if in_match:
		_end_match()
	menus.hide_all()
	# the single-threaded web build gets fewer bots so the frame stays under budget
	var bots := mini(int(preset["botCount"]), 20) if OS.has_feature("web") else int(preset["botCount"])
	start_match(randi(), bots, true, str(args.get("terrain", "auto")))

func start_match(p_seed: int, bots: int, with_player: bool, terrain_mode: String) -> void:
	world = WORLD_SCENE.instantiate()
	add_child(world)
	world.setup(terrain_mode, null, true)
	match_node = Match.new()
	match_node.name = "Match"
	add_child(match_node)
	match_node.ended.connect(_on_match_ended)
	match_node.start(p_seed, world, preset, bots, with_player)
	if with_player and match_node.local_player:
		camera_rig = CAMERA_SCENE.instantiate()
		add_child(camera_rig)
		camera_rig.target = match_node.local_player
		var src := PlayerInputSource.new()
		src.name = "Input"
		src.character = match_node.local_player
		src.camera_rig = camera_rig
		match_node.local_player.add_child(src)
		Events.local_character_changed.emit(match_node.local_player)
		hud = HUD_SCRIPT.new()
		hud.name = "HUD"
		add_child(hud)
		hud.bind(match_node, camera_rig, world)
		if not sim:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			hud.show_banner("Parachute in. Click in the game to lock the mouse; Esc pauses.")
	in_match = true
	paused = false
	print("KOTM: match started seed=%d bots=%d terrain=%s" % [p_seed, bots, world.backend_name])

## Tears the current match down (world, match, camera, HUD) so a new one can start clean.
func _end_match() -> void:
	in_match = false
	paused = false
	for n in [hud, camera_rig, match_node, world]:
		if n and is_instance_valid(n):
			n.queue_free()
	hud = null; camera_rig = null; match_node = null; world = null

func _quit_to_menu() -> void:
	_end_match()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.main_status.text = ""
	menus.show_screen("main")

func _process(dt: float) -> void:
	if sim and match_node and match_node.match_time >= sim_seconds:
		_print_summary_and_quit()
	elif not sim:
		_process_debug(dt)

func _print_summary_and_quit() -> void:
	var s := match_node.summary()
	s["terrain"] = world.backend_name
	print("SIM_SUMMARY " + JSON.stringify(s))
	get_tree().quit(0)

func _on_match_ended(won: bool, placement: int, killer_name: String, weapon: String, headshot: bool) -> void:
	print("KOTM: match ended won=%s placement=%d killer=%s" % [won, placement, killer_name])
	if sim:
		_print_summary_and_quit()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var src := match_node.local_player.get_node_or_null("Input") if match_node and match_node.local_player else null
	if src:
		src.enabled = false
	if camera_rig:
		camera_rig.look_enabled = false
	var p := match_node.local_player if match_node else null
	var stats := {
		"kills": p.kills if p else 0, "damage": p.damage_dealt if p else 0.0,
		"time": match_node.match_time if match_node else 0.0, "players": match_node.characters.size() if match_node else 0,
	}
	menus.show_end(won, placement, killer_name, weapon, headshot, stats)

func _unhandled_input(event: InputEvent) -> void:
	if match_node == null or sim or match_node.is_over:
		return
	if event.is_action_pressed("pause"):
		if paused and menus.current == "settings":
			menus.show_screen("pause")
		else:
			_set_paused(not paused)
	elif event is InputEventMouseButton and event.pressed and not paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# Browsers only grant pointer lock from a click inside the canvas.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _set_paused(on: bool) -> void:
	paused = on
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	var src := match_node.local_player.get_node_or_null("Input") if match_node and match_node.local_player else null
	if src:
		src.enabled = not on
	if camera_rig:
		camera_rig.look_enabled = not on
	if on:
		menus.show_screen("pause")
	else:
		menus.hide_all()

func _process_debug(dt: float) -> void:
	_debug_t += dt
	if _debug_t >= 5.0 and match_node and match_node.local_player and OS.has_feature("web"):
		_debug_t = 0.0
		var p := match_node.local_player
		print("KOTM: player pos=%s yaw=%.2f mode=%d mouse_mode=%d hp=%.0f fps=%d vel=%s floor=%s" % [p.global_position.round(), p.yaw, p.mode, Input.mouse_mode, p.health.hp, Engine.get_frames_per_second(), p.velocity.round(), p.is_on_floor()])
		var tv := world.find_child("Chunk_8_8", true, false) if world else null
		if tv:
			print("KOTM: terrain chunk visible=%s in_tree=%s aabb=%s mat=%s" % [tv.visible, tv.is_visible_in_tree(), tv.get_aabb(), tv.material_override])

static func _parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out
