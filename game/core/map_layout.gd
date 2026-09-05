class_name MapLayout
extends RefCounted
## The authored map: POIs, buildings, roads, baked tree list and pad heights (design/map/*.json).

var id: String
var seed: int
var half_size: float
var vertex_spacing: float = 1.0
var region_size: int = 512
var heightmap_path: String
var colormap_path: String
var preview_path: String
var pois: Array = []
var buildings: Array = []
var roads: Array = []
var pads: Array = []
var trees: Array = []
var spawn_max_height: float = 110.0

static func load_from(path: String) -> MapLayout:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MapLayout: missing " + path)
		return null
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var m := MapLayout.new()
	m.id = d["id"]
	m.seed = int(d["seed"])
	m.half_size = float(d["halfSizeM"])
	m.vertex_spacing = float(d.get("vertexSpacing", 1.0))
	m.region_size = int(d.get("regionSize", 512))
	m.heightmap_path = d["heightmap"]
	m.colormap_path = d.get("colormap", "")
	m.preview_path = d.get("preview", "")
	m.pois = d["pois"]
	m.buildings = d["buildings"]
	m.roads = d["roads"]
	m.spawn_max_height = float(d.get("spawnMaxHeightM", 110.0))
	var pf := FileAccess.open(d["pads"], FileAccess.READ)
	if pf:
		m.pads = JSON.parse_string(pf.get_as_text())["pads"]
	var tf := FileAccess.open(d["trees"], FileAccess.READ)
	if tf:
		m.trees = JSON.parse_string(tf.get_as_text())["trees"]
	return m

static func load_default() -> MapLayout:
	return load_from("res://design/map/slice_2km.json")

func poi(poi_id: String) -> Dictionary:
	for p in pois:
		if p["id"] == poi_id:
			return p
	return {}

func pad_height(pad_id: String) -> float:
	for p in pads:
		if p["id"] == pad_id:
			return float(p["height"])
	return NAN

## Height a building should sit at: its POI pad, else the pad baked at its own position, else NAN.
func building_base_height(b: Dictionary) -> float:
	if b.get("poi", "") != "":
		var h := pad_height(b["poi"])
		if not is_nan(h):
			return h
	var bx := float(b["x"])
	var bz := float(b["z"])
	for p in pads:
		if absf(float(p["x"]) - bx) < 1.5 and absf(float(p["z"]) - bz) < 1.5:
			return float(p["height"])
	return NAN

## Distance from a point to the nearest road centreline (metres), and that road's width.
func nearest_road(x: float, z: float) -> Array:
	var best := INF
	var width := 0.0
	for r in roads:
		var pts: Array = r["points"]
		for i in range(pts.size() - 1):
			var a := Vector2(pts[i][0], pts[i][1])
			var b := Vector2(pts[i + 1][0], pts[i + 1][1])
			var p := Vector2(x, z)
			var ab := b - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			var d := p.distance_to(a + ab * t)
			if d < best:
				best = d
				width = float(r["width"])
	return [best, width]
