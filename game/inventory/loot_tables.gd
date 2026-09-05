class_name LootTables
extends RefCounted
## Seeded loot rolls from design/data/loot-tables.json. Resolves alias ids
## (ammo_9mm, rifle_random, helmet_random, ...) into concrete item entries.

static func node_classes() -> Dictionary:
	return DataLib.loot_tables()["nodeClasses"]

## Returns an Array of item entries {kind, id, qty} for one loot node of [cls].
static func roll_node(cls: String, rng: RandomNumberGenerator) -> Array:
	var nc: Dictionary = node_classes().get(cls, {})
	if nc.is_empty():
		return []
	var out: Array = []
	if nc.has("fixed"):
		for f in nc["fixed"]:
			out.append_array(resolve(f, rng))
		return out
	for g in nc.get("guarantees", []):
		out.append_array(resolve(g, rng))
	if rng.randf() < float(nc.get("emptyChance", 0.0)):
		return out
	var n := rng.randi_range(int(nc.get("itemsMin", 0)), int(nc.get("itemsMax", 1)))
	var rolls: Dictionary = nc.get("rolls", {})
	var keys: Array = rolls.keys()
	var total := 0.0
	for k in keys:
		total += float(rolls[k])
	for i in n:
		var r := rng.randf() * total
		var acc := 0.0
		for k in keys:
			acc += float(rolls[k])
			if r <= acc:
				out.append_array(resolve(k, rng))
				break
	return out

static func _pick(list: Array, rng: RandomNumberGenerator) -> String:
	return list[rng.randi_range(0, list.size() - 1)]

## Alias -> concrete entries. Unknown or cosmetic ids resolve to nothing.
static func resolve(id: String, rng: RandomNumberGenerator) -> Array:
	match id:
		"rifle_random": return [{"kind": "weapon", "id": _pick(["ar15", "ar15", "ak47"], rng)}]
		"weapon_random_common": return [{"kind": "weapon", "id": _pick(["r380", "m9", "m1911", "shotgun_12g"], rng)}]
		"helmet_random": return [{"kind": "helmet", "id": _pick(["motorcycle_helmet", "motorcycle_helmet", "tactical_helmet"], rng)}]
		"ammo_random": return resolve("ammo_" + _pick(["223", "762", "9mm", "45acp", "shells"], rng), rng)
		"rare_random": return [{"kind": "weapon", "id": _pick(["magnum44", "hunting_rifle"], rng)}]
		"ammo_for_each":
			var out: Array = []
			for a in ["223", "762", "308"]:
				out.append_array(resolve("ammo_" + a, rng))
			return out
		"clothing_cosmetic", "shoes_random", "scope2x", "reflex", "ethanol", "empty_bottle", "rubbing_alcohol", "wood_stick", "gunpowder", "gas_can", "vehicle_repair_kit", "airdrop_ticket":
			return []
		"first_aid_kit x2": return [{"kind": "med", "id": "first_aid_kit", "qty": 2}]
	if id.begins_with("ammo_"):
		var aid := id.substr(5)
		var it := ItemCatalog.get_item(aid)
		if it.is_empty():
			return []
		return [{"kind": "ammo", "id": aid, "qty": int(it.get("stack", 10))}]
	var it := ItemCatalog.get_item(id)
	if it.is_empty():
		return []
	match it["kind"]:
		"weapon": return [{"kind": "weapon", "id": id}]
		"helmet": return [{"kind": "helmet", "id": id}]
		"armor": return [{"kind": "armor", "id": id}]
		"med": return [{"kind": "med", "id": id, "qty": 1}]
		"throwable": return [{"kind": "throwable", "id": id, "qty": 1}]
		"backpack": return [{"kind": "backpack", "id": id}]
		"material": return [{"kind": "material", "id": id, "qty": 1}]
	return []

static func display_name(entry: Dictionary) -> String:
	match entry["kind"]:
		"bag": return "%s's bag" % entry.get("owner", "someone")
		"ammo": return "%s x%d" % [ItemCatalog.get_item(entry["id"]).get("name", entry["id"]), int(entry.get("qty", 1))]
		_:
			var n: String = ItemCatalog.get_item(entry["id"]).get("name", entry["id"])
			return n if int(entry.get("qty", 1)) <= 1 else "%s x%d" % [n, int(entry["qty"])]
