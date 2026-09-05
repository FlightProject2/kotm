extends Node
## Plays placeholder sound effects from the Events bus (docs/game-plan/14). Positional sounds use
## AudioStreamPlayer3D pooled players; local-only cues (hitmarkers, kills, UI) are 2D.

const SFX_DIR := "res://assets/generated/sfx/"
const POOL_SIZE := 24
const RANGES := {"rifle": 1000.0, "sniper": 1200.0, "shotgun": 700.0, "smg": 600.0, "pistol": 500.0}

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _ui: AudioStreamPlayer
var listener_pos: Vector3 = Vector3.ZERO
var local_character_id: int = -1

func _ready() -> void:
	_ui = AudioStreamPlayer.new()
	_ui.bus = "Master"
	add_child(_ui)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		p.unit_size = 14.0
		p.max_db = 3.0
		add_child(p)
		_pool.append(p)
	Events.gunshot.connect(_on_gunshot)
	Events.hit_fx.connect(_on_hit_fx)
	Events.helmet_pop.connect(func(pos: Vector3, _id: String) -> void: play_at("helmet_pop", pos, 1.0))
	Events.hit_confirmed.connect(_on_hit_confirmed)
	Events.popup.connect(func(title: String, _s: String) -> void: if title == "": play_ui("pickup", -6.0))
	Events.toast.connect(func(_t: String) -> void: play_ui("zone_warning", -10.0))
	Events.local_character_changed.connect(func(ch: Node) -> void: local_character_id = ch.get("character_id") if ch else -1)
	_apply_volume()

func _apply_volume() -> void:
	var vol: float = Settings.master_volume if Settings else 0.8
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(vol, 0.0, 1.0)))

func stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var path := SFX_DIR + name + ".wav"
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
	return _streams[name]

func play_at(name: String, pos: Vector3, volume := 1.0, pitch_jitter := 0.06) -> void:
	var s := stream(name)
	if s == null:
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % POOL_SIZE
	p.stream = s
	p.global_position = pos
	p.volume_db = linear_to_db(clampf(volume, 0.01, 1.5))
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()

func play_ui(name: String, volume_db := 0.0) -> void:
	var s := stream(name)
	if s == null:
		return
	_ui.stream = s
	_ui.volume_db = volume_db
	_ui.play()

func _on_gunshot(pos: Vector3, weapon_id: String, shooter_id: int) -> void:
	var def := ItemCatalog.weapon_def(weapon_id)
	var cls: String = def.get("class", "rifle")
	var name := "shot_rifle"
	match cls:
		"sniper": name = "shot_sniper"
		"shotgun": name = "shot_shotgun"
		"smg": name = "shot_smg"
		"pistol": name = "shot_pistol"
		"bow": name = "crack"
	if weapon_id == "ak47":
		name = "shot_rifle_heavy"
	var d := pos.distance_to(listener_pos)
	if shooter_id == local_character_id:
		play_ui(name, -2.0)
	elif d > 90.0:
		play_at("shot_distant", pos, clampf(1.0 - d / RANGES.get(cls, 800.0), 0.0, 1.0))
	else:
		play_at(name, pos, 1.0)

func _on_hit_fx(pos: Vector3, _n: Vector3, kind: String) -> void:
	match kind:
		"flesh": play_at("hit_flesh", pos, 0.8)
		"armor": play_at("hit_armor", pos, 0.8)
		"helmet": play_at("helmet_ding", pos, 1.0, 0.03)
		"death": play_at("death_grunt", pos, 1.0, 0.08)
		_: play_at("crack", pos, 0.25, 0.2)

func _on_hit_confirmed(kind: String, killed: bool) -> void:
	if killed:
		play_ui("kill", -4.0)
		return
	match kind:
		"armor", "armor_break": play_ui("hit_armor", -8.0)
		"helmet_pop", "helmet": play_ui("helmet_ding", -4.0)
		_: play_ui("hit_flesh", -8.0)

func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		listener_pos = cam.global_position
