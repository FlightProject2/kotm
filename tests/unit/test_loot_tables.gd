extends TestCase

func test_rolls_are_deterministic_and_resolve() -> void:
	var a := RandomNumberGenerator.new(); a.seed = 3
	var b := RandomNumberGenerator.new(); b.seed = 3
	var ra: Array = []
	var rb: Array = []
	for i in 200:
		ra.append_array(LootTables.roll_node("residential", a))
		rb.append_array(LootTables.roll_node("residential", b))
	assert_eq(ra, rb, "same seed, same loot")
	assert_true(ra.size() > 100, "residential nodes produce loot")
	for e in ra:
		assert_true(e.has("kind") and e.has("id"), "entry shape")
		assert_true(ItemCatalog.has(e["id"]), "resolved id exists: " + str(e["id"]))

func test_guarantees() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 11
	for i in 20:
		var items := LootTables.roll_node("police", rng)
		var has_rifle := false
		for e in items:
			if e["kind"] == "weapon" and e["id"] in ["ar15", "ak47"]:
				has_rifle = true
		assert_true(has_rifle, "police nodes always carry a rifle")
		var mil := LootTables.roll_node("military", rng)
		assert_true(mil.any(func(e): return e["id"] == "hunting_rifle"), "military nodes always carry a hunting rifle")

func test_airdrop_fixed_set() -> void:
	var rng := RandomNumberGenerator.new(); rng.seed = 1
	var items := LootTables.roll_node("airdrop", rng)
	var ids := items.map(func(e): return e["id"])
	assert_true(ids.has("hunting_rifle") and ids.has("tactical_helmet") and ids.has("laminated_armor"), "airdrop ids: %s" % [ids])
	var kits := 0
	for e in items:
		if e["id"] == "first_aid_kit":
			kits += int(e.get("qty", 1))
	assert_eq(kits, 2, "two first aid kits in the crate")
