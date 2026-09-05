class_name LootSpawner
extends RefCounted
## Seeded initial loot: a few rolls around every building (by its node class) and scattered
## field loot. Identical on every peer for the same seed.

static func generate(world: World, registry: LootRegistry, rng: RandomNumberGenerator, preset: Dictionary) -> Dictionary:
	var layout := world.layout
	var n := 0
	var from_buildings := 0
	if not world.loot_nodes.is_empty():
		# Prefab loot markers (inside and beside buildings), rolled by the building's class.
		for ln in world.loot_nodes:
			for item in LootTables.roll_node(ln["class"], rng):
				var p: Vector3 = ln["pos"]
				registry.add(item, p + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4)))
				n += 1
	for b in layout.buildings:
		var cls: String = b.get("nodeClass", "residential")
		var base := layout.building_base_height(b)
		var nodes := 2 if cls in ["police", "military", "industrial", "commercial"] else 1
		for k in nodes:
			for item in LootTables.roll_node(cls, rng):
				var ang := rng.randf() * TAU
				var r := rng.randf_range(6.0, 11.0)
				var x: float = b["x"] + cos(ang) * r
				var z: float = b["z"] + sin(ang) * r
				var y := base if not is_nan(base) else world.height_at(x, z)
				registry.add(item, Vector3(x, maxf(y, world.height_at(x, z)), z))
				n += 1
	from_buildings = n
	var scatter := int(preset.get("lootScatterCount", 150))
	var half := layout.half_size - 40.0
	for i in scatter:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if world.height_at(x, z) > layout.spawn_max_height:
			continue
		for item in LootTables.roll_node("residential", rng):
			registry.add(item, Vector3(x, world.height_at(x, z), z))
			n += 1
	return {"total": n, "buildings": from_buildings, "scatter": n - from_buildings}
