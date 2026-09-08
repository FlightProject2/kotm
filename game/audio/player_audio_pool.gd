class_name PlayerAudioPool
extends Node
## A bounded pool separate from gunfire: a shot cannot recycle a dying player's voice.
signal played(event: String, character_id: int, resource_path: String, volume: float)
const SIZE := 24
var bank := PlayerSoundBank.new()
var clock := 0.0
var slots: Array[AudioStreamPlayer3D] = []
var _dead_until: Dictionary = {}

func _ready() -> void:
	for i in SIZE:
		var player := AudioStreamPlayer3D.new()
		player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
		player.max_db = 0.0
		player.set_meta("until", 0.0)
		player.set_meta("priority", 0)
		player.set_meta("character_id", -1)
		add_child(player)
		slots.append(player)
	Events.player_sound.connect(play_event)
	Events.match_started.connect(func(_seed: int) -> void: reset())

func _process(dt: float) -> void:
	clock += dt

func reset() -> void:
	_dead_until.clear()
	for player in slots:
		player.stop()
		player.set_meta("until", 0.0)

func play_event(event: String, pos: Vector3, character_id: int, volume: float) -> void:
	if clock < float(_dead_until.get(character_id, 0.0)):
		return
	var priority := int(PlayerSoundBank.PRIORITY.get(event, 0))
	# One voice per character; damage/death may interrupt breathing, never the reverse.
	for player in slots:
		if int(player.get_meta("character_id")) != character_id or float(player.get_meta("until")) <= clock:
			continue
		var current_priority := int(player.get_meta("priority"))
		if priority > 0 and current_priority > 0:
			if current_priority >= priority:
				return
			player.stop()
			player.set_meta("until", 0.0)
		elif event == "death":
			player.stop()
			player.set_meta("until", 0.0)
	var selected: AudioStreamPlayer3D = null
	var oldest := INF
	for player in slots:
		var until := float(player.get_meta("until"))
		if until <= clock:
			selected = player
			break
		if int(player.get_meta("priority")) < priority and until < oldest:
			selected = player
			oldest = until
	if selected == null:
		return
	var stream := bank.choose(event, character_id)
	if stream == null:
		return
	var footstep := event.begins_with("step_")
	selected.stop()
	selected.stream = stream
	selected.global_position = pos
	selected.unit_size = 3.0 if footstep else 4.0
	selected.max_distance = 35.0 if footstep else 50.0
	selected.volume_db = linear_to_db(clampf(volume, 0.01, 1.0))
	selected.pitch_scale = bank.rng.randf_range(0.96, 1.04) if priority == 0 else 1.0
	selected.set_meta("character_id", character_id)
	selected.set_meta("priority", priority)
	selected.set_meta("until", clock + stream.get_length() / selected.pitch_scale)
	if event == "death":
		_dead_until[character_id] = clock + 6.0
	selected.play()
	played.emit(event, character_id, stream.resource_path, volume)
