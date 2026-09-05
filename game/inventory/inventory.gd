class_name Inventory
extends RefCounted
## Weight-based inventory with a 6-slot loadout (docs/game-plan/07). Pure data; authority-owned.

signal changed

var slots: Array[String] = ["fists", "", "", "", "", ""]
var cur: int = 0
var mags: Dictionary = {}           # weapon id -> rounds in the magazine
var ammo: Dictionary = {}           # ammo id -> reserve count
var meds: Dictionary = {"bandage": 0, "field_bandage": 0, "first_aid_kit": 0}
var throwables: Dictionary = {}
var materials: Dictionary = {}
var backpack_id: String = ""

func _init() -> void:
	for a in DataLib.weapons()["ammo"]:
		ammo[a["id"]] = 0

func capacity() -> int:
	if backpack_id == "":
		return int(DataLib.armor()["backpacks"][0]["capacity"])
	return int(ItemCatalog.get_item(backpack_id).get("capacity", 400))

func weight() -> float:
	var w := 0.0
	for s in slots:
		if s != "" and s != "fists":
			w += float(ItemCatalog.get_item(s).get("weight", 0))
	for id in ammo:
		w += ammo[id] * float(ItemCatalog.get_item(id).get("weight", 0))
	for id in meds:
		w += meds[id] * float(ItemCatalog.get_item(id).get("weight", 0))
	for id in throwables:
		w += throwables[id] * float(ItemCatalog.get_item(id).get("weight", 0))
	for id in materials:
		w += materials[id] * float(ItemCatalog.get_item(id).get("weight", 0))
	return w

func over_capacity() -> bool:
	return weight() > capacity()

func current_id() -> String:
	return slots[cur]

func current_def() -> Dictionary:
	return ItemCatalog.get_item(current_id()).get("def", {})

func has_weapon(id: String) -> bool:
	return slots.has(id)

## Adds a weapon into a free slot of its class, else swaps the current/first slot of that class.
## Returns the id that was displaced ("" if none).
func give_weapon(id: String) -> String:
	var it := ItemCatalog.get_item(id)
	if it.is_empty() or it["kind"] != "weapon":
		return ""
	if has_weapon(id):
		return ""
	var wanted: Array = it["slots"]
	var target := -1
	for s in wanted:
		if slots[s] == "":
			target = s
			break
	var displaced := ""
	if target == -1:
		target = cur if wanted.has(cur) else wanted[0]
		displaced = slots[target]
	slots[target] = id
	if not mags.has(id):
		var d: Dictionary = it.get("def", {})
		mags[id] = int(d.get("magSize", 0))
	if cur == 0 or target == cur or slots[cur] == "":
		cur = target
	changed.emit()
	return displaced

func remove_weapon(id: String) -> void:
	var i := slots.find(id)
	if i > 0:
		slots[i] = ""
		if cur == i:
			cur = 0
		changed.emit()

func give_ammo(id: String, qty: int) -> void:
	ammo[id] = int(ammo.get(id, 0)) + qty
	changed.emit()

func give_med(id: String, qty := 1) -> void:
	meds[id] = int(meds.get(id, 0)) + qty
	changed.emit()

func give_throwable(id: String, qty := 1) -> void:
	throwables[id] = int(throwables.get(id, 0)) + qty
	if slots[5] == "":
		slots[5] = id
	changed.emit()

func give_material(id: String, qty := 1) -> void:
	materials[id] = int(materials.get(id, 0)) + qty
	changed.emit()

func select(slot: int) -> bool:
	if slot < 0 or slot >= slots.size() or slots[slot] == "":
		return false
	cur = slot
	changed.emit()
	return true

## Everything as loot entries (for death bags).
func dump() -> Array:
	var out: Array = []
	for s in slots:
		if s != "" and s != "fists":
			out.append({"kind": "weapon", "id": s})
	for id in ammo:
		if ammo[id] > 0:
			out.append({"kind": "ammo", "id": id, "qty": ammo[id]})
	for id in meds:
		if meds[id] > 0:
			out.append({"kind": "med", "id": id, "qty": meds[id]})
	for id in throwables:
		if throwables[id] > 0:
			out.append({"kind": "throwable", "id": id, "qty": throwables[id]})
	if backpack_id != "":
		out.append({"kind": "backpack", "id": backpack_id})
	return out
