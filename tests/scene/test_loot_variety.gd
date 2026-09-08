extends TestCase
## The loot laid out on the real map has to be varied: a player walking a town must find
## different guns, not the same rifle in every building. Guards against a table where one
## guarantee or one heavy weight swamps everything else.

func test_map_loot_is_varied() -> void:
	var w: World = load("res://game/world/world.tscn").instantiate()
	await add_to_tree(w)
	w.setup("mesh", null, true)
	await settle(2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var preset: Dictionary = DataLib.preset("slice_2km")
	var stats: Dictionary = LootSpawner.generate(w, w.loot_registry, rng, preset)
	var hist := {}
	for id in w.loot_registry.entries:
		var e = w.loot_registry.entries[id]
		var iid := String(e.item.get("id", "?"))
		hist[iid] = int(hist.get(iid, 0)) + 1
	var total: int = w.loot_registry.count()
	var keys: Array = hist.keys()
	keys.sort_custom(func(a, b): return hist[a] > hist[b])
	var top: Array = []
	for k in keys.slice(0, 8):
		top.append("%s %.1f%%" % [k, 100.0 * hist[k] / total])
	print("    loot: %d items, %d distinct, spawn=%s" % [total, keys.size(), stats])
	print("    top: %s" % ", ".join(top))
	assert_true(total > 800, "the map is well stocked (%d items)" % total)
	assert_true(keys.size() >= 25, "at least 25 distinct items on the ground (%d)" % keys.size())
	# no single item may dominate: guns in particular should not all be the same model
	var share := 100.0 * float(hist[keys[0]]) / float(total)
	assert_true(share < 18.0, "the commonest item (%s) is %.1f%% of all loot" % [keys[0], share])
	var guns := 0
	for k in keys:
		if String(ItemCatalog.get_item(k).get("kind", "")) == "weapon":
			guns += 1
	assert_true(guns >= 8, "at least 8 different guns spawn (%d)" % guns)
	w.queue_free()
	await settle(1)
