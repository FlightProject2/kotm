class_name CharacterInteraction
extends Node
## Picking up loot and looting bags (docs 07). Shared by players (F key) and bots.

const REACH := 2.2

var c: Character
var registry: LootRegistry
var nearest: LootRegistry.Entry

func _ready() -> void:
	c = get_parent() as Character

## Called by Character during its physics step (before prev_input is updated).
func tick() -> void:
	if registry == null and c.world:
		registry = c.world.loot_registry
	if registry == null or not c.alive():
		nearest = null
		return
	nearest = registry.nearest(c.global_position, REACH)
	if c.input.pressed(CharacterInput.B_INTERACT) and not c.prev_input.pressed(CharacterInput.B_INTERACT):
		if nearest and c.mode != Character.Mode.PARACHUTE:
			take(nearest)

## Applies a loot entry to the character's inventory and removes it from the ground.
func take(e: LootRegistry.Entry) -> bool:
	if registry == null or not registry.entries.has(e.id):
		return false
	var item := e.item
	var pos := e.pos
	registry.remove(e.id)
	if item["kind"] == "bag":
		for it in item.get("items", []):
			_apply(it, pos)
		if c.is_local():
			Events.popup.emit("", "Looted %s's bag" % item.get("owner", "someone"))
	else:
		_apply(item, pos)
		if c.is_local():
			Events.popup.emit("", "Picked up " + LootTables.display_name(item))
	Events.loot_removed.emit(e.id)
	c.inventory.changed.emit()
	return true

func _apply(item: Dictionary, pos: Vector3) -> void:
	var inv := c.inventory
	match item["kind"]:
		"weapon":
			if inv.has_weapon(item["id"]):
				var d: Dictionary = ItemCatalog.weapon_def(item["id"])
				if not d.is_empty() and d.has("ammo"):
					inv.give_ammo(d["ammo"], int(d.get("magSize", 10)))
			else:
				var displaced := inv.give_weapon(item["id"])
				if displaced != "":
					registry.add({"kind": "weapon", "id": displaced}, pos + Vector3(0.6, 0, 0.3))
		"ammo": inv.give_ammo(item["id"], int(item.get("qty", 1)))
		"med": inv.give_med(item["id"], int(item.get("qty", 1)))
		"throwable": inv.give_throwable(item["id"], int(item.get("qty", 1)))
		"material": inv.give_material(item["id"], int(item.get("qty", 1)))
		"helmet":
			if c.health.has_helmet():
				registry.add({"kind": "helmet", "id": c.health.helmet_id}, pos + Vector3(-0.6, 0, 0.3))
			c.health.set_helmet(item["id"])
		"armor":
			if c.health.has_armor():
				registry.add({"kind": "armor", "id": c.health.armor_id}, pos + Vector3(-0.6, 0, -0.3))
			c.health.set_armor(item["id"])
		"backpack":
			if inv.backpack_id != "":
				registry.add({"kind": "backpack", "id": inv.backpack_id}, pos + Vector3(0.3, 0, -0.6))
			inv.backpack_id = item["id"]

## Death bag with everything the character carried.
static func drop_bag(ch: Character, registry: LootRegistry) -> void:
	var items: Array = ch.inventory.dump()
	if ch.health.has_helmet():
		items.append({"kind": "helmet", "id": ch.health.helmet_id})
	if ch.health.has_armor():
		items.append({"kind": "armor", "id": ch.health.armor_id})
	if items.is_empty():
		return
	var p := ch.global_position
	registry.add({"kind": "bag", "owner": ch.display_name, "items": items}, Vector3(p.x, ch.world.height_at(p.x, p.z) if ch.world else p.y, p.z))
