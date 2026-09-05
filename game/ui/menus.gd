class_name Menus
extends CanvasLayer
## All out-of-match and overlay screens, built in code in the HUD's style (docs/game-plan/10):
## main menu with a live character preview, customize, settings, pause, and the end-of-match
## screen. Main wires the signals; this class never touches the match directly.

signal play_pressed
signal resume_pressed
signal quit_to_menu_pressed
signal quit_game_pressed

const RED := Color("c8102e")
const INK := Color("f1ede6")
const INK_DIM := Color("b8b2a8")
const GOLD := Color("e6c25a")
const PANEL := Color(0.047, 0.05, 0.063, 0.82)
const SLOT_NAMES := {"head": "HEAD", "face": "FACE", "chest": "CHEST", "legs": "LEGS", "feet": "FEET", "hands": "HANDS", "back": "BACK", "parachute": "PARACHUTE"}
const PREVIEW_WEAPONS := ["ar15", "ak47", "hunting_rifle", "shotgun_12g", "hellfire", "m9", "magnum44"]
const CONTROLS := [
	["WASD", "Move"], ["Shift", "Sprint"], ["Space", "Jump"], ["C", "Crouch"], ["Mouse 1 / 2", "Fire / Aim"],
	["R", "Reload"], ["F", "Pick up"], ["1-6", "Hotbar"], ["T", "First person"], ["Alt", "Free look"],
	["H / J", "Bandage / Medkit"], ["M", "Map"], ["Esc", "Pause"],
]

var oswald: FontFile = preload("res://assets/fonts/Oswald[wght].ttf")
var barlow: FontFile = preload("res://assets/fonts/Barlow-Regular.ttf")
var barlow_semi: FontFile = preload("res://assets/fonts/Barlow-SemiBold.ttf")

var root: Control
var screens: Dictionary = {}
var current: String = ""
var preview: CharacterPreview
var preview_holder: Control
var loadout: Dictionary = {}
var cust_labels: Dictionary = {}
var weapon_labels: Dictionary = {}
var cust_weapon_i: int = 0
var end_title: Label
var end_sub: Label
var end_stats: Label
var main_status: Label
var settings_return: String = "main"
var _headless := false

func _ready() -> void:
	layer = 10
	_headless = DisplayServer.get_name() == "headless"
	loadout = Settings.cosmetics.duplicate(true)
	if not loadout.has("weapons"):
		loadout["weapons"] = {}
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	if not _headless:
		preview = CharacterPreview.new()
		preview.loadout = loadout
		preview.custom_minimum_size = Vector2(520, 720)
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screens["main"] = _build_main()
	screens["customize"] = _build_customize()
	screens["settings"] = _build_settings()
	screens["pause"] = _build_pause()
	screens["end"] = _build_end()
	for k in screens:
		screens[k].visible = false
		root.add_child(screens[k])
	show_screen("main")

# ---------- helpers ----------
func _font(base: FontFile, size: int, weight := 400) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = base
	if base == oswald:
		f.variation_opentype = {1013: weight}
	return f

func _label(text: String, size: int, color := INK, weight := 400, base: FontFile = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font(base if base else oswald, size, weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _button(text: String, big := true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font(oswald, 26 if big else 17, 600))
	b.add_theme_font_size_override("font_size", 26 if big else 17)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_hover_pressed_color", INK)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT if big else HORIZONTAL_ALIGNMENT_CENTER
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.09, 0.11, 0.85)
	normal.border_width_left = 4
	normal.border_color = Color(0.2, 0.2, 0.22)
	normal.content_margin_left = 22; normal.content_margin_right = 22
	normal.content_margin_top = 10 if big else 6; normal.content_margin_bottom = 10 if big else 6
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(0.16, 0.05, 0.07, 0.95)
	hover.border_color = RED
	var pressed: StyleBoxFlat = hover.duplicate()
	pressed.bg_color = RED
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	b.custom_minimum_size = Vector2(300 if big else 0, 0)
	b.pressed.connect(func() -> void: _click())
	return b

func _click() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am:
		am.play_ui("pickup", -8.0)

func _panel(color := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.content_margin_left = 22; sb.content_margin_right = 22; sb.content_margin_top = 16; sb.content_margin_bottom = 16
	p.add_theme_stylebox_override("panel", sb)
	return p

func _backdrop(alpha: float, gradient: bool) -> Control:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.032, 0.04, alpha)
	if gradient:
		var m := ShaderMaterial.new()
		var s := Shader.new()
		s.code = """
shader_type canvas_item;
uniform float alpha = 1.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 top = vec3(0.10, 0.11, 0.14);
	vec3 bot = vec3(0.025, 0.027, 0.034);
	float d = distance(uv, vec2(0.68, 0.48));
	vec3 c = mix(top, bot, uv.y);
	c += vec3(0.18, 0.03, 0.05) * (1.0 - smoothstep(0.0, 0.55, d));
	float stripe = step(0.9985, fract(uv.x * 40.0 + uv.y * 0.3)) * 0.06;
	c += stripe;
	COLOR = vec4(c, alpha);
}
"""
		m.shader = s
		m.set_shader_parameter("alpha", alpha)
		bg.material = m
	return bg

func _title_block(parent: Control, subtitle: String) -> void:
	var t := _label("KING OF THE", 44, INK, 300)
	var t2 := _label("MOUNTAIN", 74, INK, 700)
	t2.add_theme_constant_override("line_spacing", -10)
	var bar := ColorRect.new()
	bar.color = RED
	bar.custom_minimum_size = Vector2(120, 6)
	var sub := _label(subtitle, 15, INK_DIM, 400, barlow_semi)
	sub.add_theme_constant_override("line_spacing", 2)
	parent.add_child(t); parent.add_child(t2); parent.add_child(bar); parent.add_child(sub)

# ---------- main ----------
func _build_main() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(_backdrop(1.0, true))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_top", 60)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_bottom", 40)
	s.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	margin.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	_title_block(left, "Solo · 2 x 2 km slice · 30 bots\nEveryone parachutes in at a random point. Last one standing is King.")
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 26); left.add_child(sp)
	var play := _button("PLAY  SOLO")
	play.pressed.connect(func() -> void: play_pressed.emit())
	left.add_child(play)
	var cust := _button("CUSTOMIZE")
	cust.pressed.connect(func() -> void: show_screen("customize"))
	left.add_child(cust)
	var sett := _button("SETTINGS")
	sett.pressed.connect(func() -> void: settings_return = "main"; show_screen("settings"))
	left.add_child(sett)
	if not OS.has_feature("web"):
		var quit := _button("QUIT")
		quit.pressed.connect(func() -> void: quit_game_pressed.emit())
		left.add_child(quit)
	main_status = _label("", 18, GOLD, 500)
	main_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_status.custom_minimum_size = Vector2(420, 0)
	left.add_child(main_status)
	var spacer := Control.new(); spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; left.add_child(spacer)
	left.add_child(_controls_strip())
	preview_holder = VBoxContainer.new()
	preview_holder.custom_minimum_size = Vector2(540, 0)
	cols.add_child(preview_holder)
	var foot := _label("Milestone 1 build · Godot 4.6 · assets by Kenney, Quaternius (CC0), GDQuest (CC-BY)", 12, INK_DIM, 400, barlow)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(80, -30)
	s.add_child(foot)
	return s

func _controls_strip() -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 2)
	for c in CONTROLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var key := _label(c[0], 13, INK, 600)
		var key_panel := _panel(Color(0.14, 0.14, 0.16, 0.9))
		var sb: StyleBoxFlat = key_panel.get_theme_stylebox("panel")
		sb.content_margin_left = 7; sb.content_margin_right = 7; sb.content_margin_top = 1; sb.content_margin_bottom = 1
		key_panel.add_child(key)
		row.add_child(key_panel)
		row.add_child(_label(c[1], 13, INK_DIM, 400, barlow))
		grid.add_child(row)
	return grid

# ---------- customize ----------
func _build_customize() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(_backdrop(1.0, true))
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_bottom", 40)
	s.add_child(margin)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 40)
	margin.add_child(cols)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	left.add_child(_label("CUSTOMIZE", 48, INK, 700))
	left.add_child(_label("Cosmetics only. Nothing here changes stats.", 14, INK_DIM, 400, barlow))
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 10); left.add_child(sp)
	var box := _panel()
	box.custom_minimum_size = Vector2(520, 0)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	box.add_child(rows)
	left.add_child(box)
	for slot in SkinSystem.data()["slots"]:
		rows.add_child(_cycle_row(String(SLOT_NAMES.get(slot, slot)), slot))
	var sp2 := Control.new(); sp2.custom_minimum_size = Vector2(0, 10); left.add_child(sp2)
	left.add_child(_label("WEAPON SKINS", 22, INK, 600))
	var wbox := _panel()
	wbox.custom_minimum_size = Vector2(520, 0)
	var wrows := VBoxContainer.new()
	wrows.add_theme_constant_override("separation", 6)
	wbox.add_child(wrows)
	left.add_child(wbox)
	for w in PREVIEW_WEAPONS:
		var wname := String(ItemCatalog.get_item(w).get("name", w)).to_upper()
		wrows.add_child(_cycle_row(wname, "weapon:" + w))
	var spacer := Control.new(); spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL; left.add_child(spacer)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 10)
	var back := _button("SAVE & BACK", false)
	back.pressed.connect(func() -> void: _save_loadout(); show_screen("main"))
	var reset := _button("RESET", false)
	reset.pressed.connect(func() -> void: loadout = SkinSystem.default_loadout(); _refresh_customize())
	var rnd := _button("RANDOM", false)
	rnd.pressed.connect(func() -> void:
		var rng := RandomNumberGenerator.new(); rng.randomize()
		loadout = SkinSystem.random_loadout(rng); _refresh_customize())
	btns.add_child(back); btns.add_child(reset); btns.add_child(rnd)
	left.add_child(btns)
	var right := VBoxContainer.new()
	right.name = "PreviewSlot"
	right.custom_minimum_size = Vector2(540, 0)
	cols.add_child(right)
	return s

func _cycle_row(title: String, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var t := _label(title, 15, INK_DIM, 500)
	t.custom_minimum_size = Vector2(150, 0)
	row.add_child(t)
	var prev := _button("<", false)
	prev.custom_minimum_size = Vector2(40, 0)
	prev.pressed.connect(func() -> void: _cycle(key, -1))
	row.add_child(prev)
	var val := _label("", 16, INK, 600)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)
	var next := _button(">", false)
	next.custom_minimum_size = Vector2(40, 0)
	next.pressed.connect(func() -> void: _cycle(key, 1))
	row.add_child(next)
	cust_labels[key] = val
	return row

func _options_for(key: String) -> Array:
	if key.begins_with("weapon:"):
		var w := key.substr(7)
		var out: Array = [{"id": "", "name": "Standard"}]
		for sk in SkinSystem.skins_for_weapon(w):
			if not String(sk["id"]).ends_with("_standard"):
				out.append(sk)
		return out
	var optional: bool = key in ["head", "face", "hands", "back"]
	var out: Array = [{"id": "", "name": "None"}] if optional else []
	out.append_array(SkinSystem.items_for_slot(key))
	return out

func _current_for(key: String) -> String:
	if key.begins_with("weapon:"):
		return String(loadout.get("weapons", {}).get(key.substr(7), ""))
	return String(loadout.get(key, ""))

func _set_for(key: String, id: String) -> void:
	if key.begins_with("weapon:"):
		if not loadout.has("weapons"):
			loadout["weapons"] = {}
		if id == "":
			loadout["weapons"].erase(key.substr(7))
		else:
			loadout["weapons"][key.substr(7)] = id
		if preview:
			preview.loadout = loadout.duplicate(true)
			preview.set_weapon(key.substr(7))
	else:
		loadout[key] = id
		if preview:
			preview.set_loadout(loadout)

func _cycle(key: String, dir: int) -> void:
	var opts := _options_for(key)
	if opts.is_empty():
		return
	var cur := _current_for(key)
	var i := 0
	for k in opts.size():
		if String(opts[k]["id"]) == cur:
			i = k
	i = posmod(i + dir, opts.size())
	_set_for(key, String(opts[i]["id"]))
	_refresh_customize()

func _refresh_customize() -> void:
	for key in cust_labels:
		var cur := _current_for(key)
		var name := "None" if cur == "" else String((SkinSystem.item(cur) if not key.begins_with("weapon:") else SkinSystem.weapon_skin(cur)).get("name", cur))
		if key.begins_with("weapon:") and cur == "":
			name = "Standard"
		cust_labels[key].text = name.to_upper()
	if preview:
		preview.set_loadout(loadout)

func _save_loadout() -> void:
	Settings.cosmetics = loadout.duplicate(true)
	Settings.save_settings()

# ---------- settings ----------
var sens_slider: HSlider
var vol_slider: HSlider
var invert_check: CheckButton
var fp_check: CheckButton

func _build_settings() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(_backdrop(0.92, true))
	var box := _panel()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 0)
	box.position = Vector2(-280, -220)
	s.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	box.add_child(v)
	v.add_child(_label("SETTINGS", 40, INK, 700))
	sens_slider = _slider_row(v, "MOUSE SENSITIVITY", 0.0006, 0.006, 0.0001, Settings.mouse_sensitivity,
		func(val: float) -> void: Settings.mouse_sensitivity = val)
	vol_slider = _slider_row(v, "MASTER VOLUME", 0.0, 1.0, 0.05, Settings.master_volume,
		func(val: float) -> void:
			Settings.master_volume = val
			var am := get_node_or_null("/root/AudioManager")
			if am and am.has_method("_apply_volume"):
				am._apply_volume())
	invert_check = _check_row(v, "INVERT MOUSE Y", Settings.invert_y, func(on: bool) -> void: Settings.invert_y = on)
	fp_check = _check_row(v, "START IN FIRST PERSON", Settings.first_person_default, func(on: bool) -> void: Settings.first_person_default = on)
	v.add_child(_label("Changes apply immediately and are saved when you go back.", 13, INK_DIM, 400, barlow))
	var back := _button("BACK", false)
	back.pressed.connect(func() -> void: Settings.save_settings(); show_screen(settings_return))
	v.add_child(back)
	return s

func _slider_row(parent: Control, title: String, lo: float, hi: float, step: float, val: float, on_change: Callable) -> HSlider:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	var t := _label(title, 15, INK_DIM, 500)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var num := _label("", 15, INK, 600)
	head.add_child(t); head.add_child(num)
	row.add_child(head)
	var sl := HSlider.new()
	sl.min_value = lo; sl.max_value = hi; sl.step = step; sl.value = val
	sl.custom_minimum_size = Vector2(0, 24)
	sl.focus_mode = Control.FOCUS_NONE
	var fmt := func(x: float) -> String: return ("%.4f" % x) if hi < 0.1 else ("%d%%" % int(round(x * 100.0)))
	num.text = fmt.call(val)
	sl.value_changed.connect(func(x: float) -> void: num.text = fmt.call(x); on_change.call(x))
	row.add_child(sl)
	parent.add_child(row)
	return sl

func _check_row(parent: Control, title: String, val: bool, on_change: Callable) -> CheckButton:
	var row := HBoxContainer.new()
	var t := _label(title, 15, INK_DIM, 500)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cb := CheckButton.new()
	cb.button_pressed = val
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(on: bool) -> void: on_change.call(on))
	row.add_child(t); row.add_child(cb)
	parent.add_child(row)
	return cb

func refresh_settings() -> void:
	if sens_slider:
		sens_slider.value = Settings.mouse_sensitivity
		vol_slider.value = Settings.master_volume
		invert_check.button_pressed = Settings.invert_y
		fp_check.button_pressed = Settings.first_person_default

# ---------- pause ----------
func _build_pause() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(_backdrop(0.62, false))
	var box := _panel()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(380, 0)
	box.position = Vector2(-190, -160)
	s.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)
	v.add_child(_label("PAUSED", 40, INK, 700))
	v.add_child(_label("The match keeps running.", 13, INK_DIM, 400, barlow))
	var resume := _button("RESUME")
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	v.add_child(resume)
	var sett := _button("SETTINGS")
	sett.pressed.connect(func() -> void: settings_return = "pause"; show_screen("settings"))
	v.add_child(sett)
	var quit := _button("QUIT TO MENU")
	quit.pressed.connect(func() -> void: quit_to_menu_pressed.emit())
	v.add_child(quit)
	return s

# ---------- end ----------
func _build_end() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(_backdrop(0.78, false))
	var box := _panel()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(620, 0)
	box.position = Vector2(-310, -200)
	s.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)
	end_title = _label("", 56, GOLD, 700)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_title)
	end_sub = _label("", 18, INK, 400, barlow_semi)
	end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_sub)
	var bar := ColorRect.new(); bar.color = RED; bar.custom_minimum_size = Vector2(0, 3)
	v.add_child(bar)
	end_stats = _label("", 16, INK_DIM, 400, barlow)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_stats)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	var again := _button("PLAY AGAIN", false)
	again.pressed.connect(func() -> void: play_pressed.emit())
	var menu := _button("MAIN MENU", false)
	menu.pressed.connect(func() -> void: quit_to_menu_pressed.emit())
	btns.add_child(again); btns.add_child(menu)
	v.add_child(btns)
	return s

func show_end(won: bool, placement: int, killer_name: String, weapon: String, headshot: bool, stats: Dictionary) -> void:
	end_title.text = "KING OF THE MOUNTAIN" if won else "#%d" % placement
	end_title.add_theme_color_override("font_color", GOLD if won else INK)
	if won:
		end_sub.text = "Last one standing."
	elif killer_name != "":
		end_sub.text = "Killed by %s  ·  %s%s" % [killer_name, weapon, "  ·  HEADSHOT" if headshot else ""]
	else:
		end_sub.text = "Died to the gas."
	var mins := int(stats.get("time", 0.0)) / 60
	var secs := int(stats.get("time", 0.0)) % 60
	end_stats.text = "KILLS  %d      DAMAGE  %d      SURVIVED  %d:%02d      %d PLAYERS" % [
		int(stats.get("kills", 0)), int(stats.get("damage", 0)), mins, secs, int(stats.get("players", 0))]
	show_screen("end")

# ---------- screen switching ----------
func show_screen(name: String) -> void:
	current = name
	for k in screens:
		screens[k].visible = (k == name)
	visible = name != ""
	if preview:
		var slot: Control = null
		if name == "main":
			slot = preview_holder
		elif name == "customize":
			slot = screens["customize"].find_child("PreviewSlot", true, false)
		if preview.get_parent() != slot:
			if preview.get_parent():
				preview.get_parent().remove_child(preview)
			if slot:
				slot.add_child(preview)
		preview.visible = slot != null
	if name == "customize":
		_refresh_customize()
	elif name == "settings":
		refresh_settings()
	elif name == "main":
		loadout = Settings.cosmetics.duplicate(true)
		if preview:
			preview.set_loadout(loadout)

func hide_all() -> void:
	show_screen("")
