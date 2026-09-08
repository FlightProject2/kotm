class_name PlayerSoundBank
extends RefCounted
## All supplied recordings are explicit resources so exported builds retain them.
const CUES := {
	"hurt": [preload("res://assets/audio/player/hurt.wav")],
	"punch": [preload("res://assets/audio/player/punch_1.wav"), preload("res://assets/audio/player/punch_2.wav")],
	"step_hard_left": [preload("res://assets/audio/player/step_light_left.wav")],
	"step_hard_right": [preload("res://assets/audio/player/step_hard_right.wav")],
	"step_grass": [preload("res://assets/audio/player/step_grass.wav")],
	"step_wood": [preload("res://assets/audio/player/step_wood.wav")],
	"step_metal": [preload("res://assets/audio/player/step_metal.wav")],
	"step_water": [preload("res://assets/audio/player/step_water_1.wav"), preload("res://assets/audio/player/step_water_2.wav")],
	"step_water_deep": [preload("res://assets/audio/player/step_water_deep.wav")],
	"fence": [preload("res://assets/audio/player/fence_1.wav"), preload("res://assets/audio/player/fence_2.wav")],
	"door_locked": [preload("res://assets/audio/player/door_locked.wav")],
	"death": [preload("res://assets/audio/player/death_1.wav"), preload("res://assets/audio/player/death_2.wav"), preload("res://assets/audio/player/death_3.wav")],
	"cough": [preload("res://assets/audio/player/cough.wav")],
	"cough_heavy": [preload("res://assets/audio/player/cough_heavy.wav")],
	"jump": [preload("res://assets/audio/player/jump.wav")],
	"exertion": [preload("res://assets/audio/player/exertion_1.wav"), preload("res://assets/audio/player/exertion_2.wav")],
}
const PRIORITY := {"death": 4, "hurt": 3, "cough": 2, "cough_heavy": 2, "exertion": 1, "jump": 1}
var rng := RandomNumberGenerator.new()
var _last: Dictionary = {}

func _init() -> void:
	rng.randomize() # Cosmetic RNG is deliberately separate from ballistics/gameplay.

func choose(event: String, character_id: int) -> AudioStream:
	if not CUES.has(event):
		return null
	var choices: Array = CUES[event]
	var key := str(character_id) + ":" + event
	var index := rng.randi_range(0, choices.size() - 1)
	if choices.size() > 1 and index == int(_last.get(key, -1)):
		index = (index + rng.randi_range(1, choices.size() - 1)) % choices.size()
	_last[key] = index
	return choices[index]

static func footstep(surface: String, left: bool) -> String:
	match surface:
		"grass": return "step_grass"
		"wood": return "step_wood"
		"metal": return "step_metal"
		"shallow_water": return "step_water"
		"deep_water": return "step_water_deep"
		_: return "step_hard_left" if left else "step_hard_right"
