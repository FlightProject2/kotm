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
			n += place_group(registry, LootTables.roll_node(ln["class"], rng), ln["pos"], rng, 0.55)
	for b in layout.buildings:
		var cls: String = b.get("nodeClass", "residential")
		var base := layout.building_base_height(b)
		var nodes := 2 if cls in ["police", "military", "industrial", "commercial"] else 1
		for k in nodes:
			var ang := rng.randf() * TAU
			var r := rng.randf_range(6.0, 11.0)
			var x: float = b["x"] + cos(ang) * r
			var z: float = b["z"] + sin(ang) * r
			var y := base if not is_nan(base) else world.height_at(x, z)
			n += place_group(registry, LootTables.roll_node(cls, rng), Vector3(x, maxf(y, world.height_at(x, z)), z), rng, 0.7)
	from_buildings = n
	var scatter := int(preset.get("lootScatterCount", 150))
	var half := layout.half_size - 40.0
	for i in scatter:
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if world.height_at(x, z) > layout.spawn_max_height:
			continue
		n += place_group(registry, LootTables.roll_node("residential", rng), Vector3(x, world.height_at(x, z), z), rng, 0.7)
	return {"total": n, "buildings": from_buildings, "scatter": n - from_buildings}

## Lays one roll out so items never stack: guns first, each gun's ammo box right beside it
## (0.5 m to the side), everything else on a small ring around the centre. Returns the count.
static func place_group(registry: LootRegistry, items: Array, centre: Vector3, rng: RandomNumberGenerator, ring: float) -> int:
	var guns: Array = []
	var ammo: Array = []
	var rest: Array = []
	for it in items:
		match String(it.get("kind", "")):
			"weapon": guns.append(it)
			"ammo": ammo.append(it)
			_: rest.append(it)
	var placed := 0
	var slot := 0
	var ring_n: int = guns.size() + rest.size()
	var base_ang := rng.randf() * TAU
	for g in guns:
		var ang := base_ang + TAU * float(slot) / maxf(ring_n, 1.0)
		var gp := centre + Vector3(cos(ang), 0, sin(ang)) * (ring if ring_n > 1 else 0.0)
		registry.add(g, gp)
		placed += 1
		slot += 1
		# this gun's ammo goes next to it; other ammo joins the ring below
		var wanted: String = String(ItemCatalog.get_item(String(g["id"])).get("def", {}).get("ammo", ""))
		for k in range(ammo.size() - 1, -1, -1):
			if String(ammo[k]["id"]) == wanted:
				var side := Vector3(-sin(ang), 0, cos(ang)) * 0.5
				registry.add(ammo[k], gp + side)
				placed += 1
				ammo.remove_at(k)
				break
	rest.append_array(ammo)
	for it in rest:
		var ang := base_ang + TAU * float(slot) / maxf(ring_n + ammo.size(), 1.0)
		registry.add(it, centre + Vector3(cos(ang), 0, sin(ang)) * (ring if (ring_n + ammo.size()) > 1 else 0.0))
		placed += 1
		slot += 1
	return placed
