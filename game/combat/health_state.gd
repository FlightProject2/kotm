class_name HealthState
extends RefCounted
## Pure health + protective gear state (docs/game-plan/06). No nodes, so it is testable
## and can be serialised for the network later.

var hp: float = 100.0
var alive: bool = true
var bleeding: bool = false
var helmet_id: String = ""      # "" = none
var helmet_take: float = 1.0    # fraction of head damage the wearer takes while the helmet absorbs
var armor_id: String = ""
var armor_absorb: float = 0.0
var armor_dur: float = 0.0
var armor_max: float = 0.0
var shoes_id: String = "conveys"
## Shot id that popped the helmet: other pellets of the same shot still get the reduction.
var helmet_popped_by_shot: int = -1
var helmet_popped_take: float = 1.0

static func _gear(list_name: String, id: String) -> Dictionary:
	for g in DataLib.armor()[list_name]:
		if g["id"] == id:
			return g
	return {}

func set_helmet(id: String) -> bool:
	var g := _gear("helmets", id)
	if g.is_empty():
		return false
	helmet_id = id
	helmet_take = float(g["wearerTakesFraction"])
	helmet_popped_by_shot = -1
	return true

func remove_helmet() -> void:
	helmet_popped_take = helmet_take
	helmet_id = ""
	helmet_take = 1.0

func has_helmet() -> bool:
	return helmet_id != ""

func set_armor(id: String) -> bool:
	var g := _gear("bodyArmor", id)
	if g.is_empty():
		return false
	armor_id = id
	armor_absorb = float(g["absorbFraction"])
	armor_dur = float(g["durability"])
	armor_max = armor_dur
	return true

func remove_armor() -> void:
	armor_id = ""
	armor_absorb = 0.0
	armor_dur = 0.0
	armor_max = 0.0

func has_armor() -> bool:
	return armor_id != "" and armor_dur > 0.0

func shoes() -> Dictionary:
	var g := _gear("shoes", shoes_id)
	return g if not g.is_empty() else _gear("shoes", "conveys")

func apply_damage(amount: float) -> bool:
	if not alive:
		return false
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		alive = false
		return true
	return false

func heal(amount: float) -> void:
	if alive:
		hp = minf(100.0, hp + amount)

func to_dict() -> Dictionary:
	return {"hp": hp, "alive": alive, "bleeding": bleeding, "helmet": helmet_id, "armor": armor_id,
		"armor_dur": armor_dur, "shoes": shoes_id}

func duplicate_state() -> HealthState:
	var s := HealthState.new()
	s.hp = hp; s.alive = alive; s.bleeding = bleeding
	s.helmet_id = helmet_id; s.helmet_take = helmet_take
	s.armor_id = armor_id; s.armor_absorb = armor_absorb; s.armor_dur = armor_dur; s.armor_max = armor_max
	s.shoes_id = shoes_id; s.helmet_popped_by_shot = helmet_popped_by_shot; s.helmet_popped_take = helmet_popped_take
	return s
