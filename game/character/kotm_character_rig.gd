class_name KOTMCharacterRig
extends Node
## Shared imported-rig adapter for gameplay and the wardrobe preview. Geometry, skin binds,
## weapon attachments and finger poses remain authored in the GLB.

const SCENE_PATH := "res://assets/characters/kotm/KOTM_Character.glb"
const MANIFEST_PATH := "res://assets/characters/kotm/asset_manifest.json"
const SUPPORT_IK := preload("res://game/character/support_hand_ik.gd")
const WEAPONS := {"ar15": "AR75", "ak47": "AR75", "hunting_rifle": "Hunting"}
const WEAPON_ROOTS := {"ar15": "AR75", "ak47": "AK47", "hunting_rifle": "HuntingRifle"}
const TEMPLATE_DIR := "res://assets/characters/kotm/templates/"
const REQUIRED_TEMPLATES := [
	"MotorcycleHelmet", "BaseballCap", "Sunglasses", "FaceBandana", "TankTop",
	"TShirt", "Hoodie", "Leggings", "Shorts", "Sneakers", "Beanie"
]
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
var grafted_template_keys: Dictionary = {}
var weapon_id := ""
var contact_enabled := false
var loadout: Dictionary = {}
var wardrobe := {"top": "DefaultTank", "bottom": "DefaultBoxers", "head": "None", "face": "None", "feet": "None", "hands": "None", "armour": "None"}
var equipment := {"helmet": false, "armour": false, "backpack": false}
var _pack_rest := Vector3.ZERO
var _pack_offset := Vector3.ZERO
var _pack_straps: Array[MeshInstance3D] = []
var errors: Array[String] = []
var body_composite = preload("res://game/character/body_composite.gd").new()

func setup(model: Node3D) -> bool:
	avatar = model
	_ensure_ar75_geometry()
	_ensure_ak47_geometry()
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
	for key in ["Helmet", "Armour", "Backpack", "AR75", "AK47", "HuntingRifle"]:
		roots[key] = avatar.find_child("EQ_" + key, true, false)
	for key in manifest.get("templates", {}):
		var info: Dictionary = manifest.templates[key]
		var template_root_name := String(info.get("root", ""))
		roots[key] = avatar.find_child(template_root_name, true, false)
		meshes[key] = []
		for source_name in info.meshes:
			var mesh := avatar.find_child(String(source_name).replace(".", "_"), true, false) as MeshInstance3D
			if mesh:
				meshes[key].append(mesh)
			elif roots[key] == null and key in REQUIRED_TEMPLATES:
				errors.append("Missing wearable mesh: " + str(source_name))
	_restore_template_geometry()
	_hide_unbatched_template_geometry()
	meshes["DefaultTank"] = []
	meshes["DefaultBoxers"] = []
	for mesh in avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh_name := String(mesh.name)
		if mesh_name.begins_with("BODY_Region_"):
			body_regions.append(mesh)
		elif mesh_name.begins_with("Eyes_sclera") or mesh_name.begins_with("Iris") or mesh_name.begins_with("Limbal") or mesh_name.begins_with("Pupil") or mesh_name.begins_with("Eyebrow"):
			mesh.visibility_range_end = 70.0
			mesh.visibility_range_end_margin = 8.0
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
		muzzle_nodes[id] = avatar.find_child(String(WEAPON_ROOTS[id]) + "_Muzzle", true, false)
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
	body_composite.setup(body_regions)
	apply_visibility()
	return true

func _restore_template_geometry() -> void:
	# The movement export can contain the authored wardrobe placeholders without
	# the compact RT_* mesh nodes. Reuse the small, skin-compatible template GLBs
	# and bind their meshes to this character's shared 54-bone skeleton.
	for key in manifest.get("templates", {}):
		var info: Dictionary = manifest.templates[key]
		var root_name := String(info.get("root", ""))
		var root := avatar.find_child(root_name, true, false) as Node3D
		var expected: Array = info.get("meshes", [])
		var complete := root != null
		for source_name in expected:
			if avatar.find_child(String(source_name).replace(".", "_"), true, false) == null:
				complete = false
				break
		if complete:
			continue
		_attach_template_geometry(String(key), root_name, expected, root)

func _attach_template_geometry(key: String, root_name: String, expected: Array, existing_root: Node3D) -> void:
	if grafted_template_keys.has(key):
		return
	var path := TEMPLATE_DIR + "KOTM_Template_" + key + ".glb"
	if not ResourceLoader.exists(path) and key == "Beanie":
		path = TEMPLATE_DIR + "KOTM_Beanie.glb"
	if not ResourceLoader.exists(path):
		errors.append("Missing template scene: " + key)
		return
	var packed: PackedScene = load(path)
	if packed == null:
		errors.append("Unable to load template scene: " + key)
		return
	var instance := packed.instantiate()
	var source_skeleton := instance.find_child("Skeleton3D", true, false) as Skeleton3D
	if source_skeleton == null or source_skeleton.get_bone_count() != skeleton.get_bone_count():
		instance.queue_free()
		errors.append("Template skeleton mismatch: " + key)
		return
	for bone_index in skeleton.get_bone_count():
		if source_skeleton.get_bone_name(bone_index) != skeleton.get_bone_name(bone_index):
			instance.queue_free()
			errors.append("Template bone order mismatch: " + key)
			return
	var root := existing_root
	if root == null:
		root = Node3D.new()
		root.name = root_name
		avatar.add_child(root)
	var attached := 0
	for source_name in expected:
		var source_mesh := instance.find_child(String(source_name), true, false) as MeshInstance3D
		if source_mesh == null:
			continue
		var local_transform := source_mesh.transform
		var source_parent := source_mesh.get_parent()
		if source_parent:
			source_parent.remove_child(source_mesh)
		source_mesh.owner = null
		skeleton.add_child(source_mesh)
		source_mesh.skeleton = NodePath("..")
		source_mesh.transform = local_transform
		meshes[key].append(source_mesh)
		attached += 1
	if attached > 0:
		roots[key] = root
		grafted_template_keys[key] = true
	else:
		errors.append("Template contains no expected meshes: " + key)
	instance.queue_free()

func _hide_unbatched_template_geometry() -> void:
	# Authoring exports may leave neutral template parts directly under the
	# skeleton. The runtime uses the compact meshes above, so keep those parts
	# from showing through every outfit.
	for mesh in avatar.find_children("*", "MeshInstance3D", true, false):
		var mesh_name := String(mesh.name)
		if mesh_name.begins_with("Template_") or mesh_name.begins_with("EQ_Template_") or mesh_name in ["Leggings_BlankShell", "Shorts_BlankShell", "Sneaker_Blank_l", "Sneaker_Blank_r", "Sneaker_LacesEyelets_l", "Sneaker_LacesEyelets_r", "Sneaker_Tongue_l", "Sneaker_Tongue_r"]:
			mesh.visible = false

func _ensure_ar75_geometry() -> void:
	# The authored character export keeps the hand-mounted socket but may omit the
	# empty-only AR75 branch. Restore the standalone solid weapon and its sockets
	# under the existing hand attachment so animation and contact stay authored.
	var target := avatar.find_child("EQ_AR75", true, false) as Node3D
	if target == null or target.find_child("AR75__Barrel", true, false) != null:
		return
	var packed: PackedScene = load("res://assets/models/kotm/KOTM_AR75.glb")
	if packed == null:
		return
	var instance := packed.instantiate()
	var source := instance.find_child("EQ_AR75", true, false) as Node3D
	if source == null:
		instance.queue_free()
		return
	for child in source.get_children():
		source.remove_child(child)
		child.owner = null
		target.add_child(child)
	instance.queue_free()

func _ensure_ak47_geometry() -> void:
	# The rebuilt animation export keeps the hand socket but stores the AK as a
	# standalone model. Restore that solid weapon under the same hand attachment
	# so the authored AR/AK clips share one bone-bound contact path.
	var ar_target := avatar.find_child("EQ_AR75", true, false) as Node3D
	if ar_target == null or ar_target.get_parent() == null:
		return
	var target := avatar.find_child("EQ_AK47", true, false) as Node3D
	if target == null:
		target = Node3D.new()
		target.name = "EQ_AK47"
		target.transform = ar_target.transform
		ar_target.get_parent().add_child(target)
	if target.find_child("AK47Rev__Barrel", true, false) != null:
		return
	var packed: PackedScene = load("res://assets/models/kotm/KOTM_AK47.glb")
	if packed == null:
		return
	var instance := packed.instantiate()
	var source := instance.find_child("EQ_AK47", true, false) as Node3D
	if source == null:
		instance.queue_free()
		return
	for child in source.get_children():
		source.remove_child(child)
		child.owner = null
		target.add_child(child)
	instance.queue_free()

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
	for weapon_key in WEAPON_ROOTS:
		var key: String = WEAPON_ROOTS[weapon_key]
		if roots.get(key):
			roots[key].visible = id == weapon_key
	var skin: Dictionary = loadout.get("weapons", {})
	if WEAPONS.has(id) and skin.has(id):
		SkinSystem.apply_to_weapon(weapon_root(id), SkinSystem.weapon_skin(String(skin[id])))

func weapon_root(id: String) -> Node3D:
	return roots.get(WEAPON_ROOTS.get(id, ""))

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
	if muzzle_bindings.has(weapon_id):
		# The common skeleton world transform cancels exactly for a bone-bound marker.
		var binding: Dictionary = muzzle_bindings[weapon_id]
		return skeleton.get_bone_global_pose(binding.bone) * binding.relative * wrist_offsets[weapon_id]
	return skeleton.global_transform.affine_inverse() * marker_world(weapon_id) * wrist_offsets[weapon_id]

func set_equipment(helmet: bool, armour: bool, backpack: bool) -> void:
	if helmet == equipment.helmet and armour == equipment.armour and backpack == equipment.backpack:
		return
	equipment = {"helmet": helmet, "armour": armour, "backpack": backpack}
	apply_visibility()

func apply_loadout(value: Dictionary) -> void:
	loadout = value.duplicate(true)
	var defaults := SkinSystem.default_loadout()
	var chest := String(value.get("chest", ""))
	var legs := String(value.get("legs", ""))
	var feet := String(value.get("feet", ""))
	var head := String(value.get("head", ""))
	var face := String(value.get("face", ""))
	var hands := String(value.get("hands", ""))
	var armour_skin := String(value.get("armour", ""))
	wardrobe.top = "DefaultTank" if chest in ["", String(defaults.chest)] else ("Hoodie" if chest.contains("hood") else "TShirt")
	wardrobe.bottom = "DefaultBoxers" if legs in ["", String(defaults.legs)] else ("Shorts" if legs.contains("short") else "Leggings")
	wardrobe.feet = "None" if feet in ["", String(defaults.feet)] else "Sneakers"
	wardrobe.head = "None" if head.is_empty() else ("Beanie" if head.contains("beanie") else "BaseballCap")
	wardrobe.face = "None" if face.is_empty() else ("Sunglasses" if face.contains("glass") else "FaceBandana")
	wardrobe.hands = "None"
	wardrobe.armour = "None"
	# Authored equipment declares its actual mesh family in the cosmetic catalog.
	for pair in [["top", chest], ["bottom", legs], ["feet", feet], ["head", head], ["face", face], ["hands", hands], ["armour", armour_skin]]:
		var model_key := String(SkinSystem.item(String(pair[1])).get("model", ""))
		if meshes.has(model_key):
			wardrobe[pair[0]] = model_key
	# Developer wardrobe overrides are explicit template names, independent of item stats.
	for slot in value.get("kotm_wardrobe", {}):
		var key := String(value.kotm_wardrobe[slot])
		if wardrobe.has(slot) and (meshes.has(key) or key == "None"):
			wardrobe[slot] = key
	for pair in [["top", chest], ["bottom", legs], ["feet", feet], ["head", head], ["face", face], ["hands", hands], ["armour", armour_skin]]:
		var item := SkinSystem.item(pair[1])
		var wearable: String = wardrobe[pair[0]]
		var wearable_info: Dictionary = manifest.get("templates", {}).get(wearable, {})
		if item.is_empty() or wearable.begins_with("Default") or wearable_info.get("finished_material", false) or wearable == "Beanie":
			continue
		var mat := SkinSystem.recipe_material(item.get("recipe", {}))
		for mesh in meshes.get(wearable, []):
			if wearable == "Sunglasses":
				# Runtime batching combines frame and lens islands in one mesh.
				# Keep the dark lens finish while applying cosmetics to the frame.
				mesh.material_override = null
				for surface in mesh.mesh.get_surface_count():
					var base_material: Material = mesh.mesh.surface_get_material(surface)
					var lens := base_material != null and base_material.resource_name.to_lower().contains("lens")
					mesh.set_surface_override_material(surface, null if lens else mat)
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
	body_composite.update()

var worn_shoes := false

func set_worn_shoes(on: bool) -> void:
	if on != worn_shoes:
		worn_shoes = on
		apply_visibility()

func apply_visibility() -> void:
	var active: Array = wardrobe.values()
	if worn_shoes:
		active.append("Sneakers")
	var helmet_on: bool = equipment.helmet or wardrobe.head in ["MotorcycleHelmet", "TacticalSantaHat"]
	for key in meshes:
		var enabled: bool = key in active and not (key == "Sunglasses" and helmet_on)
		if key in ["BaseballCap", "Beanie", "MotorcycleHelmet", "TacticalSantaHat"] and equipment.helmet:
			enabled = false
		if roots.get(key):
			roots[key].visible = enabled
		for mesh in meshes[key]:
			mesh.visible = enabled
	for pair in [["Helmet", "helmet"], ["Armour", "armour"], ["Backpack", "backpack"]]:
		if roots.get(pair[0]):
			roots[pair[0]].visible = equipment[pair[1]] and not (pair[0] == "Armour" and wardrobe.armour != "None")
	for region in body_regions:
		region.visible = true
		for key in manifest.get("body_masks", {}).get(String(region.name), []):
			if key in active:
				region.visible = false
	var hair := avatar.find_child("KOTM_Hair_SweptCrop", true, false) as Node3D
	if hair:
		hair.visible = not helmet_on and wardrobe.head == "None" and String(loadout.get("hair", "")) != "hair_bald"
	if roots.get("Backpack"):
		roots.Backpack.position = _pack_rest + (_pack_offset if equipment.armour or wardrobe.armour == "KevlarVest" else Vector3.ZERO)
	for strap in _pack_straps:
		strap.visible = not (equipment.armour or wardrobe.armour == "KevlarVest")
	body_composite.update()
