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

func _ready() -> void:
	character = get_parent() as Character
	var skels := find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	skeleton = skels[0]
	if character.cosmetics.is_empty():
		character.cosmetics = SkinSystem.default_loadout()
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
	var att := SkinSystem.build_attachments(character.cosmetics, _head_fit(body))
	if att["hat"]:
		hat = att["hat"]
		# a model-based hat comes back already sized and seated on the head
		if not hat.has_meta("fitted"):
			hat.position = Vector3(0, 0.04, 0.0)
		head_mount.add_child(hat)
	if att["mask"]:
		mask = att["mask"]
		head_mount.add_child(mask)
	var chest_mount := BoneAttachment3D.new()
	chest_mount.name = "ChestMount"
	chest_mount.bone_name = "spine_02"
	skeleton.add_child(chest_mount)
	armor_mesh = _build_armor()
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
		rotation.y = character.yaw

func _process(dt: float) -> void:
	if character == null:
		return
	if crouch_pose:
		crouch_pose.crouching = character.crouching and character.mode == Character.Mode.GROUND
	if aim_spine:
		aim_spine.pitch = character.pitch
	if arm_pose and skeleton:
		# arms only hold the gun on foot; the parachute and melee keep the clip's arms
		arm_pose.weapon_class = "parachute" if character.mode == Character.Mode.PARACHUTE else _held_class
		var aim: Vector3 = character.input.aim_dir if character.input.aim_dir.length_squared() > 0.5 else \
			Vector3(-sin(character.yaw) * cos(character.pitch), sin(character.pitch), -cos(character.yaw) * cos(character.pitch))
		arm_pose.aim_dir = skeleton.global_transform.basis.inverse() * aim
	# the gun goes away under the canopy: both hands are on the risers
	if weapon_holder and weapon_holder.mount:
		weapon_holder.mount.visible = character.mode != Character.Mode.PARACHUTE
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

## Head-bone-local transform that seats a hat model on this character's head: scaled a little
## wider than the skull, with the model's opening plane at the widest part of it.
func _head_fit(body: MeshInstance3D) -> Transform3D:
	if skeleton == null:
		return Transform3D.IDENTITY
	var hb := SkinSystem.head_bounds(body.mesh) if body else AABB(Vector3(-0.1, 1.55, -0.1), Vector3(0.2, 0.25, 0.2))
	var width := ModelLib.aabb(SkinSystem.CAP_MODEL).size.x
	if width < 0.01:
		return Transform3D.IDENTITY
	var scale := (hb.size.x * 1.05) / width
	var opening := Vector3(hb.get_center().x, hb.position.y + hb.size.y * 0.60, hb.get_center().z)
	var to_bone := skeleton.get_bone_global_rest(skeleton.find_bone("head")).affine_inverse()
	return to_bone * Transform3D(Basis().scaled(Vector3.ONE * scale), opening)

## A plate carrier that follows the torso instead of a box floating off it: front and back plates
## joined by shoulder straps, each plate narrower than the chest so nothing pokes through the arms.
func _build_armor() -> MeshInstance3D:
	const HALF_W := 0.155      # plate half-width: the mannequin's chest is about 0.34 m across
	const TOP := 0.27
	const BOT := -0.02
	const DEPTH := 0.115       # how far each plate stands off the spine
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# each plate is a shallow shell: the outer face is bowed forward at the centre so it reads as
	# curved armour rather than a slab
	for face: float in [1.0, -1.0]:
		var z: float = DEPTH * face
		var bow: float = 0.035 * face
		var rows := [[BOT, HALF_W * 0.86], [BOT + 0.10, HALF_W], [TOP - 0.09, HALF_W], [TOP, HALF_W * 0.62]]
		for r in rows.size() - 1:
			var y0: float = rows[r][0]; var w0: float = rows[r][1]
			var y1: float = rows[r + 1][0]; var w1: float = rows[r + 1][1]
			for s in 4:
				var t0 := -1.0 + 2.0 * float(s) / 4.0
				var t1 := -1.0 + 2.0 * float(s + 1) / 4.0
				var a := Vector3(w0 * t0, y0, z + bow * (1.0 - t0 * t0))
				var b := Vector3(w0 * t1, y0, z + bow * (1.0 - t1 * t1))
				var c := Vector3(w1 * t1, y1, z + bow * (1.0 - t1 * t1))
				var d := Vector3(w1 * t0, y1, z + bow * (1.0 - t0 * t0))
				if face > 0.0:
					st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
					st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
				else:
					st.add_vertex(a); st.add_vertex(c); st.add_vertex(b)
					st.add_vertex(a); st.add_vertex(d); st.add_vertex(c)
	# shoulder straps over the top, one each side, joining the two plates
	for sx: float in [-1.0, 1.0]:
		var x0: float = sx * HALF_W * 0.30
		var x1: float = sx * HALF_W * 0.62
		for face: float in [1.0, -1.0]:
			var za: float = DEPTH * face
			var zb := 0.0
			var ya := TOP
			var yb := TOP + 0.055
			var p0 := Vector3(x0, ya, za); var p1 := Vector3(x1, ya, za)
			var p2 := Vector3(x1, yb, zb); var p3 := Vector3(x0, yb, zb)
			st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
			st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p3)
			st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p1)
			st.add_vertex(p0); st.add_vertex(p3); st.add_vertex(p2)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Armor"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.9
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.visible = false
	return mi

## The studio military backpack on the upper back; visible with a backpack item or back cosmetic.
func _build_backpack(chest_mount: Node3D) -> MeshInstance3D:
	if not ModelLib.exists("military_backpack") or skeleton == null:
		return null
	var mi := ModelLib.instance("military_backpack")
	if mi.mesh == null:
		return null
	var chest_bi := skeleton.find_bone("spine_02")
	var chest_rest := skeleton.get_bone_global_rest(chest_bi)
	var sz := ModelLib.aabb("military_backpack").size
	var scale := 0.46 / maxf(sz.y, 0.01)
	# the artist's Backpack_Socket is the point that touches the wearer's back; the mannequin's
	# back surface sits about 0.14 m behind the spine_02 bone (it faces +Z, so back is -Z)
	var socket := ModelLib.socket("military_backpack", "Backpack_Socket", Vector3(0, 0, 0.06))
	var back_point := chest_rest.origin + Vector3(0, 0.04, -0.15)
	var pos := back_point - socket * scale
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
