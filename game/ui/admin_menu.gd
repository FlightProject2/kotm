class_name AdminMenu
extends CanvasLayer
## Testing console (F10 in a match): spawn or clear bots, give a loadout, heal, god mode, refill,
## bullet trails on/off, spawn a vehicle, teleport to a point of interest, slow or speed up time.
## Single player only: every action runs on the authority directly.

const RED := Color("c8102e")
const INK := Color("f1ede6")
const INK_DIM := Color("b8b2a8")
const GOLD := Color("e6c25a")

var match_node: Match
var world: World
var camera_rig: CameraRig
var oswald: FontFile = preload("res://assets/fonts/Oswald[wght].ttf")
var barlow: FontFile = preload("res://assets/fonts/Barlow-Regular.ttf")
var panel: PanelContainer
var status: Label
var tracer_btn: Button
var god_btn: Button
var time_label: Label
var poi_select: OptionButton
var open: bool = false
var _was_captured := false

signal opened
signal closed

func _ready() -> void:
	layer = 20
	visible = false
	_build()

func _font(base: FontFile, size: int, weight := 500) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	if base == oswald:
		f.variation_opentype = {1013: weight}
	return f

func _label(text: String, size := 14, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font(oswald, size))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font(oswald, 14, 600))
	b.add_theme_font_size_override("font_size", 14)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.14, 0.16, 0.95)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.3, 0.3, 0.33)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 4; sb.content_margin_bottom = 4
	var hov: StyleBoxFlat = sb.duplicate()
	hov.border_color = RED
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.add_theme_stylebox_override("focus", sb)
	b.pressed.connect(on_press)
	return b

func _row(parent: Control, items: Array) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	for it in items:
		h.add_child(it)
	parent.add_child(h)

func _build() -> void:
	panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.04, 0.05, 0.94)
	sb.set_border_width_all(2)
	sb.border_color = RED
	sb.content_margin_left = 16; sb.content_margin_right = 16; sb.content_margin_top = 12; sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(20, 110)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	v.add_child(_label("ADMIN  ·  F10 closes", 22, GOLD))
	v.add_child(_label("BOTS", 12, INK_DIM))
	_row(v, [_button("+1 bot", func() -> void: _spawn_bots(1)), _button("+5 bots", func() -> void: _spawn_bots(5)),
		_button("+20 bots", func() -> void: _spawn_bots(20)), _button("Kill all bots", _kill_bots)])
	v.add_child(_label("PLAYER", 12, INK_DIM))
	_row(v, [_button("Give loadout", _give_loadout), _button("Refill ammo", _refill), _button("Heal", _heal)])
	god_btn = _button("God mode: OFF", _toggle_god)
	tracer_btn = _button("Bullet trails: ON", _toggle_tracers)
	_row(v, [god_btn, tracer_btn])
	v.add_child(_label("WORLD", 12, INK_DIM))
	_row(v, [_button("Spawn snow truck", func() -> void: _spawn_vehicle("pickup_truck")), _button("Spawn snowmobile", func() -> void: _spawn_vehicle("offroader"))])
	poi_select = OptionButton.new()
	poi_select.focus_mode = Control.FOCUS_NONE
	poi_select.add_theme_font_override("font", _font(oswald, 14))
	poi_select.custom_minimum_size = Vector2(220, 0)
	_row(v, [poi_select, _button("Teleport", _teleport)])
	time_label = _label("Time scale 1.0x", 12, INK_DIM)
	_row(v, [_button("0.25x", func() -> void: _time(0.25)), _button("0.5x", func() -> void: _time(0.5)),
		_button("1x", func() -> void: _time(1.0)), _button("2x", func() -> void: _time(2.0)), time_label])
	status = _label("", 13, INK_DIM)
	v.add_child(status)

func bind(p_match: Match, p_world: World, p_camera: CameraRig) -> void:
	match_node = p_match
	world = p_world
	camera_rig = p_camera
	poi_select.clear()
	if world and world.layout:
		for poi in world.layout.pois:
			poi_select.add_item(String(poi.get("name", poi.get("type", "poi"))))
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(match_node):
		return
	var p := match_node.local_player
	god_btn.text = "God mode: %s" % ("ON" if p and p.god_mode else "OFF")
	tracer_btn.text = "Bullet trails: %s" % ("ON" if Settings.tracers else "OFF")
	time_label.text = "Time scale %.2fx" % Engine.time_scale
	var bots := 0
	for c in match_node.characters:
		if c.is_bot and c.alive():
			bots += 1
	status.text = "alive bots %d   ·   fps %d   ·   vehicles %d" % [bots, Engine.get_frames_per_second(), get_tree().get_nodes_in_group("vehicles").size()]

func toggle() -> void:
	set_open(not open)

func set_open(on: bool) -> void:
	open = on
	visible = on
	if on:
		_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if camera_rig:
			camera_rig.look_enabled = false
		_refresh()
		opened.emit()
	else:
		if camera_rig:
			camera_rig.look_enabled = true
		if _was_captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F10:
		toggle()
		get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	if open and Engine.get_process_frames() % 30 == 0:
		_refresh()

# ---------- actions ----------
func _player() -> Character:
	return match_node.local_player if is_instance_valid(match_node) else null

func _spawn_bots(n: int) -> void:
	var p := _player()
	if p == null:
		return
	var made := match_node.spawn_bots_near(p.global_position, n)
	# they start with a rifle so they fight straight away
	for b in made:
		b.inventory.give_weapon("ar15")
		b.inventory.give_ammo("223", 90)
	status.text = "spawned %d bots" % made.size()

func _kill_bots() -> void:
	var n := 0
	for c in match_node.characters:
		if c.is_bot and c.alive():
			c.take_plain_damage(9999.0, null, "Admin")
			n += 1
	status.text = "killed %d bots" % n

func _give_loadout() -> void:
	var p := _player()
	if p == null:
		return
	var pos := p.global_position
	for it in [{"kind": "weapon", "id": "ar15"}, {"kind": "weapon", "id": "shotgun_12g"}, {"kind": "ammo", "id": "223", "qty": 150},
			{"kind": "ammo", "id": "shells", "qty": 24}, {"kind": "helmet", "id": "motorcycle_helmet"}, {"kind": "armor", "id": "laminated_armor"},
			{"kind": "med", "id": "bandage", "qty": 5}, {"kind": "med", "id": "first_aid_kit", "qty": 2}, {"kind": "backpack", "id": "military_backpack"}]:
		p.interaction._apply(it, pos)
	Events.inventory_changed.emit(p.character_id)
	status.text = "loadout given"

func _refill() -> void:
	var p := _player()
	if p == null:
		return
	for id in p.inventory.mags.keys():
		var d: Dictionary = ItemCatalog.weapon_def(id)
		p.inventory.mags[id] = int(d.get("magSize", p.inventory.mags[id]))
		if d.has("ammo"):
			p.inventory.give_ammo(d["ammo"], 120)
	status.text = "ammo refilled"

func _heal() -> void:
	var p := _player()
	if p:
		p.health.hp = 100.0
		p.health.bleeding = false
		status.text = "healed"

func _toggle_god() -> void:
	var p := _player()
	if p:
		p.god_mode = not p.god_mode
	_refresh()

func _toggle_tracers() -> void:
	Settings.tracers = not Settings.tracers
	Settings.save_settings()
	_refresh()

func _spawn_vehicle(id: String) -> void:
	var p := _player()
	if p == null or world == null:
		return
	var pos := p.global_position + p.forward() * 7.0
	pos.y = world.height_at(pos.x, pos.z)
	var v := Vehicle.new()
	world.vehicles.add_child(v)
	v.setup(id, world)
	v.global_transform = Transform3D(Basis(Vector3.UP, p.yaw), pos)
	status.text = "spawned %s" % v.display_name()

func _teleport() -> void:
	var p := _player()
	if p == null or world == null or poi_select.selected < 0:
		return
	var poi: Dictionary = world.layout.pois[poi_select.selected]
	var x := float(poi.get("x", 0.0)) + 12.0
	var z := float(poi.get("z", 0.0)) + 12.0
	if p.in_vehicle():
		p.leave_vehicle()
	p.global_position = Vector3(x, world.height_at(x, z) + 0.5, z)
	p.velocity = Vector3.ZERO
	p.mode = Character.Mode.GROUND
	if p.is_inside_tree():
		p.reset_physics_interpolation()
	status.text = "teleported to %s" % String(poi.get("name", "poi"))

func _time(scale: float) -> void:
	Engine.time_scale = scale
	_refresh()
