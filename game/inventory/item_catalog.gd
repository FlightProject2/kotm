class_name ItemCatalog
extends RefCounted
## Every item kind in one lookup: id -> {kind, name, weight, ...}. Built from the data JSON.

static var _items: Dictionary = {}

static func all() -> Dictionary:
	if _items.is_empty():
		_build()
	return _items

static func get_item(id: String) -> Dictionary:
	return all().get(id, {})

static func has(id: String) -> bool:
	return all().has(id)

static func _build() -> void:
	var w: Dictionary = DataLib.weapons()
	for e in w["weapons"]:
		_items[e["id"]] = {"kind": "weapon", "name": e["name"], "weight": float(e.get("weight", 40)), "def": e,
			"slots": _slots_for_class(e["class"]), "class": e["class"]}
	for e in w["melee"]:
		_items[e["id"]] = {"kind": "weapon", "name": e["name"], "weight": float(e.get("weight", 10)), "def": e, "slots": [0], "class": "melee"}
	for e in w["throwables"]:
		_items[e["id"]] = {"kind": "throwable", "name": e["name"], "weight": float(e.get("weight", 10)), "def": e, "slots": [5], "class": "throwable"}
	for e in w["ammo"]:
		_items[e["id"]] = {"kind": "ammo", "name": e["name"], "weight": float(e["weightPerStack"]) / float(e["stack"]), "stack": int(e["stack"]), "def": e}
	var a: Dictionary = DataLib.armor()
	for e in a["helmets"]:
		_items[e["id"]] = {"kind": "helmet", "name": e["name"], "weight": float(e.get("weight", 15)), "def": e}
	for e in a["bodyArmor"]:
		_items[e["id"]] = {"kind": "armor", "name": e["name"], "weight": float(e.get("weight", 40)), "def": e}
	for e in a["medical"]:
		_items[e["id"]] = {"kind": "med", "name": e["name"], "weight": float(e.get("weight", 5)), "def": e}
	for e in a["backpacks"]:
		_items[e["id"]] = {"kind": "backpack", "name": e["name"], "weight": 0.0, "capacity": int(e["capacity"]), "def": e}
	for e in a["shoes"]:
		_items[e["id"]] = {"kind": "shoes", "name": e["name"], "weight": 2.0, "def": e}
	for id in ["cloth", "metal_scrap", "metal_sheet", "duct_tape", "ethanol", "gunpowder", "empty_bottle", "rubbing_alcohol", "wood_stick", "gas_can", "vehicle_repair_kit", "airdrop_ticket", "scope2x", "reflex"]:
		_items[id] = {"kind": "material", "name": id.capitalize(), "weight": 4.0 if id != "gas_can" else 40.0}

static func _slots_for_class(cls: String) -> Array:
	match cls:
		"pistol": return [3, 4]
		"melee": return [0]
		"throwable": return [5]
		_: return [1, 2]

static func weapon_def(id: String) -> Dictionary:
	var it := get_item(id)
	return it.get("def", {}) if it.get("kind", "") == "weapon" else {}
