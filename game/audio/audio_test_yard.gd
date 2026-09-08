extends Node3D
## F6 this scene for a playable audio check using the actual character and event hooks.
var character: Character
var camera: CameraRig
var status: Label
var _gas := false
var _gas_tick := 0.0
var _last := "Walk onto a labelled surface."

func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.16, 0.22, 0.29)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var surfaces := ["hard", "grass", "wood", "metal", "shallow_water", "deep_water"]
	var colors := [Color(0.38, 0.4, 0.42), Color(0.23, 0.39, 0.16), Color(0.39, 0.25, 0.14), Color(0.48, 0.57, 0.61), Color(0.17, 0.48, 0.62), Color(0.08, 0.23, 0.42)]
	for i in surfaces.size():
		var x := float(i) * 8.0 - 20.0
		var floor := _box(Vector3(x, -0.25, -4), Vector3(7.8, 0.5, 60), colors[i])
		floor.set_meta("audio_surface", surfaces[i] if i < 4 else "hard")
		_label(surfaces[i].replace("_", " ").to_upper(), Vector3(x, 0.1, 8))
		if i >= 4:
			var water := AudioWaterArea.new()
			water.audio_surface = surfaces[i]
			water.position = Vector3(x, 0.3, -4)
			var collision := CollisionShape3D.new()
			var box := BoxShape3D.new(); box.size = Vector3(7.8, 1.0, 60)
			collision.shape = box
			water.add_child(collision)
			add_child(water)
	# Metal bars have true body collisions, not a proximity trigger.
	for i in 11:
		var bar := _box(Vector3(-6 + float(i) * 0.4, 0.9, -16), Vector3(0.08, 1.8, 0.08), Color(0.4, 0.45, 0.48))
		bar.set_meta("audio_fence", true)
		bar.set_meta("audio_surface", "metal")
	_label("TOUCH THE METAL FENCE", Vector3(-4, 2.3, -16))
	var door := _box(Vector3(4, 1.25, -16), Vector3(1.8, 2.5, 0.16), Color(0.42, 0.26, 0.13))
	door.set_meta("audio_locked_door", true)
	_label("LOCKED DOOR: FACE IT + F", Vector3(4, 2.9, -16))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 20)
	canvas.add_child(panel)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 22)
	panel.add_child(status)
	AudioManager.player_sound_played.connect(_played)
	_spawn()

func _box(pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1 | 32
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new(); box.size = size
	shape.shape = box; body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new(); cube.size = size
	mesh.mesh = cube
	var material := StandardMaterial3D.new(); material.albedo_color = color
	mesh.material_override = material; body.add_child(mesh)
	add_child(body)
	return body

func _label(text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.font_size = 44
	label.pixel_size = 0.009
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)

func _spawn() -> void:
	if is_instance_valid(character):
		remove_child(character)
		character.queue_free()
	if is_instance_valid(camera):
		remove_child(camera)
		camera.queue_free()
	AudioManager.player_pool.reset()
	character = load("res://game/character/character.tscn").instantiate()
	character.character_id = 777
	character.position = Vector3(-20, 0.1, 10)
	add_child(character)
	camera = load("res://game/camera/camera_rig.tscn").instantiate()
	add_child(camera)
	camera.target = character
	var source := PlayerInputSource.new()
	source.character = character
	source.camera_rig = camera
	character.add_child(source)
	Events.local_character_changed.emit(character)
	_gas = false
	_gas_tick = 0.0

func _physics_process(dt: float) -> void:
	if _gas and character.alive():
		_gas_tick += dt
		if _gas_tick >= 1.0:
			_gas_tick -= 1.0
			character.take_plain_damage(1.0, null, "Gas")
	if character.global_position.y < -12:
		_spawn()
	status.text = "  PLAYER AUDIO YARD\n  WASD move | Shift sprint (7 sec → breath) | C crouch | Space jump\n  LMB fists | Mouse look | F locked door | Esc release pointer\n  H hurt | G gas on/off | K death | P respawn\n  HP %.0f | Gas %s | Surface %s\n  %s  " % [character.health.hp, "ON" if _gas else "OFF", character.player_audio.current_surface(), _last]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_H: character.take_plain_damage(5.0, null, "Audio test hit")
			KEY_G: _gas = not _gas
			KEY_K: character.take_plain_damage(1000.0, null, "Audio test death")
			KEY_P: _spawn()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _played(event: String, id: int, path: String, _volume: float) -> void:
	if id == 777:
		_last = event + " → " + path.get_file()
