class_name KOTMCharacterRig
extends Node
## Shared imported-rig adapter for gameplay and the wardrobe preview. Geometry, skin binds,
## weapon attachments and finger poses remain authored in the GLB.

const SCENE_PATH := "res://assets/characters/kotm/KOTM_Character.glb"
const MANIFEST_PATH := "res://assets/characters/kotm/asset_manifest.json"
const SUPPORT_IK := preload("res://game/character/support_hand_ik.gd")
const WEAPONS := {"ar15": "AR75", "hunting_rifle": "Hunting"}
static var manifest: Dictionary = {}
static var stride_centres: Dictionary = {}
static var calibrated_wrists: Dictionary = {}
static var skin_materials: Dictionary = {}
var avatar: Node3D
var skeleton: Skeleton3D
var player: AnimationPlayer
var clips: Dictionary = {}
var roots: Dictionary = {}
var meshes: Dictionary = {}
var body_regions: Array[MeshInstance3D] = []
var muzzle_nodes: Dictionary = {}
var muzzle_bindings: Dictionary = {}
var wrist_offsets: Dictionary = {}
var support_hand: SkeletonModifier3D
var weapon_id := ""
var contact_enabled := false
var loadout: Dictionary = {}
var wardrobe := {"top": "DefaultTank", "bottom": "DefaultBoxers", "head": "None", "face": "None", "feet": "None"}
var equipment := {"helmet": false, "armour": false, "backpack": false}
var _pack_rest := Vector3.ZERO
var _pack_offset := Vector3.ZERO
var _pack_straps: Array[MeshInstance3D] = []
var errors: Array[String] = []

func setup(model: Node3D) -> bool:
	avatar = model
	var skels := avatar.find_children("*", "Skeleton3D", true, false)
	var players := avatar.find_children("*", "AnimationPlayer", true, false)
	if skels.is_empty() or players.is_empty():
		return false
	skeleton = skels[0]
	player = players[0]
	if manifest.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if parsed is Dictionary:
			manifest = parsed
	for clip_name in player.get_animation_list():
		var key := String(clip_name).get_slice("/", String(clip_name).get_slice_count("/") - 1)
		clips[key] = clip_name
		var info: Dictionary = manifest.get("animations", {}).get(key, {})
		player.get_animation(clip_name).loop_mode = Animation.LOOP_LINEAR if info.get("loop", false) else Animation.LOOP_NONE
	# The truck contact solver can reuse the authored seated base. Keep the public
	# clip name distinct so truck-specific spine handling stays explicit.
	if not clips.has("KOTM_Truck_Seated") and clips.has("KOTM_Snowmobile_Seated"):
		clips["KOTM_Truck_Seated"] = clips["KOTM_Snowmobile_Seated"]
	for key in ["Helmet", "Armour", "Backpack", "AR75", "HuntingRifle"]:
		roots[key] = avatar.find_child("EQ_" + key, true, false)
	for key in manifest.get("templates", {}):
		var info: Dictionary = manifest.templates[key]
		roots[key] = avatar.find_child(info.root, true, false)
		meshes[key] = []
		for source_name in info.meshes:
			var mesh := avatar.find_child(String(source_name).replace(".", "_"), true, false) as MeshInstance3D
			if mesh:
				meshes[key].append(mesh)
			else:
				errors.append("Missing wearable mesh: " + str(source_name))
	meshes["DefaultTank"] = []
	meshes["DefaultBoxers"] = []
	for mesh in avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh_name := String(mesh.name)
		if mesh_name.begins_with("BODY_Region_"):
			body_regions.append(mesh)
		elif mesh_name.begins_with("Tank_"):
			meshes.DefaultTank.append(mesh)
		elif mesh_name.begins_with("Boxers_"):
			meshes.DefaultBoxers.append(mesh)
		if mesh_name.begins_with("GEAR_BACKPACK_Pack_Strap") or mesh_name.begins_with("GEAR_BACKPACK_Pack_LadderLock") or mesh_name.begins_with("GEAR_BACKPACK_Pack_Sternum"):
			_pack_straps.append(mesh)
	if roots.get("Backpack"):
		_pack_rest = roots.Backpack.position
		_pack_offset = skeleton.get_bone_global_rest(skeleton.find_bone("chest")).basis.inverse() * Vector3(0, 0, -0.045)
	for id in WEAPONS:
		muzzle_nodes[id] = avatar.find_child("AR75_Muzzle" if id == "ar15" else "HuntingRifle_Muzzle", true, false)
		_cache_muzzle_binding(id)
		var clip: String = "KOTM_" + WEAPONS[id] + "_Aim"
		if calibrated_wrists.has(id):
			wrist_offsets[id] = calibrated_wrists[id]
		elif clips.has(clip) and muzzle_nodes[id]:
			player.play(clips[clip], 0)
			player.seek(0.5, true)
			player.advance(0)
			wrist_offsets[id] = marker_world(id).affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand.l"))
			calibrated_wrists[id] = wrist_offsets[id]
	_calibrate_stride_centres()
	play("KOTM_Idle", 0)
	player.advance(0)
	support_hand = SUPPORT_IK.new()
	support_hand.name = "SupportHandContact"
	support_hand.target_provider = _contact_target
	support_hand.enabled_provider = func() -> bool: return contact_enabled and wrist_offsets.has(weapon_id)
	# Added after the game's pitch modifier by finish_modifiers().
	apply_visibility()
	return true

func _calibrate_stride_centres() -> void:
	for key in clips:
		if stride_centres.has(key) or not (key.ends_with("Walk") or key.ends_with("Jog") or key.ends_with("Run")):
			continue
		var centres: Array = [Vector3.ZERO, Vector3.ZERO]
		var duration := player.get_animation(clips[key]).length
		player.play(clips[key], 0)
		for sample in 16:
			player.seek(duration * sample / 16.0, true)
			player.advance(0)
			for side in 2:
				centres[side] += skeleton.get_bone_global_pose(skeleton.find_bone("foot.l" if side == 0 else "foot.r")).origin / 16.0
		stride_centres[key] = centres

func finish_modifiers() -> void:
	skeleton.add_child(support_hand)

func play(clip: String, blend := 0.2) -> void:
	if clips.has(clip):
		player.play(clips[clip], blend)

func set_weapon(id: String) -> void:
	weapon_id = id
	for key in ["AR75", "HuntingRifle"]:
		if roots.get(key):
			roots[key].visible = (id == "ar15" and key == "AR75") or (id == "hunting_rifle" and key == "HuntingRifle")
	var skin: Dictionary = loadout.get("weapons", {})
	if WEAPONS.has(id) and skin.has(id):
		SkinSystem.apply_to_weapon(weapon_root(id), SkinSystem.weapon_skin(String(skin[id])))

func weapon_root(id: String) -> Node3D:
	return roots.get("AR75" if id == "ar15" else "HuntingRifle")

func marker_world(id: String) -> Transform3D:
	if muzzle_bindings.has(id):
		var binding: Dictionary = muzzle_bindings[id]
		return skeleton.global_transform * skeleton.get_bone_global_pose(binding.bone) * binding.relative
	var marker: Node3D = muzzle_nodes.get(id)
	return marker.global_transform if marker else Transform3D.IDENTITY

func _cache_muzzle_binding(id: String) -> void:
	var marker: Node3D = muzzle_nodes.get(id)
	if marker == null:
		return
	var relative := marker.transform
	var ancestor := marker.get_parent()
	while ancestor is Node3D and not ancestor is BoneAttachment3D:
		relative = ancestor.transform * relative
		ancestor = ancestor.get_parent()
	if ancestor is BoneAttachment3D:
		var bone := skeleton.find_bone(ancestor.bone_name)
		if bone >= 0:
			muzzle_bindings[id] = {"bone": bone, "relative": relative}

func _contact_target() -> Transform3D:
	return skeleton.global_transform.affine_inverse() * marker_world(weapon_id) * wrist_offsets[weapon_id]

func set_equipment(helmet: bool, armour: bool, backpack: bool) -> void:
	var updated := {"helmet": helmet, "armour": armour, "backpack": backpack}
	if updated == equipment:
		return
	equipment = updated
	apply_visibility()

func apply_loadout(value: Dictionary) -> void:
	loadout = value.duplicate(true)
	var defaults := SkinSystem.default_loadout()
	var chest := String(value.get("chest", ""))
	var legs := String(value.get("legs", ""))
	var feet := String(value.get("feet", ""))
	var head := String(value.get("head", ""))
	var face := String(value.get("face", ""))
	wardrobe.top = "DefaultTank" if chest in ["", String(defaults.chest)] else ("Hoodie" if chest.contains("hood") else "TShirt")
	wardrobe.bottom = "DefaultBoxers" if legs in ["", String(defaults.legs)] else ("Shorts" if legs.contains("short") else "Leggings")
	wardrobe.feet = "None" if feet in ["", String(defaults.feet)] else "Sneakers"
	wardrobe.head = "None" if head.is_empty() else ("Beanie" if head.contains("beanie") else "BaseballCap")
	wardrobe.face = "None" if face.is_empty() else ("Sunglasses" if face.contains("glass") else "FaceBandana")
	# Developer wardrobe overrides are explicit template names, independent of item stats.
	for slot in value.get("kotm_wardrobe", {}):
		var key := String(value.kotm_wardrobe[slot])
		if wardrobe.has(slot) and (meshes.has(key) or key == "None"):
			wardrobe[slot] = key
	for pair in [["top", chest], ["bottom", legs], ["feet", feet], ["head", head], ["face", face]]:
		var item := SkinSystem.item(pair[1])
		var wearable: String = wardrobe[pair[0]]
		var wearable_info: Dictionary = manifest.get("templates", {}).get(wearable, {})
		if item.is_empty() or wearable.begins_with("Default") or wearable_info.get("finished_material", false) or wearable == "Beanie":
			continue
		var mat := SkinSystem.recipe_material(item.get("recipe", {}))
		for mesh in meshes.get(wearable, []):
			if wearable == "Sunglasses" and String(mesh.name).to_lower().contains("lens"):
				continue
			mesh.material_override = mat
	apply_visibility()
	set_weapon(weapon_id)
	_apply_appearance()

func _apply_appearance() -> void:
	var skin_id := String(loadout.get("skin", "skin_medium"))
	var skin_recipe: Dictionary = SkinSystem.item(skin_id).get("recipe", {})
	var base := Color("#d9a37a")
	var tint := Color(String(skin_recipe.get("color", "#d9a37a")))
	for region in body_regions:
		for index in region.mesh.get_surface_count():
			var material := region.mesh.surface_get_material(index) as StandardMaterial3D
			if material:
				if skin_id == "skin_medium":
					region.set_surface_override_material(index, null)
					continue
				var cache_key := str(material.get_rid()) + ":" + skin_id
				if not skin_materials.has(cache_key):
					var copy := material.duplicate() as StandardMaterial3D
					copy.albedo_color *= Color(tint.r / base.r, tint.g / base.g, tint.b / base.b)
					skin_materials[cache_key] = copy
				region.set_surface_override_material(index, skin_materials[cache_key])
	var hair := avatar.find_child("KOTM_Hair_SweptCrop", true, false) as MeshInstance3D
	var hair_item := SkinSystem.item(String(loadout.get("hair", "hair_short_brown")))
	if hair and not hair_item.is_empty():
		var recipe: Dictionary = hair_item.get("recipe", {})
		hair.visible = hair.visible and recipe.get("style", "short") != "bald"
		if String(loadout.get("hair", "")) != "hair_short_brown":
			hair.material_override = SkinSystem.recipe_material(recipe)

func apply_visibility() -> void:
	var active: Array = wardrobe.values()
	var helmet_on: bool = equipment.helmet or wardrobe.head == "MotorcycleHelmet"
	for key in meshes:
		var enabled: bool = key in active and not (key == "Sunglasses" and helmet_on)
		if key in ["BaseballCap", "Beanie", "MotorcycleHelmet"] and equipment.helmet:
			enabled = false
		if roots.get(key):
			roots[key].visible = enabled
		for mesh in meshes[key]:
			mesh.visible = enabled
	for pair in [["Helmet", "helmet"], ["Armour", "armour"], ["Backpack", "backpack"]]:
		if roots.get(pair[0]):
			roots[pair[0]].visible = equipment[pair[1]]
	for region in body_regions:
		region.visible = true
		for key in manifest.get("body_masks", {}).get(String(region.name), []):
			if key in active:
				region.visible = false
	var hair := avatar.find_child("KOTM_Hair_SweptCrop", true, false) as Node3D
	if hair:
		hair.visible = not helmet_on and wardrobe.head == "None" and String(loadout.get("hair", "")) != "hair_bald"
	if roots.get("Backpack"):
		roots.Backpack.position = _pack_rest + (_pack_offset if equipment.armour else Vector3.ZERO)
	for strap in _pack_straps:
		strap.visible = not equipment.armour
