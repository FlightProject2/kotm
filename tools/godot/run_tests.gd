extends SceneTree
## Headless test runner: godot --headless --path . --script res://tools/godot/run_tests.gd [-- --filter=name]

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var files: Array[String] = []
	_collect("res://tests", files)
	files.sort()
	var passed := 0
	var failed := 0
	for f in files:
		if filter != "" and not f.contains(filter):
			continue
		var script: GDScript = load(f)
		if script == null:
			push_error("cannot load test script " + f)
			failed += 1
			continue
		var t = script.new()
		if not (t is TestCase):
			continue
		var r: Array = await t.run_all(self)
		passed += r[0]
		failed += r[1]
	print("TESTS: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)

func _collect(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir():
			_collect(dir + "/" + n, out)
		elif n.begins_with("test_") and n.ends_with(".gd"):
			out.append(dir + "/" + n)
		n = d.get_next()
