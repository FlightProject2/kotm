extends TestCase

func test_pickup_swap_and_bag() -> void:
	var reg := LootRegistry.new()
	await add_to_tree(reg)
	var fl := StaticBody3D.new(); fl.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(100, 1, 100); cs.shape = bs; fl.add_child(cs); fl.position.y = -0.5
	await add_to_tree(fl)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.position = Vector3(0, 0.05, 0)
	await add_to_tree(ch)
	ch.interaction.registry = reg
	reg.add({"kind": "weapon", "id": "ar15"}, Vector3(1.0, 0, 0))
	reg.add({"kind": "ammo", "id": "223", "qty": 20}, Vector3(1.2, 0, 0.3))
	reg.add({"kind": "helmet", "id": "motorcycle_helmet"}, Vector3(0.8, 0, -0.4))
	reg.add({"kind": "weapon", "id": "ak47"}, Vector3(30, 0, 30))
	assert_eq(reg.count(), 4)
	await settle(2)
	assert_true(ch.interaction.nearest != null, "something is in reach")
	for k in 3:
		var inp := CharacterInput.new()
		inp.set_button(CharacterInput.B_INTERACT, true)
		ch.submit_input(inp)
		await tree.physics_frame
		ch.submit_input(CharacterInput.new())
		await tree.physics_frame
	assert_true(ch.inventory.has_weapon("ar15"), "picked up the AR")
	assert_eq(ch.inventory.ammo["223"], 20, "picked up the ammo")
	assert_true(ch.health.has_helmet(), "wearing the helmet")
	assert_eq(reg.count(), 1, "three items gone from the ground")
	assert_true(reg.in_radius(Vector3(30, 0, 30), 3).size() == 1, "far item untouched")
	# death bag
	ch.health.apply_damage(200)
	CharacterInteraction.drop_bag(ch, reg)
	var bag := reg.nearest(ch.global_position, 3.0)
	assert_true(bag != null and bag.item["kind"] == "bag", "bag dropped")
	assert_true(bag.item["items"].any(func(e): return e["id"] == "ar15"), "bag holds the AR")
	assert_true(bag.item["items"].any(func(e): return e["kind"] == "helmet"), "bag holds the helmet")
	ch.queue_free(); reg.queue_free(); fl.queue_free()
	await settle(1)
