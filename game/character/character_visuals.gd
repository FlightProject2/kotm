class_name CharacterVisuals
extends Node3D
## Owns the mannequin: facing, crouch squash, aim spine, weapon mount, helmet/armor meshes.
## Runs on every peer (purely cosmetic).

var character: Character
var skeleton: Skeleton3D
var aim_spine: AimSpineModifier
var weapon_holder: WeaponHolder
var helmet_mesh: MeshInstance3D
var armor_mesh: MeshInstance3D
var anim: AnimationDriver

func _ready() -> void:
	character = get_parent() as Character
	var skels := find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		return
	skeleton = skels[0]
	aim_spine = AimSpineModifier.new()
	aim_spine.name = "AimSpine"
	skeleton.add_child(aim_spine)
	weapon_holder = WeaponHolder.new()
	weapon_holder.name = "HandR"
	weapon_holder.bone_name = "hand.r"
	skeleton.add_child(weapon_holder)
	var head_mount := BoneAttachment3D.new()
	head_mount.name = "HeadMount"
	head_mount.bone_name = "head"
	skeleton.add_child(head_mount)
	helmet_mesh = MeshInstance3D.new()
	var hm := SphereMesh.new(); hm.radius = 0.15; hm.height = 0.2
	helmet_mesh.mesh = hm
	helmet_mesh.position = Vector3(0, 0.06, 0)
	helmet_mesh.visible = false
	head_mount.add_child(helmet_mesh)
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
	anim = AnimationDriver.new()
	anim.name = "Anim"
	character.add_child.call_deferred(anim)

func _process(_dt: float) -> void:
	if character == null:
		return
	rotation.y = character.yaw
	var target_scale := 0.67 if character.crouching else 1.0
	scale.y = lerpf(scale.y, target_scale, 0.3)
	if aim_spine:
		aim_spine.pitch = character.pitch
	if helmet_mesh:
		helmet_mesh.visible = character.health.has_helmet()
		if character.health.has_helmet():
			var col := Color(0.15, 0.35, 0.7) if character.health.helmet_id == "motorcycle_helmet" else Color(0.25, 0.3, 0.18)
			_set_color(helmet_mesh, col)
	if armor_mesh:
		armor_mesh.visible = character.health.has_armor()
		if character.health.has_armor():
			_set_color(armor_mesh, Color(0.3, 0.36, 0.17) if character.health.armor_id == "laminated_armor" else Color(0.4, 0.4, 0.42))

static func _set_color(mi: MeshInstance3D, c: Color) -> void:
	var m := mi.material_override as StandardMaterial3D
	if m == null:
		m = StandardMaterial3D.new()
		mi.material_override = m
	m.albedo_color = c

func show_weapon(weapon_id: String, weapon_class: String) -> void:
	if weapon_holder:
		weapon_holder.set_weapon(weapon_id, weapon_class)
	if anim:
		anim.armed = weapon_class != "melee" and weapon_id != ""
