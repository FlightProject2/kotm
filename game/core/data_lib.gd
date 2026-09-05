class_name DataLib
extends RefCounted
## Static loader for the tuning JSON under res://design/data. Cached per file.
## Static so tests (godot --script) can use it without autoloads.

static var _cache: Dictionary = {}

static func json(name: String) -> Variant:
	if _cache.has(name):
		return _cache[name]
	var path := "res://design/data/%s.json" % name
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "DataLib: missing data file " + path)
	var data: Variant = JSON.parse_string(f.get_as_text())
	assert(data != null, "DataLib: invalid JSON in " + path)
	_cache[name] = data
	return data

static func weapons() -> Dictionary: return json("weapons")
static func armor() -> Dictionary: return json("armor")
static func gas_phases() -> Dictionary: return json("gas-phases")
static func loot_tables() -> Dictionary: return json("loot-tables")
static func vehicles() -> Dictionary: return json("vehicles")
static func keybinds() -> Dictionary: return json("keybinds")
static func movement() -> Dictionary: return json("movement")
static func preset(id: String) -> Dictionary: return json("presets/" + id)

static func clear_cache() -> void:
	_cache.clear()
