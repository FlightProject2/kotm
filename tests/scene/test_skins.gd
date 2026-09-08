extends TestCase

func test_patterns_and_loadouts() -> void:
	for p in ["solid", "stripe", "camo", "flames", "checker", "snakeskin"]:
		var t := SkinSystem.pattern_texture(p, Color.RED, Color.YELLOW)
		assert_eq(t.get_width(), 128, "pattern %s is 128 px" % p)
	var rng := RandomNumberGenerator.new(); rng.seed = 2
	var l := SkinSystem.random_loadout(rng)
	assert_true(l.has("chest") and l.has("weapons"))
	assert_false(SkinSystem.item(String(l["chest"])).is_empty(), "chest item resolves")
	assert_eq(SkinSystem.default_loadout()["chest"], "tank_white")
	assert_eq(SkinSystem.default_loadout()["legs"], "boxers_white")

func test_apply_to_character_and_weapon() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.cosmetics = {"chest": "shirt_hotshot", "legs": "pants_police", "head": "hat_police_cap", "face": "mask_toxic", "back": "", "parachute": "chute_camo", "weapons": {"ar15": "ar15_toxic"}}
	await add_to_tree(ch)
	var vis: CharacterVisuals = ch.visual
	var rig := vis.studio_rig
	assert_eq(rig.wardrobe.top, "TShirt")
	assert_eq(rig.wardrobe.bottom, "Leggings")
	var shirt: MeshInstance3D = rig.meshes.TShirt[0]
	assert_true(shirt.visible and shirt.skin != null, "fitted shirt retains skinning")
	assert_true(shirt.material_override.albedo_texture != null, "Hot Shot flames applied to fitted shirt")
	var pants: MeshInstance3D = rig.meshes.Leggings[0]
	assert_true(pants.visible and pants.material_override.albedo_color.is_equal_approx(Color("#1a2140")), "police colour on fitted leggings")
	assert_false(rig.meshes.DefaultTank[0].visible, "default tank hidden under replacement")
	assert_true(vis.hat != null and vis.mask != null and vis.canopy != null, "accessories and canopy retained")
	ch.show_weapon("ar15", "rifle")
	await settle(3)
	var skinned := false
	for mesh in rig.weapon_root("ar15").find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var mat := mesh.get_surface_override_material(i) as StandardMaterial3D
			if mat and mat.albedo_texture:
				skinned = true
	assert_true(skinned, "Toxic checker skin applied to authored AR")
	rig.set_equipment(true, true, true)
	assert_false(rig.roots.BaseballCap.visible, "helmet excludes cap")
	assert_true(rig.roots.Armour.visible and rig.roots.Backpack.visible, "layered equipment visible")
	for strap in rig._pack_straps:
		assert_false(strap.visible, "front harness hidden with armour")
	for region in rig.body_regions:
		var covered := false
		for key in KOTMCharacterRig.manifest.body_masks[String(region.name)]:
			covered = covered or key in rig.wardrobe.values()
		assert_eq(region.visible, not covered, "body mask matches active wardrobe")
	ch.queue_free()
	await settle(1)
