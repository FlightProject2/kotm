class_name AudioWaterArea
extends Area3D
## Audio-only water volume: add a CollisionShape3D; does not change movement or enable swimming.
@export_enum("shallow_water", "deep_water") var audio_surface := "shallow_water"

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	body_entered.connect(_entered)
	body_exited.connect(_exited)

func _entered(body: Node3D) -> void:
	if body is Character and body.player_audio:
		body.player_audio.water_enter(self, audio_surface)

func _exited(body: Node3D) -> void:
	if body is Character and body.player_audio:
		body.player_audio.water_exit(self)

func _exit_tree() -> void:
	for body in get_overlapping_bodies():
		_exited(body)
