extends SceneTree
## Converts world/terrain/heightmap_2km.f32 (raw float32 from tools/bake_map.py) into the
## compressed Image resource the game loads, plus an EXR for external tools / Terrain3D's importer.
## Run: godot --headless --path . --script res://tools/godot/bake_terrain.gd

const SRC := "res://world/terrain/heightmap_2km.f32"
const RES := "res://world/terrain/heightmap_2km.res"
const EXR := "res://world/terrain/heightmap_2km.exr"
const SIZE := 2048

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		print("BAKE: missing %s (run python3 tools/bake_map.py first)" % SRC)
		quit(1)
		return
	var bytes := f.get_buffer(SIZE * SIZE * 4)
	var img := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RF, bytes)
	var err := ResourceSaver.save(img, RES, ResourceSaver.FLAG_COMPRESS)
	print("BAKE: saved %s (%s)" % [RES, error_string(err)])
	var err2 := img.save_exr(EXR, true)
	print("BAKE: saved %s (%s)" % [EXR, error_string(err2)])
	# round-trip check
	var back: Image = ResourceLoader.load(RES, "Image", ResourceLoader.CACHE_MODE_IGNORE)
	var a := img.get_pixel(1024, 1024).r
	var b := back.get_pixel(1024, 1024).r
	print("BAKE: centre height %.3f roundtrip %.3f size %dx%d" % [a, b, back.get_width(), back.get_height()])
	quit(0 if err == OK and absf(a - b) < 0.001 else 1)
