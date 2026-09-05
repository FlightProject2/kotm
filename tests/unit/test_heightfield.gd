extends TestCase

var hf: HeightField
var layout: MapLayout

func _setup() -> void:
	if hf == null:
		hf = HeightField.load_from("res://world/terrain/heightmap_2km.res")
		layout = MapLayout.load_default()

func test_loads_and_ranges() -> void:
	_setup()
	assert_true(hf != null, "heightmap resource loads")
	assert_eq(hf.size, 2048)
	assert_near(hf.half, 1024.0)
	var lo := INF
	var hi := -INF
	for i in 400:
		var h := hf.height_at(randf_range(-1000, 1000), randf_range(-1000, 1000))
		lo = minf(lo, h); hi = maxf(hi, h)
	assert_between(lo, 4.0, 60.0, "lowland exists")
	assert_between(hf.height_at(0, 0), 150.0, 175.0, "the Mountain peak")

func test_bilinear_matches_raw_on_integers() -> void:
	_setup()
	for i in 50:
		var px := randi_range(1, 2046)
		var pz := randi_range(1, 2046)
		assert_near(hf.height_at(px - 1024, pz - 1024), hf.raw(px, pz), 0.0005)

func test_pads_are_flat() -> void:
	_setup()
	var town := layout.poi("ashford")
	var h0 := layout.pad_height("ashford")
	assert_false(is_nan(h0))
	for i in 40:
		var a := randf() * TAU
		var r := randf() * float(town["padRadius"]) * 0.9
		var h := hf.height_at(town["x"] + cos(a) * r, town["z"] + sin(a) * r)
		assert_near(h, h0, 0.05, "Ashford pad flat")
	assert_true(hf.slope_deg_at(town["x"], town["z"]) < 1.0)

func test_slope_and_normal() -> void:
	_setup()
	var n := hf.normal_at(200, 200)
	assert_near(n.length(), 1.0, 0.001)
	assert_true(hf.slope_deg_at(0, 260) > 3.0, "mountain flank has slope")

func test_segment_hit() -> void:
	_setup()
	var top := Vector3(0, hf.height_at(0, 0) + 5.0, 0)
	assert_eq(hf.segment_hit(top, top + Vector3(0, 10, 0)), -1.0, "upwards ray clears")
	var t := hf.segment_hit(top, top + Vector3(0, -20, 0))
	assert_between(t, 0.2, 0.35, "downward ray hits near t = 0.25")

func test_layout_contents() -> void:
	_setup()
	assert_eq(layout.id, "slice_2km")
	assert_true(layout.buildings.size() >= 80)
	assert_true(layout.trees.size() > 5000)
	assert_true(layout.roads.size() >= 10)
	var b: Dictionary = layout.buildings[0]
	assert_false(is_nan(layout.building_base_height(b)), "building has a base height")
	var d := layout.nearest_road(450.0, 0.0)
	assert_true(d[0] < 1.0, "ring road passes through (450, 0)")
