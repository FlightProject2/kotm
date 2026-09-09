class_name MapLayoutOverlay
extends Control
## An in-engine survey of the same authored layout used by World.

const PAGE := Vector2(1600.0, 900.0)
const BACKGROUND := Color("0b1520")
const PANEL := Color("101e2b")
const PAPER := Color("edf2f3")
const MUTED := Color("8da4b5")
const CYAN := Color("89d3e2")
const AMBER := Color("f1bb70")
const MAP_RECT := Rect2(740.0, 118.0, 720.0, 720.0)

var _world: World
var _preview: Texture2D
var _road_km := 0.0

func _init() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func setup(world: World) -> void:
	_world = world
	_preview = null
	_road_km = 0.0
	if _world != null and _world.layout != null:
		var layout := _world.layout
		if not layout.preview_path.is_empty() and ResourceLoader.exists(layout.preview_path):
			_preview = load(layout.preview_path) as Texture2D
		for road: Dictionary in layout.roads:
			var points: Array = road.get("points", [])
			for index in range(1, points.size()):
				_road_km += Vector2(float(points[index - 1][0]), float(points[index - 1][1])).distance_to(Vector2(float(points[index][0]), float(points[index][1]))) / 1000.0
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BACKGROUND)
	if _world == null or _world.layout == null:
		return
	var page_scale := minf(size.x / PAGE.x, size.y / PAGE.y)
	var page_offset := (size - PAGE * page_scale) * 0.5
	draw_set_transform(page_offset, 0.0, Vector2.ONE * page_scale)
	var layout := _world.layout
	_text(Vector2(64, 56), "KOTM / WINTER VALLEY — LAYOUT 02", 26, PAPER)
	_text(Vector2(64, 89), "SNOW BASIN  /  TERRAIN & CONNECTIONS", 18, MUTED)
	_text(Vector2(1290, 56), "M  /  CLOSE MAP", 18, CYAN)
	draw_line(Vector2(64, 103), Vector2(1536, 103), Color("283b4c"), 1.0)

	# Compact metrics describe the authored map, never a separate mock-up.
	_stat(Vector2(64, 145), "%.2f KM" % (layout.half_size * 2.0 / 1000.0), "MAP WIDTH")
	_stat(Vector2(280, 145), "%02d" % layout.pois.size(), "LOCATIONS")
	_stat(Vector2(466, 145), "%.1f KM" % _road_km, "ROUTE NETWORK")
	draw_line(Vector2(64, 196), Vector2(668, 196), Color("283b4c"), 1.0)
	_text(Vector2(64, 229), "LOCATION INDEX", 18, MUTED)
	var row_height := minf(59.0, 476.0 / maxf(float(layout.pois.size()), 1.0))
	for index in range(layout.pois.size()):
		var poi: Dictionary = layout.pois[index]
		var y := 260.0 + float(index) * row_height
		_pin(Vector2(80, y + 7), index + 1, 15.0)
		_text(Vector2(112, y + 14), str(poi.get("name", poi.get("id", "Location"))), 21, PAPER)
		_text(Vector2(510, y + 13), str(poi.get("type", "location")).replace("_", " ").to_upper(), 14, MUTED)
	_draw_key()

	draw_rect(MAP_RECT.grow(5.0), Color("283b4c"))
	draw_rect(MAP_RECT, PANEL)
	if _preview != null:
		draw_texture_rect(_preview, MAP_RECT, false)
	_draw_grid()
	_draw_roads(layout)
	_draw_bridges(layout)
	# Numbers link directly to the index without long labels obscuring terrain.
	var placed: Array[Vector2] = []
	for index in range(layout.pois.size()):
		var poi: Dictionary = layout.pois[index]
		var anchor := _point(float(poi.get("x", 0.0)), float(poi.get("z", 0.0)))
		var marker := anchor
		for previous: Vector2 in placed:
			if marker.distance_to(previous) < 31.0:
				marker = previous + Vector2(0, 34)
		marker = marker.clamp(MAP_RECT.position + Vector2.ONE * 15.0, MAP_RECT.end - Vector2.ONE * 15.0)
		if not marker.is_equal_approx(anchor):
			draw_line(anchor, marker, PAPER, 1.0, true)
		placed.append(marker)
		_pin(marker, index + 1, 13.0)
	_draw_compass()
	_draw_scale(layout)
	_text(Vector2(740, 875), "AUTHORED TERRAIN  /  NORTH UP", 18, MUTED)
	draw_set_transform(Vector2.ZERO)

func _text(position: Vector2, value: String, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _stat(position: Vector2, value: String, caption: String) -> void:
	_text(position, value, 26, PAPER)
	_text(position + Vector2(0, 29), caption, 18, MUTED)

func _point(x: float, z: float) -> Vector2:
	var extent := _world.layout.half_size
	return MAP_RECT.position + Vector2((x + extent) / (extent * 2.0), (z + extent) / (extent * 2.0)) * MAP_RECT.size

func _draw_grid() -> void:
	var grid := Color(0.05, 0.12, 0.18, 0.14)
	for index in range(1, 8):
		var offset := MAP_RECT.size.x * float(index) / 8.0
		draw_line(MAP_RECT.position + Vector2(offset, 0), MAP_RECT.position + Vector2(offset, MAP_RECT.size.y), grid, 1.0)
		draw_line(MAP_RECT.position + Vector2(0, offset), MAP_RECT.position + Vector2(MAP_RECT.size.x, offset), grid, 1.0)

func _draw_roads(layout: MapLayout) -> void:
	for road: Dictionary in layout.roads:
		var points := PackedVector2Array()
		for point: Array in road.get("points", []):
			points.append(_point(float(point[0]), float(point[1])))
		if points.size() < 2:
			continue
		var road_type := str(road.get("type", "asphalt"))
		if road_type == "rail":
			draw_polyline(points, Color("435660"), 1.7, true)
			for index in range(1, points.size(), 11):
				var across := (points[index] - points[index - 1]).normalized().orthogonal() * 2.5
				draw_line(points[index] - across, points[index] + across, Color("435660"), 1.0, true)
			continue
		var footpath := road_type in ["trail", "footpath", "path"]
		var paved := road_type == "asphalt"
		var width := 1.0 if footpath else (2.3 if paved else 1.5)
		var color := Color(0.91, 0.94, 0.90, 0.82) if footpath else (Color(0.35, 0.78, 0.85, 0.86) if paved else Color(0.68, 0.79, 0.77, 0.82))
		draw_polyline(points, Color(0.02, 0.10, 0.16, 0.52), width + 1.6, true)
		draw_polyline(points, color, width, true)

func _draw_bridges(layout: MapLayout) -> void:
	for bridge: Dictionary in layout.bridges:
		if not bridge.has("ax") or not bridge.has("bx") or not bridge.has("az") or not bridge.has("bz"):
			continue
		var start := _point(float(bridge["ax"]), float(bridge["az"]))
		var finish := _point(float(bridge["bx"]), float(bridge["bz"]))
		var across := (finish - start).normalized().orthogonal() * 5.0
		draw_line(start, finish, BACKGROUND, 6.0, true)
		draw_line(start, finish, AMBER, 3.0, true)
		draw_line(start - across, start + across, AMBER, 2.0, true)
		draw_line(finish - across, finish + across, AMBER, 2.0, true)

func _pin(position: Vector2, number: int, radius: float) -> void:
	draw_circle(position + Vector2(0, 2), radius + 2.0, Color(0, 0, 0, 0.3))
	draw_circle(position, radius, BACKGROUND)
	draw_arc(position, radius, 0, TAU, 40, CYAN, 1.5, true)
	var value := str(number)
	var text_width := ThemeDB.fallback_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18).x
	_text(position + Vector2(-text_width * 0.5, 6.0), value, 18, PAPER)

func _draw_key() -> void:
	draw_line(Vector2(64, 757), Vector2(668, 757), Color("283b4c"), 1.0)
	_text(Vector2(64, 787), "CONNECTIONS", 18, MUTED)
	draw_line(Vector2(64, 813), Vector2(102, 813), CYAN, 3.0)
	_text(Vector2(115, 819), "Paved road", 18, PAPER)
	draw_line(Vector2(336, 813), Vector2(374, 813), Color("b5cac4"), 1.5)
	_text(Vector2(386, 819), "Track / footpath", 18, PAPER)
	draw_line(Vector2(64, 849), Vector2(102, 849), AMBER, 3.0)
	draw_line(Vector2(64, 844), Vector2(64, 854), AMBER, 2.0)
	draw_line(Vector2(102, 844), Vector2(102, 854), AMBER, 2.0)
	_text(Vector2(115, 855), "Bridge", 18, PAPER)
	draw_line(Vector2(336, 849), Vector2(374, 849), MUTED, 1.7)
	for x in [340, 351, 362, 373]:
		draw_line(Vector2(x, 845), Vector2(x, 853), MUTED, 1.0)
	_text(Vector2(386, 855), "Rail corridor", 18, PAPER)

func _draw_compass() -> void:
	var center := Vector2(1504, 162)
	_text(center + Vector2(-7, -15), "N", 20, PAPER)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -5), center + Vector2(-8, 17), center + Vector2(0, 12)]), PAPER)
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -5), center + Vector2(8, 17), center + Vector2(0, 12)]), MUTED)

func _draw_scale(layout: MapLayout) -> void:
	var length := 200.0 / (layout.half_size * 2.0) * MAP_RECT.size.x
	var start := Vector2(1320, 865)
	draw_line(start, start + Vector2(length, 0), PAPER, 2.0)
	draw_line(start - Vector2(0, 5), start + Vector2(0, 5), PAPER, 2.0)
	draw_line(start + Vector2(length, -5), start + Vector2(length, 5), PAPER, 2.0)
	_text(start + Vector2(length + 10, 6), "200 m", 18, PAPER)
