extends Node3D
## Playable integration yard: two real vehicles and Characters, with quick driver selection.

const CHARACTER := preload("res://game/character/character.tscn")
const CAMERA := preload("res://game/camera/camera_rig.tscn")
const PARKING := [Vector3(-4.2, 0.05, 0), Vector3(4.2, 0.05, 0)]
const LABELS := ["SNOW TRUCK", "SNOW MOBILE UTV"]
var vehicles: Array[Vehicle] = []
var drivers: Array[Character] = []
var camera_rig: CameraRig
var inspection_camera: Camera3D
var input_source: PlayerInputSource
var status: Label
var selected := 0
var inspecting := false

func _ready() -> void:
	_build_yard()
	for i in 2:
		var vehicle := Vehicle.new()
		add_child(vehicle)
		vehicle.setup("pickup_truck" if i == 0 else "atv", null)
		vehicle.position = PARKING[i]
		vehicles.append(vehicle)
		var driver: Character = CHARACTER.instantiate()
		driver.name = "TruckDriver" if i == 0 else "UTVDriver"
		driver.display_name = LABELS[i] + " test driver"
		driver.owner_peer_id = multiplayer.get_unique_id() if i == selected else 0
		driver.god_mode = true
		driver.cosmetics = SkinSystem.default_loadout()
		add_child(driver)
		drivers.append(driver)
		driver.enter_vehicle(vehicle)
		var label := Label3D.new()
		label.text = "F%d  /  %s" % [i + 1, LABELS[i]]
		label.position = PARKING[i] + Vector3(0, 0.04, 4.6)
		label.rotation_degrees.x = -90
		label.font_size = 60
		label.pixel_size = 0.008
		label.modulate = Color("344755")
		add_child(label)
	input_source = PlayerInputSource.new()
	add_child(input_source)
	camera_rig = CAMERA.instantiate()
	add_child(camera_rig)
	input_source.camera_rig = camera_rig
	camera_rig.first_person = false
	inspection_camera = Camera3D.new()
	inspection_camera.fov = 45
	add_child(inspection_camera)
	_select(0)
	_build_overlay()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_yard() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("b6cede")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d6e9ff")
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)
	var floor := StaticBody3D.new()
	floor.name = "SnowGround"
	floor.collision_layer = 1
	floor.position.y = -0.5
	add_child(floor)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(240, 1, 240)
	shape.shape = box
	floor.add_child(shape)
	var mesh := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = box.size
	mesh.mesh = slab
	var snow := StandardMaterial3D.new()
	snow.albedo_color = Color("e5eef2")
	snow.roughness = 0.95
	mesh.material_override = snow
	floor.add_child(mesh)
	# Distance markers make speed, steering and reversing easy to judge.
	for distance in range(-100, 101, 10):
		for side in [-1, 1]:
			var post := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.08
			cylinder.bottom_radius = 0.12
			cylinder.height = 0.85
			post.mesh = cylinder
			post.position = Vector3(side * 15.0, 0.425, distance)
			var paint := StandardMaterial3D.new()
			paint.albedo_color = Color("e07f37") if distance % 20 == 0 else Color("415b6d")
			post.material_override = paint
			add_child(post)

func _build_overlay() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.position = Vector2(20, 18)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.1, 0.14, 0.88)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 17)
	panel.add_child(status)

func _select(index: int) -> void:
	if input_source.character:
		input_source.character.submit_input(CharacterInput.new())
	selected = index
	for i in drivers.size():
		drivers[i].owner_peer_id = multiplayer.get_unique_id() if i == selected else 0
	input_source.character = drivers[selected]
	camera_rig.target = drivers[selected]
	camera_rig.yaw = vehicles[selected].rotation.y + 0.65
	camera_rig.pitch = -0.14
	camera_rig.first_person = false
	_update_inspection_camera()

func _process(_dt: float) -> void:
	if status == null:
		return
	var vehicle := vehicles[selected]
	var seated := drivers[selected].in_vehicle()
	status.text = "KOTM  /  VEHICLE TEST YARD\nF1 Snow truck   F2 Snow mobile UTV   F3 Inspect\nW/S drive/reverse   A/D steer   Space brake   F enter/exit\nMouse look   R reset yard   Esc release/capture cursor\n\n%s  |  %s  |  %+.0f km/h" % [LABELS[selected], "SEATED" if seated else "ON FOOT", vehicle.speed * 3.6]
	if inspecting:
		_update_inspection_camera()
	if vehicle.global_position.length() > 110:
		_reset_yard()

func _update_inspection_camera() -> void:
	if inspection_camera == null:
		return
	var vehicle := vehicles[selected]
	var offset := Vector3(-5.8, 3.2, -6.6) if selected == 0 else Vector3(-4.2, 2.6, -4.5)
	inspection_camera.global_position = vehicle.global_transform * offset
	inspection_camera.look_at(vehicle.global_position + Vector3(0, 1.2, 0), Vector3.UP)

func _set_inspecting(enabled: bool) -> void:
	inspecting = enabled
	camera_rig.look_enabled = not inspecting
	if inspecting:
		inspection_camera.make_current()
	else:
		camera_rig.camera.make_current()

func _reset_yard() -> void:
	for driver in drivers:
		if driver.in_vehicle():
			driver.leave_vehicle()
	for i in vehicles.size():
		var vehicle := vehicles[i]
		vehicle.global_transform = Transform3D(Basis.IDENTITY, PARKING[i])
		vehicle.speed = 0
		vehicle.steer = 0
		vehicle.velocity = Vector3.ZERO
		vehicle.reset_physics_interpolation()
		drivers[i].submit_input(CharacterInput.new())
		drivers[i].enter_vehicle(vehicle)
		drivers[i].reset_physics_interpolation()
	_select(selected)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		camera_rig.look_enabled = not inspecting and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_F1: _select(0)
		KEY_F2: _select(1)
		KEY_F3: _set_inspecting(not inspecting)
		KEY_R: _reset_yard()
