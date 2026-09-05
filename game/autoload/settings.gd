extends Node
## Player-local settings. Persisted to user://settings.cfg.

var mouse_sensitivity: float = 0.0022
var invert_y: bool = false
var first_person_default: bool = false
var master_volume: float = 0.8
var cosmetics: Dictionary = {}

const PATH := "user://settings.cfg"

func _ready() -> void:
	cosmetics = SkinSystem.default_loadout()
	load_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("input", "invert_y", invert_y)
	first_person_default = cfg.get_value("camera", "first_person_default", first_person_default)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	cosmetics = cfg.get_value("cosmetics", "loadout", cosmetics)
	if cosmetics.is_empty():
		cosmetics = SkinSystem.default_loadout()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("camera", "first_person_default", first_person_default)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("cosmetics", "loadout", cosmetics)
	cfg.save(PATH)
