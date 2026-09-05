extends Node3D
## Flat test map: spawns a local player with a camera rig. Run with F6 in the editor.

const CHARACTER := preload("res://game/character/character.tscn")
const CAMERA := preload("res://game/camera/camera_rig.tscn")

func _ready() -> void:
	var ch: Character = CHARACTER.instantiate()
	ch.display_name = "You"
	ch.position = Vector3(0, 1.0, 0)
	add_child(ch)
	var rig: CameraRig = CAMERA.instantiate()
	add_child(rig)
	rig.target = ch
	var src := PlayerInputSource.new()
	src.character = ch
	src.camera_rig = rig
	ch.add_child(src)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
