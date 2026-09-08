class_name Crafting
extends RefCounted
## Authority-owned transactions. Recipes follow the June 2016 BR combat preview.
const RECIPES := {
	"coagulant": {"name": "Blood coagulant", "cost": {"first_aid_kit": 1, "bandage": 10}, "result": "blood_coagulant", "kind": "med"},
	"makeshift_armor": {"name": "Makeshift armour", "cost": {"duct_tape": 1, "military_backpack": 1, "tactical_helmet": 1}, "result": "makeshift_armor", "kind": "armor"},
	"bandage": {"name": "Bandage", "cost": {"cloth": 2}, "result": "bandage", "kind": "med"},
}

static func count(ch: Character, id: String) -> int:
	if id == ch.inventory.backpack_id or id == ch.health.helmet_id:
		return 1
	return int(ch.inventory.materials.get(id, 0)) + int(ch.inventory.meds.get(id, 0))

static func can_make(ch: Character, recipe: String) -> bool:
	if not RECIPES.has(recipe) or not ch.alive() or not ch.is_authority() or ch.in_vehicle() or ch.mode == Character.Mode.PARACHUTE:
		return false
	for id in RECIPES[recipe].cost:
		if count(ch, id) < int(RECIPES[recipe].cost[id]):
			return false
	return true

static func make(ch: Character, recipe: String) -> bool:
	if not can_make(ch, recipe):
		return false
	var spec: Dictionary = RECIPES[recipe]
	for id in spec.cost:
		if id == ch.inventory.backpack_id:
			ch.inventory.backpack_id = ""
		elif id == ch.health.helmet_id:
			ch.health.remove_helmet()
		elif ch.inventory.meds.has(id):
			ch.inventory.meds[id] -= int(spec.cost[id])
		else:
			ch.inventory.materials[id] -= int(spec.cost[id])
	if spec.kind == "med":
		ch.inventory.give_med(spec.result)
	else:
		ch.health.set_armor(spec.result)
	ch.combat.reload_t = 0.0
	ch.combat._clear_fire_buffer()
	ch.inventory.changed.emit()
	return true
