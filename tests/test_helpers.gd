class_name TestDamage
extends RefCounted

static func weapon(id: String) -> Dictionary:
	for w in DataLib.weapons()["weapons"]:
		if w["id"] == id:
			return w
	return {}
