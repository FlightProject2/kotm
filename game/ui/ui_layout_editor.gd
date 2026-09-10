class_name UILayoutEditor
extends Control
## In-game UI layout tool. Pick any front-end screen, drag its top-level panels, resize them
## from the bottom-right corner, then save a responsive user preset or copy its JSON for a build.

signal screen_changed(screen_name: String)

const SAVE_PATH := "user://kotm_ui_layout.json"
const LEGACY_SAVE_PATH := "user://kotm_lobby_layout.json"
const TARGET_NAMES := [
	"MainNavigation",
	"MatchmakingColumn",
	"MainPlayerStage",
	"SeasonPartyColumn",
	"MainWatermark",
	"CustomizeAppearance",
]

var target_root: Control
var screen_roots: Dictionary = {}
var screen_names: Array[String] = []
var current_screen := "main"
var targets: Dictionary = {}
var handles: Dictionary = {}
var defaults: Dictionary = {}
var layout_data: Dictionary = {}
var screen_defaults: Dictionary = {}
var screen_layouts: Dictionary = {}
var selected: Control
var editor_layer: Control
var screen_selector: OptionButton
var selector: OptionButton
var x_spin: SpinBox
var y_spin: SpinBox
var w_spin: SpinBox
var h_spin: SpinBox
var scale_spin: SpinBox
var visible_check: CheckButton
var json_edit: TextEdit
var status: Label
var _syncing := false
var _screen_syncing := false

class LayoutHandle extends Control:
	var target: Control
	var editor
	var dragging := false
	var resizing := false
	var drag_start := Vector2.ZERO
	var rect_start := Rect2()

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_MOVE
		queue_redraw()

	func _process(_dt: float) -> void:
		if target == null or not is_instance_valid(target):
			return
		if not dragging:
			var rect := target.get_global_rect()
			global_position = rect.position
			size = rect.size
		visible = target.visible or editor.selected == target
		queue_redraw()

	func _draw() -> void:
		var chosen: bool = editor.selected == target
		var color := Color(1.0, 0.12, 0.12, 0.95) if chosen else Color(0.95, 0.75, 0.18, 0.72)
		draw_rect(Rect2(Vector2.ZERO, size), color, false, 2.0)
		draw_rect(Rect2(size - Vector2(18, 18), Vector2(18, 18)), color, true)
		draw_string(ThemeDB.fallback_font, Vector2(6, 18), String(target.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				editor.select_target(target)
				editor.detach_target(target)
				dragging = true
				resizing = event.position.x >= size.x - 22.0 and event.position.y >= size.y - 22.0
				mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE if resizing else Control.CURSOR_MOVE
				drag_start = get_global_mouse_position()
				rect_start = Rect2(target.position, target.size)
			else:
				dragging = false
				resizing = false
				mouse_default_cursor_shape = Control.CURSOR_MOVE
				editor.commit_target(target)
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			var delta := get_global_mouse_position() - drag_start
			if resizing:
				target.size = Vector2(maxf(80.0, rect_start.size.x + delta.x / target.scale.x), maxf(40.0, rect_start.size.y + delta.y / target.scale.y))
			else:
				target.position = rect_start.position + delta
			editor.refresh_inspector()
			accept_event()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	editor_layer = Control.new()
	editor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	editor_layer.visible = false
	add_child(editor_layer)
	_build_inspector()

func setup(root: Control) -> void:
	## Backwards-compatible single-screen setup for tools/tests that only have one root.
	setup_screens({"main": root})

func setup_screens(roots: Dictionary) -> void:
	screen_roots = roots.duplicate()
	screen_names.clear()
	for key in screen_roots.keys():
		screen_names.append(String(key))
	screen_names.sort()
	if screen_names.has("main"):
		screen_names.erase("main")
		screen_names.push_front("main")
	current_screen = screen_names[0] if not screen_names.is_empty() else "main"
	target_root = screen_roots.get(current_screen) as Control
	_collect_targets()
	if target_root and not target_root.resized.is_connected(_on_target_root_resized):
		target_root.resized.connect(_on_target_root_resized)
	call_deferred("_finish_setup")

func _on_target_root_resized() -> void:
	if not layout_data.is_empty():
		call_deferred("apply_layout", layout_data)

func _collect_targets() -> void:
	targets.clear()
	if target_root == null:
		return
	# Named main-menu regions remain stable for existing presets. Other screens are built in
	# code, so expose each direct child as a movable design region and give anonymous nodes a
	# readable, stable name for the saved JSON.
	for name in TARGET_NAMES:
		var node := target_root.find_child(name, true, false) as Control
		if node:
			targets[name] = node
	var index := 0
	for child in target_root.get_children():
		var node := child as Control
		if node == null or node == editor_layer:
			index += 1
			continue
		var name := String(node.name)
		if name.is_empty() or name.begins_with("@"):
			name = "%s_%s_%02d" % [current_screen.capitalize(), node.get_class(), index]
			node.name = name
		if not targets.has(name):
			targets[name] = node
		index += 1

func _finish_setup() -> void:
	await get_tree().process_frame
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_saved()
	_prepare_screen(current_screen)
	_build_handles()
	_fill_screen_selector()
	_fill_selector()
	if not targets.is_empty():
		select_target(targets.values()[0])

func _prepare_screen(name: String) -> void:
	if not screen_roots.has(name):
		return
	current_screen = name
	target_root = screen_roots[name] as Control
	if target_root and not target_root.resized.is_connected(_on_target_root_resized):
		target_root.resized.connect(_on_target_root_resized)
	_collect_targets()
	if not screen_defaults.has(name):
		screen_defaults[name] = capture_layout().duplicate(true)
	defaults = screen_defaults[name].duplicate(true)
	if screen_layouts.has(name):
		apply_layout(screen_layouts[name], false)
	else:
		layout_data = defaults.duplicate(true)

func _fill_screen_selector() -> void:
	if screen_selector == null:
		return
	_screen_syncing = true
	screen_selector.clear()
	for name in screen_names:
		screen_selector.add_item(String(name).replace("_", " ").to_upper())
		var index := screen_selector.item_count - 1
		screen_selector.set_item_metadata(index, name)
	for index in screen_selector.item_count:
		if String(screen_selector.get_item_metadata(index)) == current_screen:
			screen_selector.select(index)
			break
	_screen_syncing = false

func _build_handles() -> void:
	for old in handles.values():
		old.queue_free()
	handles.clear()
	for name in targets:
		var handle := LayoutHandle.new()
		handle.name = "Handle_" + String(name)
		handle.target = targets[name]
		handle.editor = self
		editor_layer.add_child(handle)
		editor_layer.move_child(handle, 0)
		handles[name] = handle

func _build_inspector() -> void:
	var panel := PanelContainer.new()
	panel.name = "UILayoutInspector"
	panel.anchor_left = 1.0; panel.anchor_right = 1.0; panel.anchor_bottom = 1.0
	panel.offset_left = -330.0; panel.offset_right = 0.0
	panel.offset_top = 0.0; panel.offset_bottom = 0.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.026, 0.033, 0.98)
	style.border_color = Color(0.8, 0.03, 0.08)
	style.set_border_width_all(2)
	style.content_margin_left = 16; style.content_margin_right = 16
	style.content_margin_top = 14; style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	editor_layer.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	column.add_child(_label("UI LAYOUT TOOL", 23, Color.WHITE))
	column.add_child(_label("Choose a screen, then drag or resize its panels.", 13, Color("b8b2a8")))
	column.add_child(_label("SCREEN", 12, Color("e6c25a")))
	screen_selector = OptionButton.new()
	screen_selector.item_selected.connect(func(index: int) -> void:
		if _screen_syncing or index < 0 or index >= screen_selector.item_count:
			return
		var name := String(screen_selector.get_item_metadata(index))
		set_screen(name)
	)
	column.add_child(screen_selector)
	column.add_child(_label("REGION", 12, Color("e6c25a")))
	selector = OptionButton.new()
	selector.item_selected.connect(func(index: int) -> void:
		if index >= 0 and index < selector.item_count:
			select_target(targets.get(selector.get_item_metadata(index)))
	)
	column.add_child(selector)
	x_spin = _number_row(column, "X", -4000, 4000)
	y_spin = _number_row(column, "Y", -4000, 4000)
	w_spin = _number_row(column, "WIDTH", 40, 4000)
	h_spin = _number_row(column, "HEIGHT", 30, 4000)
	scale_spin = _number_row(column, "SCALE", 0.25, 3.0, 0.05)
	for spin in [x_spin, y_spin, w_spin, h_spin, scale_spin]:
		spin.value_changed.connect(func(_value: float) -> void: apply_inspector())
	visible_check = CheckButton.new()
	visible_check.text = "VISIBLE"
	visible_check.toggled.connect(func(on: bool) -> void:
		if not _syncing and selected:
			selected.visible = on
			commit_target(selected)
	)
	column.add_child(visible_check)
	var save := _button("SAVE LAYOUT")
	save.pressed.connect(save_layout)
	column.add_child(save)
	var reset := _button("RESET CODE DEFAULTS")
	reset.pressed.connect(reset_layout)
	column.add_child(reset)
	var copy := _button("COPY LAYOUT JSON")
	copy.pressed.connect(copy_json)
	column.add_child(copy)
	json_edit = TextEdit.new()
	json_edit.placeholder_text = "Paste layout JSON here, then press APPLY PASTED JSON."
	json_edit.custom_minimum_size = Vector2(0, 135)
	json_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(json_edit)
	var apply := _button("APPLY PASTED JSON")
	apply.pressed.connect(apply_pasted_json)
	column.add_child(apply)
	status = _label("F10 closes this tool", 12, Color("e6c25a"))
	column.add_child(status)
	var close := _button("CLOSE UI LAYOUT TOOL")
	close.pressed.connect(close_editor)
	column.add_child(close)

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 34
	return button

func _number_row(parent: VBoxContainer, title: String, minimum: float, maximum: float, step := 1.0) -> SpinBox:
	var row := HBoxContainer.new()
	var label := _label(title, 13, Color("b8b2a8"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spin := SpinBox.new()
	spin.min_value = minimum; spin.max_value = maximum; spin.step = step
	spin.custom_minimum_size.x = 145
	row.add_child(label); row.add_child(spin); parent.add_child(row)
	return spin

func _fill_selector() -> void:
	if selector == null:
		return
	selector.clear()
	for name in targets:
		selector.add_item(String(name))
		selector.set_item_metadata(selector.item_count - 1, name)

func set_screen(name: String) -> void:
	if _screen_syncing or not screen_roots.has(name) or name == current_screen:
		return
	_prepare_screen(name)
	_build_handles()
	_fill_screen_selector()
	_fill_selector()
	selected = null
	if not targets.is_empty():
		select_target(targets.values()[0])
	screen_changed.emit(current_screen)

func open_editor() -> void:
	editor_layer.visible = true
	_fill_screen_selector()
	_fill_selector()
	if selected:
		select_target(selected)

func close_editor() -> void:
	editor_layer.visible = false

func toggle_editor() -> void:
	if editor_layer.visible:
		close_editor()
	else:
		open_editor()

func is_open() -> bool:
	return editor_layer != null and editor_layer.visible

func select_target(target: Control) -> void:
	if target == null:
		return
	selected = target
	for index in selector.item_count:
		if String(selector.get_item_metadata(index)) == String(target.name):
			selector.select(index)
			break
	refresh_inspector()

func detach_target(target: Control) -> void:
	var rect := Rect2(target.position, target.size)
	target.set_anchors_preset(Control.PRESET_TOP_LEFT)
	target.position = rect.position
	target.size = rect.size

func refresh_inspector() -> void:
	if selected == null:
		return
	_syncing = true
	x_spin.value = selected.position.x
	y_spin.value = selected.position.y
	w_spin.value = selected.size.x
	h_spin.value = selected.size.y
	scale_spin.value = selected.scale.x
	visible_check.button_pressed = selected.visible
	_syncing = false

func apply_inspector() -> void:
	if _syncing or selected == null:
		return
	detach_target(selected)
	selected.position = Vector2(x_spin.value, y_spin.value)
	selected.size = Vector2(w_spin.value, h_spin.value)
	selected.scale = Vector2.ONE * scale_spin.value
	commit_target(selected)

func commit_target(target: Control) -> void:
	if target_root == null or target_root.size.x <= 0.0 or target_root.size.y <= 0.0:
		return
	layout_data[String(target.name)] = _target_record(target)
	screen_layouts[current_screen] = layout_data.duplicate(true)
	status.text = "Unsaved changes"
	refresh_inspector()

func _target_record(target: Control) -> Dictionary:
	return {
		"rect": [
			target.position.x / target_root.size.x,
			target.position.y / target_root.size.y,
			target.size.x / target_root.size.x,
			target.size.y / target_root.size.y,
		],
		"scale": target.scale.x,
		"visible": target.visible,
	}

func capture_layout() -> Dictionary:
	var result := {}
	if target_root == null or target_root.size.x <= 0.0 or target_root.size.y <= 0.0:
		return result
	for name in targets:
		result[name] = _target_record(targets[name])
	return result

func apply_layout(data: Dictionary, store := true) -> void:
	if target_root == null:
		return
	for name in data:
		var target := targets.get(name) as Control
		var record: Variant = data[name]
		if target == null or not record is Dictionary:
			continue
		var rect: Array = record.get("rect", [])
		if rect.size() != 4:
			continue
		target.set_anchors_preset(Control.PRESET_TOP_LEFT)
		target.position = Vector2(float(rect[0]) * target_root.size.x, float(rect[1]) * target_root.size.y)
		target.size = Vector2(maxf(40.0, float(rect[2]) * target_root.size.x), maxf(30.0, float(rect[3]) * target_root.size.y))
		var scale_value := clampf(float(record.get("scale", 1.0)), 0.25, 3.0)
		target.scale = Vector2.ONE * scale_value
		target.visible = bool(record.get("visible", true))
	layout_data = data.duplicate(true)
	if store:
		screen_layouts[current_screen] = layout_data.duplicate(true)
	refresh_inspector()

func save_layout() -> void:
	layout_data = capture_layout()
	screen_layouts[current_screen] = layout_data.duplicate(true)
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(screen_layouts, "\t"))
		status.text = "Saved %s layout on this device" % current_screen
	else:
		status.text = "Could not save layout"

func _load_saved() -> void:
	var path := SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else LEGACY_SAVE_PATH
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return
	# The original lobby-only tool saved one flat region dictionary. Import it as the main
	# screen automatically so existing user presets keep working after this upgrade.
	var dict := parsed as Dictionary
	var looks_flat := false
	for key in dict:
		if dict[key] is Dictionary and (dict[key] as Dictionary).has("rect"):
			looks_flat = true
			break
	if looks_flat:
		screen_layouts["main"] = dict.duplicate(true)
	else:
		for key in dict:
			if dict[key] is Dictionary:
				screen_layouts[String(key)] = (dict[key] as Dictionary).duplicate(true)

func reset_layout() -> void:
	apply_layout(defaults)
	screen_layouts.erase(current_screen)
	if screen_layouts.is_empty():
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	else:
		var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(screen_layouts, "\t"))
	status.text = "Restored %s defaults" % current_screen

func copy_json() -> void:
	layout_data = capture_layout()
	var encoded := JSON.stringify(layout_data, "\t")
	json_edit.text = encoded
	DisplayServer.clipboard_set(encoded)
	status.text = "Layout JSON copied"

func apply_pasted_json() -> void:
	var parsed: Variant = JSON.parse_string(json_edit.text)
	if parsed is Dictionary:
		apply_layout(parsed)
		status.text = "Pasted layout applied; press SAVE to keep it"
	else:
		status.text = "That text is not valid layout JSON"
