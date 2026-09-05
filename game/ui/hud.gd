class_name HUD
extends CanvasLayer
## In-match HUD (docs/game-plan/10), built in code: remain counter, compass, zone banner, kill
## feed, reticle + hitmarker, health/ammo, gear, hotbar, popups, pickup prompt, map screen.

const RED := Color("c8102e")
const INK := Color("f1ede6")
const INK_DIM := Color("b8b2a8")
const ZONE_GREEN := Color("5fd35f")
const ORANGE := Color("e8842b")
const GOLD := Color("e6c25a")
const PANEL := Color(0.047, 0.05, 0.063, 0.72)

var character: Character
var match_ref: Match
var camera_rig: CameraRig
var world: World
var oswald: FontFile = preload("res://assets/fonts/Oswald[wght].ttf")
var barlow: FontFile = preload("res://assets/fonts/Barlow-Regular.ttf")
var barlow_semi: FontFile = preload("res://assets/fonts/Barlow-SemiBold.ttf")

var root: Control
var remain_label: Label
var zone_label: Label
var zone_num: Label
var zone_box: PanelContainer
var banner_label: Label
var feed: VBoxContainer
var weapon_label: Label
var ammo_label: Label
var hp_bar: ProgressBar
var hp_num: Label
var bleed_label: Label
var status_label: Label
var gear_label: Label
var hotbar: HBoxContainer
var hot_tiles: Array[PanelContainer] = []
var hot_names: Array[Label] = []
var popups: VBoxContainer
var prompt: PanelContainer
var prompt_label: Label
var compass: Control
var reticle: Control
var hitmarker: Control
var vignette: ColorRect
var gasfx: ColorRect
var scope: ColorRect
var map_screen: Control
var _hit_kind := ""
var _hit_alpha := 0.0
var _hit_kill := false
var _hurt := 0.0
var _gas := 0.0
var _banner_t := 0.0
var _status_t := 0.0
var _zone_state := ""
var _zone_phase := -1
var _zone_left := 0.0
var map_open := false
var preview_tex: Texture2D

func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build()
	Events.remain_changed.connect(func(n: int) -> void: remain_label.text = str(n))
	Events.kill_feed.connect(_on_kill_feed)
	Events.banner.connect(show_banner)
	Events.toast.connect(show_banner)
	Events.popup.connect(_on_popup)
	Events.hit_confirmed.connect(_on_hit)
	Events.damaged.connect(func(_a: float, _d: Vector3, _k: String) -> void: _hurt = 1.0)
	Events.zone_state.connect(func(p: int, s: String, left: float) -> void: _zone_phase = p; _zone_state = s; _zone_left = left)
	Events.local_character_changed.connect(func(ch: Node) -> void: character = ch)

func bind(p_match: Match, p_rig: CameraRig, p_world: World) -> void:
	match_ref = p_match
	camera_rig = p_rig
	world = p_world
	character = p_match.local_player
	if world and world.layout.preview_path != "":
		preview_tex = load(world.layout.preview_path)
	remain_label.text = str(p_match.alive_count)

# ---------- construction ----------
func _font(base: FontFile, size: int, weight := 400) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = base
	if base == oswald:
		fv.variation_opentype = {2003265652: weight}   # 'wght'
	return fv

func _label(text: String, font: FontVariation, size: int, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _panel(color := PANEL, border_left := Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.content_margin_left = 10; sb.content_margin_right = 10; sb.content_margin_top = 4; sb.content_margin_bottom = 4
	if border_left.a > 0:
		sb.border_width_left = 2
		sb.border_color = border_left
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _place(c: Control, anchor: int, x: float, y: float, w := 0.0, h := 0.0) -> void:
	c.set_anchors_preset(anchor)
	c.position = Vector2(x, y)
	if w > 0:
		c.size = Vector2(w, h)
	root.add_child(c)

func _build() -> void:
	# full-screen effect layers first (drawn under everything)
	vignette = _shader_rect("""
shader_type canvas_item;
uniform float strength = 0.0;
void fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.25, 0.75, length(d)); COLOR = vec4(0.78, 0.06, 0.18, v * strength); }""")
	gasfx = _shader_rect("""
shader_type canvas_item;
uniform float strength = 0.0;
void fragment(){ vec2 d = UV - 0.5; float v = smoothstep(0.2, 0.8, length(d)); COLOR = vec4(0.27, 0.63, 0.24, v * 0.55 * strength + 0.12 * strength); }""")
	scope = _shader_rect("""
shader_type canvas_item;
uniform vec2 aspect = vec2(1.78, 1.0);
void fragment(){ vec2 d = (UV - 0.5) * aspect; float r = length(d); float a = smoothstep(0.42, 0.44, r);
	float cross = (abs(d.x) < 0.0015 || abs(d.y) < 0.0015) && r < 0.42 ? 0.85 : 0.0; COLOR = vec4(0.0, 0.0, 0.0, max(a, cross)); }""")
	scope.visible = false
	# top-left remain
	var remain_box := HBoxContainer.new()
	remain_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	remain_label = _label("150", _font(oswald, 40, 700), 40, RED)
	var remain_word := _label("REMAIN", _font(oswald, 16, 500), 16)
	remain_word.size_flags_vertical = Control.SIZE_SHRINK_END
	remain_box.add_child(remain_label)
	remain_box.add_child(remain_word)
	_place(remain_box, Control.PRESET_TOP_LEFT, 18, 10)
	var hint := _label("[M] Map   [T] First person   [C] Crouch   [H]/[J] Bandage / Medkit   [F] Pick up", _font(barlow, 12), 12, INK_DIM)
	_place(hint, Control.PRESET_TOP_LEFT, 18, 64)
	# compass
	compass = Control.new()
	compass.custom_minimum_size = Vector2(420, 34)
	compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass.draw.connect(_draw_compass)
	_place(compass, Control.PRESET_CENTER_TOP, -210, 10, 420, 34)
	# top-right zone box + feed
	var tr := VBoxContainer.new()
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.alignment = BoxContainer.ALIGNMENT_BEGIN
	zone_box = _panel(Color(0.2, 0.5, 0.2, 0.55))
	var zb := VBoxContainer.new()
	zone_label = _label("", _font(barlow, 16), 16, Color("dfffdf"))
	zone_num = _label("", _font(oswald, 30, 700), 30, Color.WHITE)
	zone_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zb.add_child(zone_label); zb.add_child(zone_num)
	zone_box.add_child(zb)
	zone_box.visible = false
	tr.add_child(zone_box)
	feed = VBoxContainer.new()
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	tr.add_child(feed)
	_place(tr, Control.PRESET_TOP_RIGHT, -360, 10, 342, 400)
	tr.size = Vector2(342, 400)
	tr.position = Vector2(-360, 10)
	# centre banner
	var bp := _panel(Color(0.09, 0.09, 0.11, 0.85))
	banner_label = _label("", _font(barlow_semi, 20), 20)
	bp.add_child(banner_label)
	_place(bp, Control.PRESET_CENTER_TOP, -200, 150, 400, 40)
	bp.name = "BannerPanel"
	bp.modulate.a = 0.0
	# reticle + hitmarker
	reticle = Control.new()
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.draw.connect(_draw_reticle)
	_place(reticle, Control.PRESET_CENTER, -20, -20, 40, 40)
	hitmarker = Control.new()
	hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hitmarker.draw.connect(_draw_hitmarker)
	_place(hitmarker, Control.PRESET_CENTER, -20, -20, 40, 40)
	# prompt
	prompt = _panel(PANEL, RED)
	prompt_label = _label("", _font(barlow, 15), 15)
	prompt.add_child(prompt_label)
	_place(prompt, Control.PRESET_CENTER, -100, 60, 200, 30)
	prompt.visible = false
	# bottom centre: weapon / ammo / hp
	var bc := VBoxContainer.new()
	bc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bc.alignment = BoxContainer.ALIGNMENT_END
	weapon_label = _label("FISTS", _font(oswald, 12, 400), 12, INK_DIM)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ammo_label = _label("", _font(oswald, 30, 700), 30)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bc.add_child(weapon_label); bc.add_child(ammo_label)
	var hp_row := HBoxContainer.new()
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plus := _label("+", _font(oswald, 22, 700), 22)
	bleed_label = _label("BLEEDING", _font(oswald, 11, 500), 11, RED)
	bleed_label.visible = false
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(400, 16)
	hp_bar.show_percentage = false
	hp_bar.max_value = 100
	hp_bar.value = 100
	var bg := StyleBoxFlat.new(); bg.bg_color = Color(0, 0, 0, 0.65); bg.border_width_top = 1; bg.border_width_bottom = 1; bg.border_width_left = 1; bg.border_width_right = 1; bg.border_color = Color(1, 1, 1, 0.18)
	var fg := StyleBoxFlat.new(); fg.bg_color = Color("b8121f")
	hp_bar.add_theme_stylebox_override("background", bg)
	hp_bar.add_theme_stylebox_override("fill", fg)
	hp_num = _label("100", _font(oswald, 18, 600), 18)
	hp_row.add_child(bleed_label); hp_row.add_child(plus); hp_row.add_child(hp_bar); hp_row.add_child(hp_num)
	bc.add_child(hp_row)
	status_label = _label("", _font(barlow, 12), 12, INK_DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bc.add_child(status_label)
	_place(bc, Control.PRESET_CENTER_BOTTOM, -250, -110, 500, 100)
	# gear bottom-left
	gear_label = _label("", _font(oswald, 13, 400), 13, INK_DIM)
	_place(gear_label, Control.PRESET_BOTTOM_LEFT, 18, -70)
	popups = VBoxContainer.new()
	popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popups.alignment = BoxContainer.ALIGNMENT_END
	_place(popups, Control.PRESET_BOTTOM_LEFT, 18, -330, 320, 240)
	# hotbar bottom-right
	hotbar = HBoxContainer.new()
	hotbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hotbar.add_theme_constant_override("separation", 4)
	for i in 6:
		var tile := _panel(PANEL)
		tile.custom_minimum_size = Vector2(60, 46)
		var v := VBoxContainer.new()
		var num := _label(str(i + 1), _font(oswald, 12, 700), 12, RED)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var nm := _label("", _font(oswald, 11, 400), 11, INK_DIM)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(num); v.add_child(nm)
		tile.add_child(v)
		hotbar.add_child(tile)
		hot_tiles.append(tile)
		hot_names.append(nm)
	_place(hotbar, Control.PRESET_BOTTOM_RIGHT, -18 - 6 * 64, -68)
	# map screen
	map_screen = Control.new()
	map_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_screen.visible = false
	map_screen.draw.connect(_draw_map)
	root.add_child(map_screen)

func _shader_rect(code: String) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	var s := Shader.new()
	s.code = code
	m.shader = s
	r.material = m
	root.add_child(r)
	return r

# ---------- events ----------
func _on_kill_feed(killer: String, victim: String, weapon: String, headshot: bool) -> void:
	var p := _panel(PANEL, RED)
	var l := _label("%s  [%s]%s  %s" % [killer, weapon, "  ✦" if headshot else "", victim], _font(barlow, 13), 13)
	p.add_child(l)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	feed.add_child(p)
	feed.move_child(p, 0)
	while feed.get_child_count() > 8:
		feed.get_child(feed.get_child_count() - 1).queue_free()
	get_tree().create_timer(8.0).timeout.connect(func() -> void: if is_instance_valid(p): p.queue_free())

func show_banner(text: String) -> void:
	banner_label.text = text
	_banner_t = 3.5

func show_status(text: String) -> void:
	status_label.text = text
	_status_t = 2.5

func _on_popup(title: String, subtitle: String) -> void:
	var p: PanelContainer
	if title != "":
		p = _panel(Color(0.91, 0.52, 0.17, 0.85))
		var v := VBoxContainer.new()
		v.add_child(_label(title, _font(oswald, 15, 500), 15, Color.WHITE))
		v.add_child(_label(subtitle, _font(oswald, 12, 400), 12, Color("fff5e8")))
		p.add_child(v)
	else:
		p = _panel(PANEL, INK_DIM)
		p.add_child(_label(subtitle, _font(barlow, 13), 13))
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	popups.add_child(p)
	while popups.get_child_count() > 5:
		popups.get_child(0).queue_free()
	get_tree().create_timer(2.6).timeout.connect(func() -> void: if is_instance_valid(p): p.queue_free())

func _on_hit(kind: String, killed: bool) -> void:
	_hit_kind = kind
	_hit_kill = killed
	_hit_alpha = 1.0
	hitmarker.queue_redraw()

# ---------- drawing ----------
func _draw_reticle() -> void:
	if character == null or camera_rig == null:
		return
	if camera_rig.scoped or character.mode == Character.Mode.PARACHUTE or map_open:
		return
	var c := reticle.size * 0.5
	var aiming := camera_rig.aiming
	reticle.draw_circle(c, 2.0 if aiming else 3.0, Color.WHITE)
	if not aiming:
		var def := character.combat.current_def()
		var spread := float(def.get("hipSpreadDeg", 0.0)) * 6.0
		if spread > 0.0:
			reticle.draw_arc(c, 6.0 + spread, 0, TAU, 32, Color(1, 1, 1, 0.5), 1.0)

func _draw_hitmarker() -> void:
	if _hit_alpha <= 0.0:
		return
	var col := Color.WHITE
	match _hit_kind:
		"armor", "armor_break": col = GOLD
		"helmet_pop": col = RED
	if _hit_kill:
		col = RED
	col.a = _hit_alpha
	var c := hitmarker.size * 0.5
	var s := 9.0 + (1.0 - _hit_alpha) * 6.0
	var g := 4.0
	var w := 3.0 if _hit_kill else 2.0
	for d in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		hitmarker.draw_line(c + d * g, c + d * s, col, w)

func _draw_compass() -> void:
	var w := compass.size.x
	compass.draw_rect(Rect2(0, 0, w, 34), Color(0.047, 0.05, 0.063, 0.55))
	if camera_rig == null:
		return
	var heading := fposmod(-rad_to_deg(camera_rig.yaw + camera_rig.free_look_yaw), 360.0)
	var px_per_deg := w / 120.0
	var f := _font(oswald, 18, 500)
	for d in range(-70, 71):
		var deg := int(fposmod(roundf(heading) + d, 360.0))
		var x := w * 0.5 + (d - (heading - roundf(heading))) * px_per_deg
		if deg % 15 == 0:
			compass.draw_rect(Rect2(x - 1, 22, 2, 8), Color(INK, 0.9))
			var lbl := ""
			match deg:
				0: lbl = "N"
				90: lbl = "E"
				180: lbl = "S"
				270: lbl = "W"
				_: lbl = str(deg) if deg % 45 == 0 else ""
			if lbl != "":
				compass.draw_string(f, Vector2(x - 8, 17), lbl, HORIZONTAL_ALIGNMENT_CENTER, 16, 14, INK)
		elif deg % 5 == 0:
			compass.draw_rect(Rect2(x - 0.5, 25, 1, 5), Color(INK, 0.45))
	if match_ref and match_ref.zone and match_ref.zone.phase >= 0 and character:
		var z := match_ref.zone
		var dx := z.next_center.x - character.global_position.x
		var dz := z.next_center.y - character.global_position.z
		var bearing := fposmod(rad_to_deg(atan2(-dx, -dz)) * -1.0, 360.0)
		var rel := fposmod(bearing - heading + 180.0, 360.0) - 180.0
		var x := clampf(w * 0.5 + rel * px_per_deg, 8, w - 8)
		compass.draw_colored_polygon(PackedVector2Array([Vector2(x, 28), Vector2(x - 7, 34), Vector2(x + 7, 34)]), ZONE_GREEN)
		var dist := Vector2(dx, dz).length() - z.next_radius
		if dist > 0:
			compass.draw_string(_font(oswald, 12, 500), Vector2(x - 20, 10), "%dm" % int(dist), HORIZONTAL_ALIGNMENT_CENTER, 40, 11, ZONE_GREEN)
	compass.draw_rect(Rect2(w * 0.5 - 1.5, 20, 3, 14), RED)

func _draw_map() -> void:
	var vs := map_screen.size
	map_screen.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.03, 0.035, 0.9))
	var side := minf(vs.x, vs.y) - 80.0
	var origin := (vs - Vector2(side, side)) * 0.5
	if preview_tex:
		map_screen.draw_texture_rect(preview_tex, Rect2(origin, Vector2(side, side)), false)
	if world == null:
		return
	var half := world.layout.half_size
	var to_px := func(x: float, z: float) -> Vector2: return origin + Vector2((x + half) / (2.0 * half) * side, (z + half) / (2.0 * half) * side)
	var f := _font(oswald, 12, 500)
	for p in world.layout.pois:
		var pt: Vector2 = to_px.call(float(p["x"]), float(p["z"]))
		map_screen.draw_string(f, pt + Vector2(-30, -6), String(p["name"]).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 120, 11, Color(1, 1, 1, 0.85))
	if match_ref and match_ref.zone and match_ref.zone.phase >= 0:
		var z := match_ref.zone
		var scale := side / (2.0 * half)
		map_screen.draw_arc(to_px.call(z.center.x, z.center.y), z.radius * scale, 0, TAU, 96, ZONE_GREEN, 2.0)
		map_screen.draw_arc(to_px.call(z.next_center.x, z.next_center.y), z.next_radius * scale, 0, TAU, 96, Color.WHITE, 1.5)
	if character:
		var pt: Vector2 = to_px.call(character.global_position.x, character.global_position.z)
		var yaw := character.yaw
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		var rgt := Vector2(-fwd.y, fwd.x)
		map_screen.draw_colored_polygon(PackedVector2Array([pt + fwd * 9, pt - fwd * 6 + rgt * 6, pt - fwd * 6 - rgt * 6]), RED)

# ---------- per frame ----------
func _process(dt: float) -> void:
	if character == null or not is_instance_valid(character):
		return
	# health / ammo / weapon
	var h := character.health
	hp_bar.value = h.hp
	hp_num.text = str(ceili(maxf(h.hp, 0.0)))
	bleed_label.visible = h.bleeding
	var def := character.combat.current_def()
	var id := character.inventory.current_id()
	weapon_label.text = String(def.get("name", "Fists")).to_upper()
	if def.has("magSize"):
		ammo_label.text = "%d / %d" % [int(character.inventory.mags.get(id, 0)), int(character.inventory.ammo.get(def["ammo"], 0))]
	else:
		ammo_label.text = "—"
	if character.combat.reload_t > 0.0:
		status_label.text = "Reloading…"
	elif character.heal_timer > 0.0:
		status_label.text = "Using %s…" % character.heal_pending.get("name", "")
	elif character.mode == Character.Mode.PARACHUTE:
		status_label.text = "Parachuting · W dive · S flare · mouse to steer"
	elif _status_t > 0.0:
		_status_t -= dt
	else:
		status_label.text = ""
	var armor_txt := "—"
	if h.has_armor():
		armor_txt = "%s  %d%%" % [ItemCatalog.get_item(h.armor_id).get("name", h.armor_id), int(h.armor_dur / h.armor_max * 100.0)]
	gear_label.text = "HELMET  %s\nARMOR  %s\nBANDAGE [H]  %d    MEDKIT [J]  %d" % [
		ItemCatalog.get_item(h.helmet_id).get("name", "—") if h.has_helmet() else "—", armor_txt,
		int(character.inventory.meds.get("bandage", 0)), int(character.inventory.meds.get("first_aid_kit", 0))]
	for i in hot_tiles.size():
		var tile := hot_tiles[i]
		var nm: Label = hot_names[i]
		var sid: String = character.inventory.slots[i]
		nm.text = String(ItemCatalog.get_item(sid).get("name", "")).replace("12-Gauge ", "").to_upper() if sid != "" else ""
		var sb: StyleBoxFlat = tile.get_theme_stylebox("panel")
		sb.border_width_bottom = 2 if i == character.inventory.cur else 0
		sb.border_color = RED
	# prompt
	var near := character.interaction.nearest
	if near != null and character.mode != Character.Mode.PARACHUTE:
		prompt.visible = true
		prompt_label.text = ("F  Loot " if near.item["kind"] == "bag" else "F  Pick up ") + LootTables.display_name(near.item)
	else:
		prompt.visible = false
	# zone box
	if _zone_state == "reveal":
		zone_box.visible = true
		zone_label.text = "Revealing safe zone in"
	elif _zone_state == "warn":
		zone_box.visible = true
		zone_label.text = "Gas closing in"
	elif _zone_state == "close":
		zone_box.visible = true
		zone_label.text = "Gas closing"
	else:
		zone_box.visible = false
	if match_ref and match_ref.zone:
		zone_num.text = str(ceili(match_ref.zone.seconds_left()))
		var in_gas := match_ref.zone.phase >= 0 and match_ref.zone.is_outside(character.global_position)
		_gas = lerpf(_gas, 1.0 if in_gas else 0.0, 0.1)
		(gasfx.material as ShaderMaterial).set_shader_parameter("strength", _gas)
	# effects
	_hurt = maxf(0.0, _hurt - dt * 4.0)
	(vignette.material as ShaderMaterial).set_shader_parameter("strength", _hurt)
	if _hit_alpha > 0.0:
		_hit_alpha = maxf(0.0, _hit_alpha - dt * 4.0)
		hitmarker.queue_redraw()
	var bp := root.get_node("BannerPanel") as Control
	_banner_t = maxf(0.0, _banner_t - dt)
	bp.modulate.a = clampf(_banner_t * 2.0, 0.0, 1.0)
	if camera_rig:
		scope.visible = camera_rig.scoped
		(scope.material as ShaderMaterial).set_shader_parameter("aspect", Vector2(root.size.x / root.size.y, 1.0))
	compass.queue_redraw()
	reticle.queue_redraw()
	if map_open:
		map_screen.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map"):
		map_open = not map_open
		map_screen.visible = map_open
