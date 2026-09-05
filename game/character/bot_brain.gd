class_name BotBrain
extends Node
## Server-side AI producing CharacterInput for a bot. Milestone step 16 fills in the full
## prototype behaviour; for now bots steer their parachute and idle after landing.

var c: Character
var rng: RandomNumberGenerator
var t: float = 0.0

func _ready() -> void:
	c = get_parent() as Character
	if rng == null:
		rng = RandomNumberGenerator.new()

func _physics_process(dt: float) -> void:
	if not multiplayer.is_server() or c == null or not c.alive():
		return
	t += dt
	var i := CharacterInput.new()
	i.yaw = c.yaw
	i.pitch = 0.0
	i.aim_dir = c.forward()
	if c.mode == Character.Mode.PARACHUTE:
		i.move = Vector2(0, 1.0 if t > 3.0 else 0.0)
	c.submit_input(i)
