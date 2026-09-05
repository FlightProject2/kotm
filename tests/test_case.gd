class_name TestCase
extends RefCounted
## Minimal test base. Methods named test_* run in order; scene tests may await tree frames.

var tree: SceneTree
var _passed := 0
var _failed := 0
var _current := ""

func run_all(t: SceneTree) -> Array:
	tree = t
	var script_name: String = get_script().resource_path.get_file()
	for m in get_method_list():
		var mname: String = m.name
		if not mname.begins_with("test_"):
			continue
		_current = mname
		var before := _failed
		await call(mname)
		var ok := _failed == before
		if ok:
			_passed += 1
		print("  %s  %s.%s" % ["PASS" if ok else "FAIL", script_name, mname])
	return [_passed, _failed]

func fail(msg: String) -> void:
	_failed += 1
	push_error("[%s] %s" % [_current, msg])

func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		fail("expected true. " + msg)

func assert_false(cond: bool, msg := "") -> void:
	if cond:
		fail("expected false. " + msg)

func assert_eq(a, b, msg := "") -> void:
	if a != b:
		fail("expected %s == %s. %s" % [str(a), str(b), msg])

func assert_near(a: float, b: float, eps := 1e-4, msg := "") -> void:
	if absf(a - b) > eps:
		fail("expected %s ~= %s (eps %s). %s" % [a, b, eps, msg])

func assert_between(v: float, lo: float, hi: float, msg := "") -> void:
	if v < lo or v > hi:
		fail("expected %s in [%s, %s]. %s" % [v, lo, hi, msg])

## Adds a node under the root and waits for two physics frames so bodies settle.
func add_to_tree(node: Node) -> void:
	tree.root.add_child(node)
	await tree.physics_frame
	await tree.physics_frame

func settle(frames := 2) -> void:
	for i in frames:
		await tree.physics_frame
