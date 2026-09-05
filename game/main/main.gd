extends Node
## Entry point: main menu -> match; or headless simulation with --sim (see README).

const WORLD_SCENE := preload("res://game/world/world.tscn")
const CAMERA_SCENE := preload("res://game/camera/camera_rig.tscn")

var args: Dictionary = {}
var world: World
var match_node: Match
var camera_rig: CameraRig
var sim: bool = false
var sim_seconds: float = 60.0
var preset: Dictionary

@onready var menu: Control = $Menus/MainMenu
@onready var status_label: Label = $Menus/MainMenu/Status

func _ready() -> void:
	args = _parse_args(OS.get_cmdline_user_args())
	preset = DataLib.preset(str(args.get("map", "slice_2km")))
	sim = args.has("sim")
	if sim:
		sim_seconds = float(args.get("sim-seconds", 60))
		menu.visible = false
		start_match(int(args.get("seed", 1)), int(args.get("bots", preset["botCount"])), not args.has("no-player"), str(args.get("terrain", "auto")))
	else:
		menu.visible = true
		$Menus/MainMenu/Play.pressed.connect(_on_play)

func _on_play() -> void:
	menu.visible = false
	start_match(randi(), int(preset["botCount"]), true, str(args.get("terrain", "auto")))

func start_match(p_seed: int, bots: int, with_player: bool, terrain_mode: String) -> void:
	world = WORLD_SCENE.instantiate()
	add_child(world)
	world.setup(terrain_mode)
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
		if not sim:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("KOTM: match started seed=%d bots=%d terrain=%s" % [p_seed, bots, world.backend_name])

func _process(_dt: float) -> void:
	if sim and match_node and match_node.match_time >= sim_seconds:
		_print_summary_and_quit()

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
	menu.visible = true
	status_label.text = ("KING OF THE MOUNTAIN" if won else "You placed #%d" % placement) + (" · killed by %s (%s)" % [killer_name, weapon] if not won and killer_name != "" else "")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and match_node and not sim:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

static func _parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else true
	return out
