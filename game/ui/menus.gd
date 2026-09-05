class_name Menus
extends CanvasLayer
## Front-end screens in the Z1BR / King of the Kill layout: a torn red side panel with PLAY /
## CUSTOMIZE / MARKETPLACE, the character centre stage, wallet + dailies on the right; a Customize
## item grid with rarity bars and locked items; a Marketplace with crates and a reel-style crate
## opening; stats, settings, pause and the end screen. Built in code. Main wires the signals.

signal play_pressed
signal resume_pressed
signal quit_to_menu_pressed
signal quit_game_pressed

const RED := Color("c8102e")
const RED_DARK := Color("5a0b14")
const INK := Color("f1ede6")
const INK_DIM := Color("b8b2a8")
const GOLD := Color("e6c25a")
const GREEN := Color("6fd36f")
const PANEL := Color(0.047, 0.05, 0.063, 0.82)
const PANEL_SOLID := Color(0.07, 0.072, 0.085, 0.96)
const TABS := {
	"CLOTHING": ["chest", "legs", "feet", "hands"],
	"HEAD": ["hair", "skin", "head", "face"],
	"GEAR": ["back", "parachute"],
	"WEAPONS": [],
}
const SLOT_NAMES := {"head": "HAT", "face": "MASK", "chest": "SHIRT", "legs": "PANTS", "feet": "SHOES", "hands": "GLOVES", "back": "BACKPACK", "parachute": "PARACHUTE", "skin": "SKIN", "hair": "HAIR"}
const PREVIEW_WEAPONS := ["ar15", "ak47", "hunting_rifle", "shotgun_12g", "hellfire", "m9", "magnum44"]
const CONTROLS := [
	["WASD", "Move"], ["Shift", "Sprint"], ["Space", "Jump"], ["C", "Crouch"], ["Mouse 1 / 2", "Fire / Aim"],
	["R", "Reload"], ["F", "Pick up / Drive"], ["1-6", "Hotbar"], ["T", "First person"], ["Alt", "Free look"],
	["H / J", "Bandage / Medkit"], ["M", "Map"], ["Esc", "Pause"],
]

var oswald: FontFile = preload("res://assets/fonts/Oswald[wght].ttf")
var barlow: FontFile = preload("res://assets/fonts/Barlow-Regular.ttf")
var barlow_semi: FontFile = preload("res://assets/fonts/Barlow-SemiBold.ttf")

var root: Control
var screens: Dictionary = {}
var current: String = ""
var preview: CharacterPreview
var preview_slots: Dictionary = {}     # screen -> Control that hosts the preview
var loadout: Dictionary = {}
var main_status: Label
var settings_return: String = "main"
var _headless := false
# main
var wallet_labels: Dictionary = {}
var dailies_box: VBoxContainer
var stats_box: VBoxContainer
var toast_label: Label
var _toast_t := 0.0
# customize
var cust_tab: String = "CLOTHING"
var cust_weapon: String = "ar15"
var cust_grid: GridContainer
var cust_tabs: HBoxContainer
var cust_weapon_row: HBoxContainer
var cust_info: Label
var cust_labels: Dictionary = {}       # kept for tests: slot -> Label showing the equipped name
# marketplace
var market_cards: VBoxContainer
var reel_layer: Control
var reel_strip: HBoxContainer
var reel_clip: Control
var reel_result: Control
var reel_result_name: Label
var reel_result_sub: Label
var reel_claim: Button
var _reel_t := -1.0
var _reel_dur := 4.4
var _reel_target_x := 0.0
var _reel_start_x := 0.0
var _reel_drop: Dictionary = {}
# end
var end_title: Label
var end_sub: Label
var end_stats: Label
var end_reward: Label
# settings
var sens_slider: HSlider
var vol_slider: HSlider
var invert_check: CheckButton
var fp_check: CheckButton

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
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screens["main"] = _build_main()
	screens["customize"] = _build_customize()
	screens["market"] = _build_market()
	screens["stats"] = _build_stats()
	screens["settings"] = _build_settings()
	screens["pause"] = _build_pause()
	screens["end"] = _build_end()
	for k in screens:
		screens[k].visible = false
		root.add_child(screens[k])
	toast_label = _label("", 18, GOLD, 600)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.position = Vector2(-300, 70)
	toast_label.size = Vector2(600, 30)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.visible = false
	root.add_child(toast_label)
	if Engine.has_singleton("Progress") or get_node_or_null("/root/Progress"):
		Progress.changed.connect(_refresh_wallet)
		Progress.crate_awarded.connect(func(id: String, reason: String) -> void: toast("%s awarded (%s)" % [String(Progress.CRATES[id]["name"]), reason]))
		Progress.challenge_completed.connect(func(c: Dictionary) -> void: toast("Daily complete: %s  +%d coins" % [c["text"], int(c["coins"])]))
	show_screen("main")

func _process(dt: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= dt
		toast_label.modulate.a = clampf(_toast_t / 0.6, 0.0, 1.0)
		if _toast_t <= 0.0:
			toast_label.visible = false
	if _reel_t >= 0.0:
		_reel_t += dt
		var k := clampf(_reel_t / _reel_dur, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.6)   # fast start, long slow-down
		reel_strip.position.x = lerpf(_reel_start_x, _reel_target_x, e)
		if k >= 1.0:
			_reel_t = -1.0
			_reveal_drop()

func toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	_toast_t = 4.0

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

func _style(bg: Color, border: Color = Color(0, 0, 0, 0), border_w := 0, radius := 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 6; sb.content_margin_bottom = 6
	return sb

func _button(text: String, size := 17, w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font(oswald, size, 600))
	b.add_theme_font_size_override("font_size", size)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(st, INK)
	b.add_theme_color_override("font_disabled_color", INK_DIM)
	var normal := _style(Color(0.13, 0.13, 0.15, 0.95), Color(0.28, 0.28, 0.3), 1)
	var hover := _style(Color(0.22, 0.06, 0.08, 0.98), RED, 1)
	var pressed := _style(RED, RED, 1)
	var disabled := _style(Color(0.1, 0.1, 0.11, 0.7), Color(0.2, 0.2, 0.22), 1)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", normal)
	b.add_theme_stylebox_override("disabled", disabled)
	if w > 0.0:
		b.custom_minimum_size = Vector2(w, 0)
	b.pressed.connect(func() -> void: _click())
	return b

## Big side-panel entry: red triangle + word, like the Z1BR menu.
func _menu_entry(text: String, size: int, on_press: Callable) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.custom_minimum_size = Vector2(380, size + 22)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, empty)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 14)
	var tri := Polygon2D.new()
	var s := size * 0.5
	tri.polygon = PackedVector2Array([Vector2(0, 0), Vector2(s * 0.9, s * 0.5), Vector2(0, s)])
	tri.color = RED
	var tri_holder := Control.new()
	tri_holder.custom_minimum_size = Vector2(s, size + 22)
	tri_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tri.position = Vector2(0, (size + 22) * 0.5 - s * 0.5)
	tri_holder.add_child(tri)
	row.add_child(tri_holder)
	var l := _label(text, size, INK, 500)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	b.add_child(row)
	b.mouse_entered.connect(func() -> void: l.add_theme_color_override("font_color", GOLD); tri.color = GOLD)
	b.mouse_exited.connect(func() -> void: l.add_theme_color_override("font_color", INK); tri.color = RED)
	b.pressed.connect(func() -> void: _click(); on_press.call())
	return b

func _click() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am:
		am.play_ui("ui_click", -6.0)

func _panel(color := PANEL, border := Color(0, 0, 0, 0), border_w := 0) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := _style(color, border, border_w, 3)
	sb.content_margin_left = 18; sb.content_margin_right = 18; sb.content_margin_top = 12; sb.content_margin_bottom = 12
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _backdrop(alpha: float, torn_panel: bool) -> Control:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.032, 0.04, alpha)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = """
shader_type canvas_item;
uniform float alpha = 1.0;
uniform float panel_w = 0.0;   // 0 = no side panel
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 uv = SCREEN_UV;
	// hangar backdrop: dark blue-grey gradient with a warm floor and light streaks
	vec3 top = vec3(0.16, 0.19, 0.23);
	vec3 bot = vec3(0.05, 0.05, 0.06);
	vec3 c = mix(top, bot, smoothstep(0.1, 0.95, uv.y));
	c += vec3(0.10, 0.09, 0.07) * (1.0 - smoothstep(0.0, 0.7, distance(uv, vec2(0.62, 0.55))));
	float streak = smoothstep(0.0, 0.02, abs(fract((uv.x - uv.y * 0.55) * 6.0) - 0.5) - 0.44) ;
	c += vec3(0.05) * (1.0 - streak) * (1.0 - uv.y);
	c *= 0.85 + 0.3 * noise(uv * vec2(40.0, 22.0));
	if (panel_w > 0.0) {
		float edge = panel_w + 0.045 * noise(vec2(uv.y * 9.0, 3.0)) + 0.012 * noise(vec2(uv.y * 40.0, 7.0));
		float inside = 1.0 - smoothstep(edge - 0.004, edge + 0.004, uv.x);
		vec3 red = mix(vec3(0.50, 0.06, 0.09), vec3(0.22, 0.03, 0.05), uv.y);
		red *= 0.8 + 0.4 * noise(uv * vec2(30.0, 60.0));
		float crack = step(0.985, noise(uv * vec2(120.0, 300.0)));
		red -= crack * 0.15;
		c = mix(c, red, inside);
		c = mix(c, vec3(0.02), inside * (1.0 - smoothstep(0.0, 0.03, edge - uv.x)) * 0.8);
	}
	COLOR = vec4(c, alpha);
}
"""
	m.shader = s
	m.set_shader_parameter("alpha", alpha)
	m.set_shader_parameter("panel_w", 0.27 if torn_panel else 0.0)
	bg.material = m
	return bg

func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _rarity_color(r: String) -> Color:
	return Progress.RARITY_COLORS.get(r, Color("9aa0a6")) if get_node_or_null("/root/Progress") else Color("9aa0a6")

# ---------- main ----------
func _build_main() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(_backdrop(1.0, true))
	# left torn panel content
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.position = Vector2(70, 40)
	left.size = Vector2(430, 1000)
	left.add_theme_constant_override("separation", 6)
	s.add_child(left)
	var logo := VBoxContainer.new()
	logo.add_theme_constant_override("separation", -18)
	var l1 := _label("KOTM", 132, INK, 900)
	l1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l1.add_theme_constant_override("shadow_offset_x", 4)
	l1.add_theme_constant_override("shadow_offset_y", 5)
	var l2 := _label("KING OF THE MOUNTAIN", 26, GOLD, 600)
	logo.add_child(l1); logo.add_child(l2)
	left.add_child(logo)
	left.add_child(_spacer(40))
	left.add_child(_menu_entry("PLAY", 44, func() -> void: play_pressed.emit()))
	left.add_child(_menu_entry("CUSTOMIZE", 44, func() -> void: show_screen("customize")))
	left.add_child(_menu_entry("MARKETPLACE", 44, func() -> void: show_screen("market")))
	left.add_child(_spacer(10))
	left.add_child(_menu_entry("LEADERBOARDS", 26, func() -> void: show_screen("stats")))
	left.add_child(_menu_entry("SETTINGS", 26, func() -> void: settings_return = "main"; show_screen("settings")))
	left.add_child(_spacer(24))
	# message of the day
	var motd := _panel(Color(0.02, 0.02, 0.025, 0.9))
	motd.custom_minimum_size = Vector2(380, 0)
	var mv := VBoxContainer.new()
	mv.add_theme_constant_override("separation", 4)
	mv.add_child(_label("MESSAGE OF THE DAY", 18, INK, 700))
	var promo := _panel(Color(0.55, 0.07, 0.1, 1.0))
	var pv := VBoxContainer.new()
	pv.add_child(_label("Hot Shot CRATE", 30, GOLD, 800))
	pv.add_child(_label("Win a match for a free Victory Crate. Flames, chrome and camo drops.", 13, INK, 400, barlow))
	var promo_btn := _button("AVAILABLE NOW", 13, 140)
	promo_btn.pressed.connect(func() -> void: show_screen("market"))
	pv.add_child(promo_btn)
	promo.add_child(pv)
	promo.mouse_filter = Control.MOUSE_FILTER_PASS
	mv.add_child(promo)
	motd.add_child(mv)
	motd.mouse_filter = Control.MOUSE_FILTER_PASS
	left.add_child(motd)
	main_status = _label("", 16, GOLD, 500)
	main_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_status.custom_minimum_size = Vector2(380, 0)
	left.add_child(main_status)
	if not OS.has_feature("web"):
		var quit := _button("EXIT KOTM", 18, 380)
		quit.pressed.connect(func() -> void: quit_game_pressed.emit())
		quit.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		quit.position = Vector2(70, -70)
		s.add_child(quit)
	# top bar: wallet + profile
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.position = Vector2(560, 22)
	top.add_theme_constant_override("separation", 34)
	s.add_child(top)
	for key in ["coins", "crates", "wins", "kills"]:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 8)
		var icon := ColorRect.new()
		icon.custom_minimum_size = Vector2(22, 22)
		icon.color = {"coins": GOLD, "crates": Color("c8102e"), "wins": GREEN, "kills": INK_DIM}[key]
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var lab := _label("0", 22, INK, 600)
		var cap := _label(key.to_upper(), 11, INK_DIM, 500)
		cap.size_flags_vertical = Control.SIZE_SHRINK_END
		cell.add_child(icon); cell.add_child(lab); cell.add_child(cap)
		top.add_child(cell)
		wallet_labels[key] = lab
	var name_lab := _label("", 22, INK, 700)
	wallet_labels["name"] = name_lab
	top.add_child(name_lab)
	# centre: character stage
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_CENTER)
	stage.position = Vector2(-330 + 130, -430)
	stage.size = Vector2(640, 900)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(stage)
	preview_slots["main"] = stage
	# right: dailies + stats
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.position = Vector2(-470, 90)
	right.size = Vector2(420, 700)
	right.add_theme_constant_override("separation", 10)
	s.add_child(right)
	var dt := _label("DAILIES", 30, INK, 700)
	dt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(dt)
	dailies_box = VBoxContainer.new()
	dailies_box.add_theme_constant_override("separation", 6)
	right.add_child(dailies_box)
	right.add_child(_spacer(20))
	var st := _label("SOLO RECORD", 22, INK, 700)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(st)
	stats_box = VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 3)
	right.add_child(stats_box)
	# bottom: controls strip
	var ctr := _controls_strip()
	ctr.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	ctr.position = Vector2(560, -80)
	s.add_child(ctr)
	var foot := _label("Milestone 1 · Godot 4.6 · Kenney, Quaternius (CC0), GDQuest (CC-BY)", 11, INK_DIM, 400, barlow)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	foot.position = Vector2(-470, -26)
	s.add_child(foot)
	return s

func _controls_strip() -> Control:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 2)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in CONTROLS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var kp := _panel(Color(0.14, 0.14, 0.16, 0.9))
		var sb: StyleBoxFlat = kp.get_theme_stylebox("panel")
		sb.content_margin_left = 6; sb.content_margin_right = 6; sb.content_margin_top = 0; sb.content_margin_bottom = 0
		kp.add_child(_label(c[0], 12, INK, 600))
		row.add_child(kp)
		row.add_child(_label(c[1], 12, INK_DIM, 400, barlow))
		grid.add_child(row)
	return grid

func _refresh_wallet() -> void:
	if wallet_labels.is_empty():
		return
	var pr := get_node_or_null("/root/Progress")
	if pr == null:
		return
	wallet_labels["coins"].text = str(pr.coins)
	var n := 0
	for k in pr.crates:
		n += int(pr.crates[k])
	wallet_labels["crates"].text = str(n)
	wallet_labels["wins"].text = str(int(pr.stats["wins"]))
	wallet_labels["kills"].text = str(int(pr.stats["kills"]))
	wallet_labels["name"].text = pr.player_name
	for c in dailies_box.get_children():
		c.queue_free()
	for d in pr.dailies:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		dot.color = GREEN if d["done"] else Color(0.25, 0.25, 0.28)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var t := _label(String(d["text"]), 15, INK if not d["done"] else INK_DIM, 400, barlow_semi)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var prog := _label("%d / %d" % [int(d["progress"]), int(d["target"])], 15, GOLD if d["done"] else INK, 600)
		row.add_child(dot); row.add_child(t); row.add_child(prog)
		var reward := _label("+%d%s" % [int(d["coins"]), "  +crate" if String(d["crate"]) != "" else ""], 12, INK_DIM, 400, barlow)
		var wrap := VBoxContainer.new()
		wrap.add_theme_constant_override("separation", 0)
		wrap.add_child(row); wrap.add_child(reward)
		dailies_box.add_child(wrap)
	for c in stats_box.get_children():
		c.queue_free()
	var st: Dictionary = pr.stats
	for pair in [["Matches", int(st["matches"])], ["Wins", int(st["wins"])], ["Kills", int(st["kills"])], ["Top 10", int(st["top10"])],
			["Best placement", ("#%d" % int(st["best_placement"])) if int(st["best_placement"]) > 0 else "—"], ["Damage", int(st["damage"])]]:
		var row := HBoxContainer.new()
		var a := _label(String(pair[0]), 14, INK_DIM, 400, barlow)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(a)
		row.add_child(_label(str(pair[1]), 14, INK, 600))
		stats_box.add_child(row)

# ---------- customize ----------
func _build_customize() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(_backdrop(1.0, false))
	# character on top, centred
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_CENTER_TOP)
	stage.position = Vector2(-220, -40)
	stage.size = Vector2(440, 470)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(stage)
	preview_slots["customize"] = stage
	var title := _label("CUSTOMIZE", 34, INK, 700)
	title.position = Vector2(70, 30)
	s.add_child(title)
	var back := _button("SAVE & BACK", 16, 160)
	back.pressed.connect(func() -> void: _save_loadout(); show_screen("main"))
	back.set_anchors_preset(Control.PRESET_TOP_LEFT)
	back.position = Vector2(70, 84)
	s.add_child(back)
	var rnd := _button("RANDOM (OWNED)", 14, 160)
	rnd.pressed.connect(func() -> void: _random_owned(); _refresh_customize())
	rnd.position = Vector2(70, 130)
	s.add_child(rnd)
	# item board
	var board := _panel(Color(0.04, 0.04, 0.05, 0.9), Color(0.25, 0.25, 0.28), 1)
	board.set_anchors_preset(Control.PRESET_CENTER)
	board.position = Vector2(-520, -110)
	board.size = Vector2(1040, 560)
	board.mouse_filter = Control.MOUSE_FILTER_PASS
	s.add_child(board)
	var bv := VBoxContainer.new()
	bv.add_theme_constant_override("separation", 8)
	board.add_child(bv)
	cust_tabs = HBoxContainer.new()
	cust_tabs.add_theme_constant_override("separation", 6)
	for t in TABS:
		var tb := _button(String(t), 15, 150)
		tb.pressed.connect(func() -> void: cust_tab = String(t); _refresh_customize())
		cust_tabs.add_child(tb)
	bv.add_child(cust_tabs)
	cust_weapon_row = HBoxContainer.new()
	cust_weapon_row.add_theme_constant_override("separation", 4)
	for w in PREVIEW_WEAPONS:
		var wb := _button(String(ItemCatalog.get_item(w).get("name", w)).to_upper(), 12, 120)
		wb.pressed.connect(func() -> void: cust_weapon = String(w); if preview: preview.set_weapon(cust_weapon); _refresh_customize())
		cust_weapon_row.add_child(wb)
	bv.add_child(cust_weapon_row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1000, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cust_grid = GridContainer.new()
	cust_grid.columns = 8
	cust_grid.add_theme_constant_override("h_separation", 8)
	cust_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(cust_grid)
	bv.add_child(scroll)
	cust_info = _label("", 15, INK_DIM, 400, barlow_semi)
	bv.add_child(cust_info)
	# the equipped-name labels the old tests read
	for slot in SkinSystem.data()["slots"]:
		cust_labels[slot] = Label.new()
	return s

func _tile(entry: Dictionary, equipped: bool, owned: bool, on_press: Callable) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(114, 114)
	var rarity: String = String(entry.get("rarity", "common"))
	var rc := _rarity_color(rarity)
	var normal := _style(Color(0.1, 0.1, 0.12, 1.0), RED if equipped else Color(0.3, 0.3, 0.33), 2 if equipped else 1, 3)
	var hover := _style(Color(0.16, 0.16, 0.18, 1.0), RED if equipped else GOLD, 2, 3)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", normal)
	# icon: pattern texture or colour swatch
	var recipe: Dictionary = entry.get("recipe", {})
	var icon := TextureRect.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 10; icon.offset_top = 10; icon.offset_right = -10; icon.offset_bottom = -30
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base := Color(String(recipe.get("color", recipe.get("base", "#777777"))))
	var pattern := String(recipe.get("pattern", "solid"))
	if pattern != "solid" and pattern != "":
		icon.texture = SkinSystem.pattern_texture(pattern, base, Color(String(recipe.get("accent", "#222222"))))
	else:
		var img := Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(base)
		icon.texture = ImageTexture.create_from_image(img)
	if entry.get("id", "") == "":
		icon.modulate = Color(1, 1, 1, 0.15)
	b.add_child(icon)
	var name_l := _label(String(entry.get("name", "")).to_upper(), 10, INK if owned else INK_DIM, 500)
	name_l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_l.offset_top = -26; name_l.offset_bottom = -8
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	b.add_child(name_l)
	var bar := ColorRect.new()
	bar.color = rc
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -5; bar.offset_bottom = -1; bar.offset_left = 2; bar.offset_right = -2
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(bar)
	if not owned:
		icon.modulate = Color(0.45, 0.45, 0.45, 0.9)
		var lock := _label("LOCKED", 11, GOLD, 700)
		lock.set_anchors_preset(Control.PRESET_CENTER)
		lock.position = Vector2(-26, -10)
		b.add_child(lock)
	b.mouse_entered.connect(func() -> void: cust_info.text = "%s  ·  %s%s" % [String(entry.get("name", "")), rarity.replace("_", " ").to_upper(), "" if owned else "  ·  drop from a crate"])
	b.pressed.connect(func() -> void: _click(); on_press.call())
	return b

func _refresh_customize() -> void:
	if cust_grid == null:
		return
	var pr := get_node_or_null("/root/Progress")
	for c in cust_grid.get_children():
		c.queue_free()
	for i in cust_tabs.get_child_count():
		var tb: Button = cust_tabs.get_child(i)
		tb.add_theme_stylebox_override("normal", _style(RED if tb.text == cust_tab else Color(0.13, 0.13, 0.15, 0.95), RED if tb.text == cust_tab else Color(0.28, 0.28, 0.3), 1))
	cust_weapon_row.visible = cust_tab == "WEAPONS"
	if cust_tab == "WEAPONS":
		for i in cust_weapon_row.get_child_count():
			var wb: Button = cust_weapon_row.get_child(i)
			var wid: String = PREVIEW_WEAPONS[i]
			wb.add_theme_stylebox_override("normal", _style(RED if wid == cust_weapon else Color(0.13, 0.13, 0.15, 0.95), RED if wid == cust_weapon else Color(0.28, 0.28, 0.3), 1))
		var cur := String(loadout.get("weapons", {}).get(cust_weapon, ""))
		for sk in SkinSystem.skins_for_weapon(cust_weapon):
			var id := String(sk["id"])
			var is_std := id.ends_with("_standard")
			var eq := (cur == "" and is_std) or cur == id
			var owned: bool = pr == null or pr.owns(id)
			cust_grid.add_child(_tile(sk, eq, owned, func() -> void:
				if not owned:
					cust_info.text = "Locked: %s drops from crates." % String(sk["name"])
					return
				_set_for("weapon:" + cust_weapon, "" if is_std else id)
				_refresh_customize()))
	else:
		for slot in TABS[cust_tab]:
			var header := _label(String(SLOT_NAMES.get(slot, slot)), 13, GOLD, 700)
			header.custom_minimum_size = Vector2(114, 114)
			header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cust_grid.add_child(header)
			var cur := String(loadout.get(slot, ""))
			var options := _options_for(slot)
			var n := 1
			for opt in options:
				var id := String(opt["id"])
				var owned: bool = pr == null or pr.owns(id)
				cust_grid.add_child(_tile(opt, cur == id, owned, func() -> void:
					if not owned:
						cust_info.text = "Locked: %s drops from crates." % String(opt["name"])
						return
					_set_for(slot, id)
					_refresh_customize()))
				n += 1
			while n % cust_grid.columns != 0:
				cust_grid.add_child(_spacer(1))
				n += 1
	for slot in cust_labels:
		var cur := _current_for(slot)
		cust_labels[slot].text = ("NONE" if cur == "" else String(SkinSystem.item(cur).get("name", cur)).to_upper())
	if preview:
		preview.set_loadout(loadout)
		if cust_tab == "WEAPONS":
			preview.set_weapon(cust_weapon)

func _options_for(key: String) -> Array:
	if key.begins_with("weapon:"):
		var w := key.substr(7)
		var out: Array = [{"id": "", "name": "Standard", "rarity": "common"}]
		for sk in SkinSystem.skins_for_weapon(w):
			if not String(sk["id"]).ends_with("_standard"):
				out.append(sk)
		return out
	var optional: bool = key in ["head", "face", "hands", "back"]
	var out: Array = [{"id": "", "name": "None", "rarity": "common", "recipe": {"color": "#333333"}}] if optional else []
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
	else:
		loadout[key] = id

## Kept for tests and keyboard use: step a slot through its options.
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

func _random_owned() -> void:
	var pr := get_node_or_null("/root/Progress")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for slot in SkinSystem.data()["slots"]:
		var opts := _options_for(slot).filter(func(o): return pr == null or pr.owns(String(o["id"])))
		if not opts.is_empty():
			loadout[slot] = String(opts[rng.randi_range(0, opts.size() - 1)]["id"])
	loadout["weapons"] = {}
	for w in PREVIEW_WEAPONS:
		var opts := SkinSystem.skins_for_weapon(w).filter(func(o): return (pr == null or pr.owns(String(o["id"]))) and not String(o["id"]).ends_with("_standard"))
		if not opts.is_empty() and rng.randf() < 0.6:
			loadout["weapons"][w] = String(opts[rng.randi_range(0, opts.size() - 1)]["id"])

func _save_loadout() -> void:
	Settings.cosmetics = loadout.duplicate(true)
	Settings.save_settings()

# ---------- marketplace ----------
func _build_market() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(_backdrop(1.0, false))
	var title := _label("MARKETPLACE", 34, INK, 700)
	title.position = Vector2(70, 30)
	s.add_child(title)
	var sub := _label("Crates drop one skin each. Rarity odds: common 50%, uncommon 28%, rare 14%, ultra rare 6%, legendary 2%. Duplicates refund coins.", 14, INK_DIM, 400, barlow)
	sub.position = Vector2(70, 76)
	s.add_child(sub)
	var back := _button("BACK", 16, 140)
	back.pressed.connect(func() -> void: show_screen("main"))
	back.position = Vector2(70, 110)
	s.add_child(back)
	market_cards = VBoxContainer.new()
	market_cards.set_anchors_preset(Control.PRESET_TOP_LEFT)
	market_cards.position = Vector2(70, 170)
	market_cards.size = Vector2(760, 700)
	market_cards.add_theme_constant_override("separation", 14)
	s.add_child(market_cards)
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	stage.position = Vector2(-620, 60)
	stage.size = Vector2(560, 800)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.add_child(stage)
	preview_slots["market"] = stage
	# crate opening overlay
	reel_layer = Control.new()
	reel_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	reel_layer.visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.82)
	reel_layer.add_child(dim)
	var rt := _label("OPENING CRATE", 34, INK, 700)
	rt.set_anchors_preset(Control.PRESET_CENTER_TOP)
	rt.position = Vector2(-200, 220)
	rt.size = Vector2(400, 40)
	rt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reel_layer.add_child(rt)
	reel_clip = Control.new()
	reel_clip.set_anchors_preset(Control.PRESET_CENTER)
	reel_clip.position = Vector2(-560, -90)
	reel_clip.size = Vector2(1120, 150)
	reel_clip.clip_contents = true
	var clip_bg := ColorRect.new()
	clip_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_bg.color = Color(0.06, 0.06, 0.07, 1.0)
	reel_clip.add_child(clip_bg)
	reel_strip = HBoxContainer.new()
	reel_strip.add_theme_constant_override("separation", 6)
	reel_strip.position = Vector2(0, 8)
	reel_clip.add_child(reel_strip)
	var marker := ColorRect.new()
	marker.color = RED
	marker.position = Vector2(559, 0)
	marker.size = Vector2(3, 150)
	reel_clip.add_child(marker)
	reel_layer.add_child(reel_clip)
	reel_result = _panel(PANEL_SOLID, RED, 2)
	reel_result.set_anchors_preset(Control.PRESET_CENTER)
	reel_result.position = Vector2(-260, 90)
	reel_result.size = Vector2(520, 150)
	reel_result.visible = false
	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	reel_result_name = _label("", 30, GOLD, 800)
	reel_result_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reel_result_sub = _label("", 15, INK_DIM, 400, barlow_semi)
	reel_result_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reel_claim = _button("CLAIM", 18, 200)
	reel_claim.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reel_claim.pressed.connect(func() -> void: reel_layer.visible = false; _refresh_market())
	rv.add_child(reel_result_name); rv.add_child(reel_result_sub); rv.add_child(reel_claim)
	reel_result.add_child(rv)
	reel_result.mouse_filter = Control.MOUSE_FILTER_PASS
	reel_layer.add_child(reel_result)
	s.add_child(reel_layer)
	return s

func _refresh_market() -> void:
	if market_cards == null:
		return
	var pr := get_node_or_null("/root/Progress")
	for c in market_cards.get_children():
		c.queue_free()
	if pr == null:
		return
	for id in Progress.CRATES:
		var def: Dictionary = Progress.CRATES[id]
		var card := _panel(PANEL_SOLID, Color(0.3, 0.3, 0.33), 1)
		card.mouse_filter = Control.MOUSE_FILTER_PASS
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		var art := ColorRect.new()
		art.custom_minimum_size = Vector2(120, 90)
		art.color = Color(0.55, 0.07, 0.1) if id == "hot_shot_crate" else Color(0.75, 0.6, 0.2)
		row.add_child(art)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(_label(String(def["name"]).to_upper(), 24, INK, 700))
		col.add_child(_label(String(def["desc"]), 14, INK_DIM, 400, barlow))
		col.add_child(_label("You own: %d" % pr.crate_count(id), 14, GOLD, 600))
		row.add_child(col)
		var btns := VBoxContainer.new()
		btns.add_theme_constant_override("separation", 6)
		var cost := int(def["cost"])
		if cost > 0:
			var buy := _button("BUY  %d" % cost, 15, 160)
			buy.disabled = pr.coins < cost
			buy.pressed.connect(func() -> void:
				if pr.buy_crate(id):
					toast("Bought %s" % String(def["name"]))
				_refresh_market())
			btns.add_child(buy)
		else:
			btns.add_child(_label("Awarded on a win", 12, INK_DIM, 400, barlow))
		var open := _button("OPEN", 15, 160)
		open.disabled = pr.crate_count(id) <= 0
		open.pressed.connect(func() -> void: _open_crate(id))
		btns.add_child(open)
		row.add_child(btns)
		card.add_child(row)
		market_cards.add_child(card)
	var wallet := _label("COINS  %d" % pr.coins, 20, GOLD, 700)
	market_cards.add_child(wallet)

func _open_crate(crate_id: String) -> void:
	var pr := get_node_or_null("/root/Progress")
	if pr == null:
		return
	var drop: Dictionary = pr.open_crate(crate_id)
	if drop.is_empty():
		return
	_reel_drop = drop
	for c in reel_strip.get_children():
		c.queue_free()
	var pool: Array = pr.crate_pool()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var count := 46
	var land := 38
	var tile_w := 140.0
	for i in count:
		var e: Dictionary = drop if i == land else pool[rng.randi_range(0, pool.size() - 1)]
		var t := _panel(Color(0.12, 0.12, 0.14, 1.0), _rarity_color(String(e["rarity"])), 2)
		t.custom_minimum_size = Vector2(tile_w - 6, 134)
		var v := VBoxContainer.new()
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(90, 60)
		sw.color = _swatch_color(e)
		sw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var nm := _label(String(e["name"]).to_upper(), 10, INK, 500)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.clip_text = true
		nm.custom_minimum_size = Vector2(120, 0)
		v.add_child(sw); v.add_child(nm)
		t.add_child(v)
		reel_strip.add_child(t)
	# strip starts at x=0; the landing tile's centre must end under the marker (clip centre 560)
	_reel_start_x = 0.0
	_reel_target_x = 560.0 - (land * tile_w + tile_w * 0.5) + rng.randf_range(-40.0, 40.0)
	reel_strip.position.x = 0.0
	reel_result.visible = false
	reel_layer.visible = true
	_reel_t = 0.0
	var am := get_node_or_null("/root/AudioManager")
	if am:
		am.play_ui("reload", -6.0)

func _swatch_color(e: Dictionary) -> Color:
	var src: Dictionary = SkinSystem.item(String(e["id"])) if e.get("kind", "item") == "item" else SkinSystem.weapon_skin(String(e["id"]))
	var recipe: Dictionary = src.get("recipe", {})
	return Color(String(recipe.get("color", recipe.get("base", "#777777"))))

func _reveal_drop() -> void:
	var rarity := String(_reel_drop.get("rarity", "common"))
	reel_result_name.text = String(_reel_drop.get("name", "")).to_upper()
	reel_result_name.add_theme_color_override("font_color", _rarity_color(rarity))
	if bool(_reel_drop.get("duplicate", false)):
		reel_result_sub.text = "%s  ·  DUPLICATE, refunded %d coins" % [rarity.replace("_", " ").to_upper(), int(_reel_drop.get("refund", 0))]
	else:
		reel_result_sub.text = "%s  ·  NEW! Equip it in Customize." % rarity.replace("_", " ").to_upper()
	reel_result.visible = true
	var am := get_node_or_null("/root/AudioManager")
	if am:
		am.play_ui("kill" if rarity in ["legendary", "ultra_rare"] else "pickup", -4.0)

# ---------- stats ----------
var stats_full: VBoxContainer

func _build_stats() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(_backdrop(1.0, false))
	var box := _panel(PANEL_SOLID)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.position = Vector2(-300, -240)
	box.custom_minimum_size = Vector2(600, 0)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	s.add_child(box)
	stats_full = VBoxContainer.new()
	stats_full.add_theme_constant_override("separation", 8)
	box.add_child(stats_full)
	return s

func _refresh_stats() -> void:
	for c in stats_full.get_children():
		c.queue_free()
	stats_full.add_child(_label("LEADERBOARDS  ·  SOLO", 34, INK, 700))
	stats_full.add_child(_label("Local record until online play lands.", 13, INK_DIM, 400, barlow))
	var pr := get_node_or_null("/root/Progress")
	if pr:
		var st: Dictionary = pr.stats
		for pair in [["Player", pr.player_name], ["Matches", int(st["matches"])], ["Wins", int(st["wins"])], ["Kills", int(st["kills"])], ["Headshots", int(st["headshots"])],
				["Top 10 finishes", int(st["top10"])], ["Best placement", ("#%d" % int(st["best_placement"])) if int(st["best_placement"]) > 0 else "—"],
				["Damage dealt", int(st["damage"])], ["Items picked up", int(st["pickups"])], ["Driven", "%d m" % int(st["drive_m"])], ["Coins", pr.coins]]:
			var row := HBoxContainer.new()
			var a := _label(String(pair[0]), 17, INK_DIM, 400, barlow_semi)
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(a)
			row.add_child(_label(str(pair[1]), 17, INK, 600))
			stats_full.add_child(row)
	var back := _button("BACK", 16, 200)
	back.pressed.connect(func() -> void: show_screen("main"))
	stats_full.add_child(back)

# ---------- settings ----------
func _build_settings() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	s.add_child(_backdrop(0.94, false))
	var box := _panel(PANEL_SOLID)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(560, 0)
	box.position = Vector2(-280, -220)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
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
	var back := _button("BACK", 16)
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
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.62)
	s.add_child(dim)
	var box := _panel(PANEL_SOLID, RED, 2)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(380, 0)
	box.position = Vector2(-190, -160)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	s.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	box.add_child(v)
	v.add_child(_label("PAUSED", 40, INK, 700))
	v.add_child(_label("The match keeps running.", 13, INK_DIM, 400, barlow))
	var resume := _button("RESUME", 22)
	resume.pressed.connect(func() -> void: resume_pressed.emit())
	v.add_child(resume)
	var sett := _button("SETTINGS", 22)
	sett.pressed.connect(func() -> void: settings_return = "pause"; show_screen("settings"))
	v.add_child(sett)
	var quit := _button("QUIT TO MENU", 22)
	quit.pressed.connect(func() -> void: quit_to_menu_pressed.emit())
	v.add_child(quit)
	return s

# ---------- end ----------
func _build_end() -> Control:
	var s := Control.new()
	s.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.78)
	s.add_child(dim)
	var box := _panel(PANEL_SOLID, RED, 2)
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(640, 0)
	box.position = Vector2(-320, -210)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
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
	end_reward = _label("", 18, GOLD, 600)
	end_reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_reward)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 12)
	var again := _button("PLAY AGAIN", 18, 180)
	again.pressed.connect(func() -> void: play_pressed.emit())
	var menu := _button("MAIN MENU", 18, 180)
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
	var reward := 50 + maxi(0, 31 - placement) * 6 + (300 if won else 0)
	end_reward.text = "+%d coins%s" % [reward, "   ·   VICTORY CRATE awarded, open it in the Marketplace" if won else ""]
	show_screen("end")

# ---------- screen switching ----------
func show_screen(name: String) -> void:
	current = name
	for k in screens:
		screens[k].visible = (k == name)
	visible = name != ""
	if preview:
		var slot: Control = preview_slots.get(name, null)
		if preview.get_parent() != slot:
			if preview.get_parent():
				preview.get_parent().remove_child(preview)
			if slot:
				slot.add_child(preview)
				preview.set_anchors_preset(Control.PRESET_FULL_RECT)
		preview.visible = slot != null
		if slot:
			preview.set_loadout(loadout)
			preview.set_weapon(cust_weapon if name == "customize" and cust_tab == "WEAPONS" else "ar15")
	match name:
		"main":
			loadout = Settings.cosmetics.duplicate(true)
			if not loadout.has("weapons"):
				loadout["weapons"] = {}
			if preview:
				preview.set_loadout(loadout)
			_refresh_wallet()
		"customize":
			_refresh_customize()
		"market":
			_refresh_market()
		"stats":
			_refresh_stats()
		"settings":
			refresh_settings()

func hide_all() -> void:
	show_screen("")
