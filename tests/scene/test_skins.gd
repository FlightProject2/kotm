extends TestCase

func test_patterns_and_loadouts() -> void:
	for p in ["solid", "stripe", "camo", "flames", "checker", "snakeskin"]:
		var t := SkinSystem.pattern_texture(p, Color.RED, Color.YELLOW)
		assert_eq(t.get_width(), 128, "pattern %s is 128 px" % p)
	var rng := RandomNumberGenerator.new(); rng.seed = 2
	var l := SkinSystem.random_loadout(rng)
	assert_true(l.has("chest") and l.has("weapons"))
	assert_false(SkinSystem.item(String(l["chest"])).is_empty(), "chest item resolves")
	var d := SkinSystem.default_loadout()
	assert_eq(d["chest"], "shirt_grey")

func test_apply_to_character_and_weapon() -> void:
	var fl := StaticBody3D.new(); fl.collision_layer = 1
	var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(50, 1, 50); cs.shape = bs; fl.add_child(cs); fl.position.y = -0.5
	await add_to_tree(fl)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.cosmetics = {"chest": "shirt_hotshot", "legs": "pants_police", "head": "hat_police_cap", "face": "mask_toxic", "back": "", "parachute": "chute_camo", "weapons": {"ar15": "ar15_toxic"}}
	ch.position = Vector3(0, 0.05, 0)
	await add_to_tree(ch)
	await settle(3)
	var vis: CharacterVisuals = ch.visual
	var body: MeshInstance3D = vis.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.mesh and m.mesh.get_surface_count() >= 3)[0]
	var azul := body.get_surface_override_material(0) as StandardMaterial3D
	assert_true(azul != null and azul.albedo_texture != null, "Hot Shot shirt applied with a flames texture on the body suit")
	var blanco := body.get_surface_override_material(2) as StandardMaterial3D
	assert_true(blanco != null and blanco.albedo_color.is_equal_approx(Color("#1a2140")), "police slacks colour on accents")
	assert_true(vis.hat != null and vis.mask != null, "hat and mask attachments built")
	assert_true(vis.canopy != null, "parachute canopy exists")
	ch.inventory.give_weapon("ar15")
	await settle(2)
	var model := vis.weapon_holder.mount.get_child(0) as Node3D
	assert_true(model != null, "gun model mounted")
	var skinned := false
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var om := mi.get_surface_override_material(i) as StandardMaterial3D
			if om and om.albedo_texture != null:
				skinned = true
	assert_true(skinned, "Toxic checker skin applied to the AR-15")
	ch.queue_free(); fl.queue_free()
	await settle(1)
