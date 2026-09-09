extends Node3D
## Review the authored map using the same World, terrain and lighting as the game.
## Run this scene directly; the main game scene is unchanged.

const VIEW_NAMES: Array[String] = [
	"Basin overview", "Ashford church", "Cranmoor street", "Frozen west lake", "The Mountain summit",
	"Frostmere Lodge", "Riverside Mill", "North Radar", "West river bridge",
	"Oakridge Terrace", "Coldwater Freight", "Pinewatch Waterworks", "Switchback Services",
	"Glacier Lodge ice rink",
]
const VIEW_FILES: Array[String] = [
	"01-basin-overview", "02-ashford-church", "03-cranmoor-street", "04-frozen-west-lake", "05-mountain-summit",
	"06-frostmere-lodge", "07-riverside-mill", "08-north-radar", "09-west-bridge",
	"10-oakridge-terrace", "11-coldwater-freight", "12-pinewatch-waterworks", "13-switchback-services",
	"14-glacier-lodge",
]
const FLY_SPEED := 55.0
const BOOST_MULTIPLIER := 5.0
const LOOK_SENSITIVITY := 0.0025

var world: World
var inspection_camera: Camera3D
var hud: CanvasLayer
var _view_label: Label
var _views: Array[Dictionary] = []
var _current_view := 0
var _looking := false
var _fog_enabled := true
var layout_overlay: Control

func _ready() -> void:
	world = preload("res://game/world/world.tscn").instantiate() as World
	add_child(world)
	world.setup("mesh", null, true)
	_fog_enabled = (world.get_node("Env") as WorldEnvironment).environment.fog_enabled
	inspection_camera = Camera3D.new()
	inspection_camera.name = "InspectionCamera"
	inspection_camera.near = 0.1
	inspection_camera.far = 6000.0
	add_child(inspection_camera)
	inspection_camera.make_current()
	_build_views()
	_build_hud()
	layout_overlay = preload("res://game/dev/map_layout_overlay.gd").new()
	var overlay_layer := CanvasLayer.new()
	overlay_layer.name = "LayoutPlan"
	add_child(overlay_layer)
	overlay_layer.add_child(layout_overlay)
	layout_overlay.call("setup", world)
	layout_overlay.hide()
	select_view(0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func get_view_names() -> PackedStringArray:
	return PackedStringArray(VIEW_NAMES)

func get_view_files() -> PackedStringArray:
	return PackedStringArray(VIEW_FILES)

func get_current_view() -> int:
	return _current_view

func set_hud_visible(value: bool) -> void:
	if hud:
		hud.visible = value

func set_tactical_view(value: bool) -> void:
	layout_overlay.visible = value
	if value:
		_looking = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Zero-based view index, shared by the number shortcuts and capture script.
func select_view(index: int) -> void:
	if index < 0 or index >= _views.size():
		return
	_current_view = index
	# The overview is above the gameplay foliage range: show the full forest for layout review.
	for batch: MultiMeshInstance3D in world.trees.get_children():
		batch.visibility_range_end = 0.0 if index == 0 else TreePlacer.VIS_RANGE
	# A survey camera sits beyond the normal atmosphere distance; show the full layout.
	(world.get_node("Env") as WorldEnvironment).environment.fog_enabled = _fog_enabled and index != 0
	var view: Dictionary = _views[index]
	inspection_camera.global_position = view["position"]
	inspection_camera.fov = float(view["fov"])
	inspection_camera.look_at(view["target"], Vector3.UP)
	if _view_label:
		_view_label.text = "%d / %s" % [index + 1, VIEW_NAMES[index]]

func _build_views() -> void:
	_views.append({"position": Vector3(1500, 1450, 1700), "target": Vector3(0, -70, 0), "fov": 47.0})
	var church := Vector2(520, 447)
	var church_yaw := 0.0
	for building: Dictionary in world.layout.buildings:
		if building.get("prefab", "") == "church" and building.get("poi", "") == "ashford":
			church = Vector2(float(building["x"]), float(building["z"]))
			church_yaw = float(building.get("yaw", 0.0))
			break
	var church_target := _ground_point(church, 4.5)
	var church_offset := Basis(Vector3.UP, church_yaw) * Vector3(27, 10, 32)
	var church_eye := church_target + church_offset
	church_eye.y = maxf(church_eye.y, world.height_at(church_eye.x, church_eye.z) + 6.0)
	_views.append({"position": church_eye, "target": church_target, "fov": 57.0})
	var village := _poi_position("cranmoor", Vector2(-560, -300))
	_views.append({
		"position": _ground_point(village + Vector2(-73, 0), 3.2),
		"target": _ground_point(village + Vector2(38, 0), 3.0), "fov": 66.0,
	})
	var lake := Vector2(-800, 150)
	_views.append({
		"position": _ground_point(lake + Vector2(125, 165), 65.0),
		"target": _ground_point(lake, 1.0), "fov": 63.0,
	})
	var summit := _poi_position("the_mountain", Vector2.ZERO)
	var summit_target := _ground_point(summit, 3.0)
	var summit_eye := _ground_point(summit + Vector2(115, 130), 30.0)
	summit_eye.y = maxf(summit_eye.y, summit_target.y + 65.0)
	_views.append({"position": summit_eye, "target": summit_target, "fov": 64.0})
	for point in ["frostmere_lodge", "riverside_mill", "north_radar"]:
		var location := _poi_position(point, Vector2.ZERO)
		var target := _ground_point(location, 4.0)
		var eye := _ground_point(location + Vector2(64, 70), 28.0)
		eye.y = maxf(eye.y, target.y + 25.0)
		_views.append({"position": eye, "target": target, "fov": 59.0})
	var bridge_center := Vector2(-700, 183)
	var bridge_top := 22.0
	if not world.layout.bridges.is_empty():
		var bridge: Dictionary = world.layout.bridges[0]
		bridge_center = Vector2((float(bridge.ax) + float(bridge.bx)) * 0.5, (float(bridge.az) + float(bridge.bz)) * 0.5)
		bridge_top = float(bridge.deckY)
	var bridge_eye := _ground_point(bridge_center + Vector2(65, 60), 24.0)
	_views.append({"position": bridge_eye, "target": Vector3(bridge_center.x, bridge_top, bridge_center.y), "fov": 62.0})
	_views.append({"position": Vector3(460, 68, 530), "target": Vector3(413, 34, 429), "fov": 61.0})
	_views.append({"position": Vector3(-579, 85, -700), "target": Vector3(-648, 54, -760), "fov": 65.0})
	_views.append({"position": Vector3(-529, 46, -318), "target": Vector3(-574, 29, -359), "fov": 61.0})
	_views.append({"position": Vector3(308, 57, -184), "target": Vector3(279, 49, -214), "fov": 60.0})
	_views.append({"position": Vector3(585, 71, 612), "target": Vector3(522, 35, 547), "fov": 66.0})

func _poi_position(id: String, fallback: Vector2) -> Vector2:
	var poi := world.layout.poi(id)
	if poi.is_empty():
		return fallback
	return Vector2(float(poi["x"]), float(poi["z"]))

func _ground_point(point: Vector2, clearance: float) -> Vector3:
	return Vector3(point.x, world.height_at(point.x, point.y) + clearance, point.y)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "TourHUD"
	add_child(hud)
	var panel := PanelContainer.new()
	panel.position = Vector2(22, 22)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.065, 0.82)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	hud.add_child(panel)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 6)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lines)
	var title := Label.new()
	title.text = "KOTM / SNOW MAP REVIEW"
	title.add_theme_font_size_override("font_size", 21)
	lines.add_child(title)
	_view_label = Label.new()
	_view_label.add_theme_font_size_override("font_size", 18)
	_view_label.add_theme_color_override("font_color", Color(0.65, 0.85, 0.96))
	lines.add_child(_view_label)
	var controls := Label.new()
	controls.text = "WASD fly  /  Q down  /  E up  /  Shift boost\nHold right mouse to look  /  Esc release mouse\n1–9 locations  /  0 Oakridge  /  [ ] cycle every view\nM layout plan"
	controls.add_theme_font_size_override("font_size", 15)
	controls.add_theme_color_override("font_color", Color(0.81, 0.85, 0.88))
	lines.add_child(controls)

func _process(delta: float) -> void:
	if inspection_camera == null or layout_overlay.visible or not get_window().has_focus():
		return
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		move -= inspection_camera.global_basis.z
	if Input.is_physical_key_pressed(KEY_S):
		move += inspection_camera.global_basis.z
	if Input.is_physical_key_pressed(KEY_A):
		move -= inspection_camera.global_basis.x
	if Input.is_physical_key_pressed(KEY_D):
		move += inspection_camera.global_basis.x
	if Input.is_physical_key_pressed(KEY_Q):
		move -= Vector3.UP
	if Input.is_physical_key_pressed(KEY_E):
		move += Vector3.UP
	if move.is_zero_approx():
		return
	var speed := FLY_SPEED * (BOOST_MULTIPLIER if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	inspection_camera.global_position += move.normalized() * speed * delta
	var eye := inspection_camera.global_position
	if absf(eye.x) <= world.half_size() and absf(eye.z) <= world.half_size():
		eye.y = maxf(eye.y, world.height_at(eye.x, eye.z) + 1.8)
		inspection_camera.global_position = eye
	_view_label.text = "Free flight / %s" % VIEW_NAMES[_current_view]

func _unhandled_input(event: InputEvent) -> void:
	if layout_overlay.visible and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _looking:
		inspection_camera.rotation.y -= event.relative.x * LOOK_SENSITIVITY
		inspection_camera.rotation.x = clampf(inspection_camera.rotation.x - event.relative.y * LOOK_SENSITIVITY, -1.5, 1.5)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key == KEY_M:
			set_tactical_view(not layout_overlay.visible)
			get_viewport().set_input_as_handled()
		elif key >= KEY_1 and key <= KEY_9:
			select_view(key - KEY_1)
			get_viewport().set_input_as_handled()
		elif key == KEY_0:
			# The number row has ten usable keys; 0 opens the first expansion district.
			select_view(9)
			get_viewport().set_input_as_handled()
		elif key == KEY_BRACKETLEFT or key == KEY_BRACKETRIGHT:
			var step := -1 if key == KEY_BRACKETLEFT else 1
			select_view(posmod(_current_view + step, _views.size()))
			get_viewport().set_input_as_handled()
		elif key == KEY_ESCAPE:
			set_tactical_view(false)
			_looking = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
