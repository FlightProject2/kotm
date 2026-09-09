extends Node
var issues: Array[String] = []
var stats: Dictionary = {}

func _ready() -> void:
	call_deferred("run_check")

func check(ok: bool, message: String) -> void:
	if not ok:
		issues.append(message)
		push_error(message)

func run_check() -> void:
	await get_tree().process_frame
	var packed = load(KOTMCharacterRig.SCENE_PATH) as PackedScene
	check(packed != null, "Character GLB loads")
	if packed == null:
		get_tree().quit(1)
		return
	var model = packed.instantiate() as Node3D
	add_child(model)
	var adapter = KOTMCharacterRig.new()
	add_child(adapter)
	var setup_ok := adapter.setup(model)
	check(setup_ok, "Shared rig setup")
	if not setup_ok:
		get_tree().quit(1)
		return
	adapter.finish_modifiers()
	check(adapter.errors.is_empty(), "All wardrobe mesh names resolve: " + str(adapter.errors))
	check(adapter.skeleton.get_bone_count() == 54, "54 deform bones")
	check(adapter.manifest.templates.size() == 17, "17 wardrobe templates")
	for key in adapter.manifest.templates:
		check(adapter.roots.get(key) != null, "Root exists: " + key)
		check(not adapter.meshes.get(key, []).is_empty(), "Meshes exist: " + key)
		for mesh in adapter.meshes.get(key, []):
			check(mesh.mesh != null and mesh.mesh.get_surface_count() > 0, "Imported material surfaces: " + str(mesh.name))
	var outfit = SkinSystem.default_loadout()
	outfit.merge({"chest":"hoodie_zip_graphite", "legs":"shortshorts_flag", "hands":"gloves_studded_lime", "feet":"canvas_oxblood"}, true)
	adapter.apply_loadout(outfit)
	for pair in [["top","HoodieZip"],["bottom","ShortShorts"],["hands","FingerlessGloves"],["feet","CanvasShoes"]]:
		check(adapter.wardrobe[pair[0]] == pair[1], "Catalog maps " + pair[1])
		for mesh in adapter.meshes[pair[1]]:
			check(mesh.visible, "Selected mesh visible: " + str(mesh.name))
			check(mesh.material_override == null, "Authored material retained: " + str(mesh.name))
	for region in adapter.body_regions:
		var masks: Array = adapter.manifest.body_masks.get(String(region.name), [])
		var hidden := false
		for key in adapter.wardrobe.values():
			if key in masks:
				hidden = true
		check(region.visible != hidden, "Body mask state: " + str(region.name))
	outfit.armour = "vest_kevlar"
	outfit.head = "santa_tactical"
	adapter.apply_loadout(outfit)
	adapter.set_equipment(false, true, true)
	check(not adapter.roots.Armour.visible, "Legacy armour hidden with authored vest")
	check(adapter.meshes.KevlarVest[0].visible, "Kevlar visible")
	check(adapter.meshes.TacticalSantaHat[0].visible, "Tactical Santa visible")
	check(adapter._pack_straps.size() == 1, "Batched backpack harness resolves separately")
	for strap in adapter._pack_straps:
		check(not strap.visible, "Backpack harness hidden with vest")
	for id in ["ar15", "ak47", "hunting_rifle"]:
		adapter.set_weapon(id)
		check(adapter.weapon_root(id).visible, "Equipped weapon visible: " + id)
		check(adapter.muzzle_nodes.get(id) != null, "Muzzle exists: " + id)
		for other in ["ar15", "ak47", "hunting_rifle"]:
			if other != id:
				check(not adapter.weapon_root(other).visible, "Other weapon hidden: " + other)
		for suffix in ["Aim", "Walk", "Run", "Crouch", "Reload"]:
			var clip = "KOTM_" + KOTMCharacterRig.WEAPONS[id] + "_" + suffix
			check(adapter.clips.has(clip), "Animation available: " + clip)
			adapter.play(clip, 0)
			adapter.player.seek(0.25, true)
			adapter.player.advance(0)
			check(adapter.marker_world(id).origin.is_finite(), "Animated muzzle finite: " + id)
	adapter.apply_loadout(SkinSystem.default_loadout())
	adapter.set_equipment(false, false, false)
	check(adapter.wardrobe.top == "DefaultTank" and adapter.wardrobe.bottom == "DefaultBoxers", "Original default outfit retained")
	check(adapter.meshes.DefaultTank.size() == 1 and adapter.meshes.DefaultBoxers.size() == 1, "Batched default outfit resolves")
	var glasses_loadout := SkinSystem.default_loadout()
	glasses_loadout.face = "mask_toxic"
	glasses_loadout["kotm_wardrobe"] = {"face":"Sunglasses"}
	adapter.apply_loadout(glasses_loadout)
	var lens_surfaces := 0
	var tinted_frames := 0
	for mesh in adapter.meshes.Sunglasses:
		check(mesh.material_override == null, "Sunglasses use separate surface materials")
		for surface in mesh.mesh.get_surface_count():
			var base_material: Material = mesh.mesh.surface_get_material(surface)
			if base_material != null and base_material.resource_name.to_lower().contains("lens"):
				lens_surfaces += 1
				check(mesh.get_surface_override_material(surface) == null, "Sunglasses lens finish preserved")
			else:
				tinted_frames += 1
				check(mesh.get_surface_override_material(surface) != null, "Sunglasses frame receives cosmetic tint")
	check(lens_surfaces > 0 and tinted_frames > 0, "Batched sunglasses retain both material roles")
	adapter.apply_loadout(SkinSystem.default_loadout())
	var imported_meshes := model.find_children("*", "MeshInstance3D", true, false)
	var composite_surfaces := 0
	for mesh in imported_meshes.duplicate():
		if mesh.name == "KOTM_VisibleBodyComposite":
			composite_surfaces += mesh.mesh.get_surface_count()
			imported_meshes.erase(mesh)
	var surfaces := 0
	for mesh in imported_meshes:
		surfaces += mesh.mesh.get_surface_count()
	check(imported_meshes.size() == 51, "Optimized model has 51 mesh nodes")
	check(surfaces == 144, "Optimized model has 144 surfaces")
	stats = {"issues":issues, "bones":adapter.skeleton.get_bone_count(), "clips":adapter.clips.size(), "templates":adapter.manifest.templates.size(), "body_regions":adapter.body_regions.size(), "weapon_roots":adapter.WEAPON_ROOTS, "mesh_nodes":imported_meshes.size(), "material_surfaces":surfaces, "runtime_body_composite_surfaces":composite_surfaces}
	print("KOTM_EQUIPMENT_CHECK=" + JSON.stringify(stats))
	adapter.queue_free()
	model.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if issues.is_empty() else 1)
