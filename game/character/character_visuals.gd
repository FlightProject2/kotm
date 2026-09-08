class_name CharacterVisuals
extends Node3D
## Owns the mannequin: facing, crouch squash, aim spine, weapon mount, helmet/armor meshes.
## Runs on every peer (purely cosmetic).

var character: Character
var skeleton: Skeleton3D
var aim_spine: AimSpineModifier
var arm_pose: ArmPoseModifier
var crouch_pose: CrouchPoseModifier
var weapon_holder: WeaponHolder
var helmet_mesh: MeshInstance3D
var backpack_mesh: MeshInstance3D
var armor_mesh: MeshInstance3D
var anim: AnimationDriver
var hat: Node3D
var mask: Node3D
var canopy: Node3D
var studio_rig: KOTMCharacterRig
var leg_ik: SkeletonModifier3D
var vehicle_contact: SkeletonModifier3D

func _ready() -> void:
	character = get_parent() as Character
	var skels := find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	skeleton = skels[0]
	if character.cosmetics.is_empty():
		character.cosmetics = SkinSystem.default_loadout()
	if find_child("KOTM_Character_Rig", true, false) or find_child("EQ_AR75", true, false):
		_setup_studio()
		return
	SkinSystem.apply_to_character(self, character.cosmetics)
	crouch_pose = CrouchPoseModifier.new()
	crouch_pose.name = "CrouchPose"
	skeleton.add_child(crouch_pose)
	aim_spine = AimSpineModifier.new()
	aim_spine.name = "AimSpine"
	skeleton.add_child(aim_spine)
	arm_pose = ArmPoseModifier.new()
	arm_pose.name = "ArmPose"
	skeleton.add_child(arm_pose)
	weapon_holder = WeaponHolder.new()
	weapon_holder.name = "HandR"
	weapon_holder.bone_name = "hand.r"
	weapon_holder.character = character
	skeleton.add_child(weapon_holder)
	character.fired.connect(func(_v: float, _h: float) -> void: weapon_holder.fire_effects())
	var head_mount := BoneAttachment3D.new()
	head_mount.name = "HeadMount"
	head_mount.bone_name = "head"
	skeleton.add_child(head_mount)
	helmet_mesh = _build_helmet(head_mount)
	var body := _body_mesh()
	if body:
		head_mount.add_child(SkinSystem.build_face(skeleton, body.mesh, character.cosmetics))
	var att := SkinSystem.build_attachments(character.cosmetics)
	if att["hat"]:
		hat = att["hat"]
		hat.position = Vector3(0, 0.04, 0.0)
		head_mount.add_child(hat)
	if att["mask"]:
		mask = att["mask"]
		head_mount.add_child(mask)
	var chest_mount := BoneAttachment3D.new()
	chest_mount.name = "ChestMount"
	chest_mount.bone_name = "spine_02"
	skeleton.add_child(chest_mount)
	armor_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.42, 0.34, 0.3)
	armor_mesh.mesh = bm
	armor_mesh.position = Vector3(0, 0.12, 0)
	armor_mesh.visible = false
	chest_mount.add_child(armor_mesh)
	backpack_mesh = _build_backpack(chest_mount)
	if att["back"]:
		chest_mount.add_child(att["back"])
	_build_canopy()
	anim = AnimationDriver.new()
	anim.name = "Anim"
	character.add_child.call_deferred(anim)

func _physics_process(_dt: float) -> void:
	if character:
		if studio_rig == null or not KOTMCharacterRig.WEAPONS.has(studio_rig.weapon_id):
			rotation.y = character.yaw

func _process(dt: float) -> void:
	if character == null:
		return
	if studio_rig:
		_process_studio()
		return
	if crouch_pose:
		crouch_pose.crouching = character.crouching and character.mode == Character.Mode.GROUND
	if aim_spine:
		aim_spine.pitch = character.pitch
	if arm_pose and skeleton:
		# arms only hold the gun on foot; the parachute and melee keep the clip's arms
		arm_pose.weapon_class = "" if character.mode == Character.Mode.PARACHUTE else _held_class
		var aim: Vector3 = character.input.aim_dir if character.input.aim_dir.length_squared() > 0.5 else \
			Vector3(-sin(character.yaw) * cos(character.pitch), sin(character.pitch), -cos(character.yaw) * cos(character.pitch))
		arm_pose.aim_dir = skeleton.global_transform.basis.inverse() * aim
	if canopy:
		canopy.visible = character.mode == Character.Mode.PARACHUTE
	if hat:
		hat.visible = not character.health.has_helmet()
	if helmet_mesh:
		helmet_mesh.visible = character.health.has_helmet()
		if character.health.has_helmet() and helmet_mesh.mesh is SphereMesh:
			var col := Color(0.15, 0.35, 0.7) if character.health.helmet_id == "motorcycle_helmet" else Color(0.25, 0.3, 0.18)
			_set_color(helmet_mesh, col)
	if backpack_mesh:
		backpack_mesh.visible = character.inventory.backpack_id != "" or String(character.cosmetics.get("back", "")) != ""
	if armor_mesh:
		armor_mesh.visible = character.health.has_armor()
		if character.health.has_armor():
			_set_color(armor_mesh, Color(0.3, 0.36, 0.17) if character.health.armor_id == "laminated_armor" else Color(0.4, 0.4, 0.42))

func _build_canopy() -> void:
	canopy = Node3D.new()
	canopy.name = "Parachute"
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 2.4
	sm.height = 1.3
	sm.is_hemisphere = true
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = SkinSystem.parachute_color(character.cosmetics)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.9
	mi.material_override = m
	mi.position.y = 4.2
	canopy.add_child(mi)
	if studio_rig:
		for side in ["l", "r"]:
			var riser := MeshInstance3D.new()
			riser.name = "Riser_" + side
			var strap := BoxMesh.new()
			strap.size = Vector3(0.025, 0.36, 0.014)
			riser.mesh = strap
			var grip: Vector3 = preload("res://game/character/parachute_contact.gd").grip(side)
			riser.position = to_local(skeleton.global_transform * (grip + Vector3.UP * 0.04))
			var fabric := StandardMaterial3D.new()
			fabric.albedo_color = Color(0.09, 0.09, 0.07)
			fabric.roughness = 1.0
			riser.material_override = fabric
			canopy.add_child(riser)
	var lines := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for corner in [Vector3(-1.6, 4.2, -1.6), Vector3(1.6, 4.2, -1.6), Vector3(-1.6, 4.2, 1.6), Vector3(1.6, 4.2, 1.6)]:
		im.surface_add_vertex(Vector3(0, 1.5, 0))
		im.surface_add_vertex(corner)
	im.surface_end()
	lines.mesh = im
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.15, 0.15, 0.15)
	lines.material_override = lm
	canopy.add_child(lines)
	canopy.visible = false
	add_child(canopy)
	skeleton.skeleton_updated.connect(_update_canopy_lines.bind(im))

func _update_canopy_lines(im: ImmediateMesh) -> void:
	if not canopy.visible:
		return
	var hands: Array[Vector3] = []
	for side in ["l", "r"]:
		if studio_rig:
			var grip: Vector3 = preload("res://game/character/parachute_contact.gd").grip(side)
			hands.append(to_local(skeleton.global_transform * (grip + Vector3.UP * 0.22)))
		else:
			hands.append(to_local(skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("hand." + side)).origin))
	if hands[0].x > hands[1].x:
		hands.reverse()
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for corner in [Vector3(-1.6, 4.2, -1.6), Vector3(1.6, 4.2, -1.6), Vector3(-1.6, 4.2, 1.6), Vector3(1.6, 4.2, 1.6)]:
		im.surface_add_vertex(hands[0 if corner.x < 0 else 1])
		im.surface_add_vertex(corner)
	im.surface_end()

## The studio motorcycle helmet, fitted over the measured head (falls back to a sphere).
func _build_helmet(head_mount: Node3D) -> MeshInstance3D:
	var body := _body_mesh()
	var mi: MeshInstance3D = ModelLib.instance("motorcycle_helmet") if ModelLib.exists("motorcycle_helmet") else null
	if mi == null or mi.mesh == null or body == null or skeleton == null:
		var sphere := MeshInstance3D.new()
		var hm := SphereMesh.new(); hm.radius = 0.15; hm.height = 0.2
		sphere.mesh = hm
		sphere.position = Vector3(0, 0.06, 0)
		sphere.visible = false
		head_mount.add_child(sphere)
		return sphere
	# head bounds are in skeleton space; the helmet's own space has its centre at the origin
	var hb := SkinSystem.head_bounds(body.mesh)
	var head_c := hb.get_center() + Vector3(0, hb.size.y * 0.06, hb.size.z * 0.02)
	var scale := (hb.size.x * 1.22) / maxf(ModelLib.aabb("motorcycle_helmet").size.x, 0.01)
	var to_bone := skeleton.get_bone_global_rest(skeleton.find_bone("head")).affine_inverse()
	# the model faces -Z (Blender -Y forward -> glTF -Z); the mannequin faces +Z in skeleton space
	mi.transform = to_bone * Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * scale), head_c)
	mi.visible = false
	head_mount.add_child(mi)
	return mi

## The studio military backpack on the upper back; visible with a backpack item or back cosmetic.
func _build_backpack(chest_mount: Node3D) -> MeshInstance3D:
	if not ModelLib.exists("military_backpack") or skeleton == null:
		return null
	var mi := ModelLib.instance("military_backpack")
	if mi.mesh == null:
		return null
	var body := _body_mesh()
	var hb := SkinSystem.head_bounds(body.mesh) if body else AABB(Vector3(-0.1, 1.55, -0.1), Vector3(0.2, 0.25, 0.2))
	var chest_bi := skeleton.find_bone("spine_02")
	var chest_rest := skeleton.get_bone_global_rest(chest_bi)
	var sz := ModelLib.aabb("military_backpack").size
	var scale := 0.44 / maxf(sz.y, 0.01)
	# behind the chest: mannequin faces +Z, so the back is -Z; pack front (straps) faces +Z
	var pos := chest_rest.origin + Vector3(0, 0.10, -(hb.size.z * 0.55 + sz.z * scale * 0.5))
	mi.transform = chest_rest.affine_inverse() * Transform3D(Basis().scaled(Vector3.ONE * scale), pos)
	mi.visible = false
	chest_mount.add_child(mi)
	return mi

func _body_mesh() -> MeshInstance3D:
	for m in find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.skin != null and mi.mesh != null:
			return mi
	return null

static func _set_color(mi: MeshInstance3D, c: Color) -> void:
	var m := mi.material_override as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		mi.material_override = m
	m.albedo_color = c

func play_melee() -> void:
	if anim:
		anim.play_melee()

var _held_class: String = ""

func show_weapon(weapon_id: String, weapon_class: String) -> void:
	_held_class = weapon_class if weapon_id != "" else ""
	if weapon_holder:
		weapon_holder.set_weapon(weapon_id, weapon_class)
	if anim:
		anim.armed = weapon_class != "melee" and weapon_id != ""
		if studio_rig:
			anim.weapon_changed()

func _setup_studio() -> void:
	studio_rig = KOTMCharacterRig.new()
	studio_rig.name = "StudioRig"
	add_child(studio_rig)
	studio_rig.setup(get_node("Model"))
	studio_rig.apply_loadout(character.cosmetics)
	var lower_layer := preload("res://game/character/locomotion_layer.gd").new()
	lower_layer.character = character
	lower_layer.rig = studio_rig
	skeleton.add_child(lower_layer)
	var running_arms := preload("res://game/character/running_arms.gd").new()
	running_arms.name = "RunningArms"
	running_arms.character = character
	skeleton.add_child(running_arms)
	aim_spine = AimSpineModifier.new()
	aim_spine.weights = {"spine_01": 0.35, "spine_02": 0.65, "head": 0.0}
	skeleton.add_child(aim_spine)
	# Other weapon classes retain the existing procedural hold until their own fitted clips
	# are authored. This modifier is disabled for both studio rifles.
	arm_pose = ArmPoseModifier.new()
	skeleton.add_child(arm_pose)
	var facing := preload("res://game/character/kotm_pose_modifier.gd").new()
	facing.character = character
	facing.rig = studio_rig
	facing.visual = self
	skeleton.add_child(facing)
	leg_ik = preload("res://game/character/directional_leg_ik.gd").new()
	leg_ik.character = character
	leg_ik.rig = studio_rig
	skeleton.add_child(leg_ik)
	studio_rig.finish_modifiers()
	vehicle_contact = preload("res://game/character/vehicle_contact_ik.gd").new()
	vehicle_contact.name = "VehicleContact"
	vehicle_contact.character = character
	vehicle_contact.rig = studio_rig
	skeleton.add_child(vehicle_contact)
	var parachute_contact := preload("res://game/character/parachute_contact.gd").new()
	parachute_contact.name = "ParachuteContact"
	parachute_contact.character = character
	skeleton.add_child(parachute_contact)
	weapon_holder = WeaponHolder.new()
	weapon_holder.name = "HandR"
	weapon_holder.bone_name = "hand.r"
	weapon_holder.character = character
	weapon_holder.studio_rig = studio_rig
	skeleton.add_child(weapon_holder)
	character.fired.connect(func(_v: float, _h: float) -> void: weapon_holder.fire_effects())
	hat = studio_rig.roots.get(studio_rig.wardrobe.head)
	mask = studio_rig.roots.get(studio_rig.wardrobe.face)
	_build_canopy()
	anim = AnimationDriver.new()
	anim.name = "Anim"
	character.add_child.call_deferred(anim)

func _process_studio() -> void:
	var seated := character.in_vehicle()
	var parachuting := character.mode == Character.Mode.PARACHUTE
	var fitted := KOTMCharacterRig.WEAPONS.has(studio_rig.weapon_id)
	aim_spine.pitch = 0.0 if fitted or seated or parachuting else clampf(character.pitch, -0.9, 0.9)
	arm_pose.active = not parachuting and not fitted and not seated
	if fitted and not parachuting:
		arm_pose.weight = 0.0
	arm_pose.weapon_class = "parachute" if parachuting else (_held_class if not fitted and not seated else "")
	var aim := character.input.aim_dir if character.input.aim_dir.length_squared() > 0.5 else character.forward()
	arm_pose.aim_dir = skeleton.global_basis.inverse() * aim
	studio_rig.contact_enabled = fitted and not seated and not parachuting and character.combat.reload_t <= 0
	studio_rig.set_worn_shoes(character.health.shoes_id not in ["", "barefoot"])
	studio_rig.set_equipment(character.health.has_helmet(), character.health.has_armor(), character.inventory.backpack_id != "" or String(character.cosmetics.get("back", "")) != "")
	if fitted:
		studio_rig.weapon_root(studio_rig.weapon_id).visible = not seated and not parachuting
	weapon_holder.mount.visible = not seated and not parachuting
	canopy.visible = parachuting
