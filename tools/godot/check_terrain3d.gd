extends SceneTree
## Probes whether the Terrain3D GDExtension loads and works headless.
## Prints HEADLESS_TERRAIN3D=ok|fail so CI can pick the terrain backend default.

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	if not ClassDB.class_exists("Terrain3D"):
		print("HEADLESS_TERRAIN3D=fail (class missing)")
		quit(1)
		return
	var terrain: Node = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
	root.add_child(terrain)
	await process_frame
	var img := Image.create_empty(256, 256, false, Image.FORMAT_RF)
	for y in 256:
		for x in 256:
			img.set_pixel(x, y, Color(float(x) / 255.0, 0, 0, 1))
	terrain.region_size = 256
	terrain.data.import_images([img, null, null], Vector3(0, 0, 0), 0.0, 100.0)
	await process_frame
	var h: float = terrain.data.get_height(Vector3(128.0, 0, 128.0))
	print("probe height at x=128: %s (expected ~50.2)" % h)
	if is_nan(h) or absf(h - 50.2) > 2.0:
		print("HEADLESS_TERRAIN3D=fail (height probe)")
		quit(1)
		return
	print("HEADLESS_TERRAIN3D=ok")
	quit(0)
