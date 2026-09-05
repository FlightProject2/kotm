class_name WeaponHolder
extends BoneAttachment3D
## Holds the current weapon model on the right hand bone. Models are auto-fitted by their AABB
## so any CC0 gun ends up the right length with its grip at the hand.

const TARGET_LENGTH := {"rifle": 0.85, "sniper": 1.1, "shotgun": 1.0, "smg": 0.6, "pistol": 0.26, "bow": 1.2, "melee": 0.45}
const MODELS := {
	"ar15": "res://assets/kenney/weapon/machinegun.glb", "ak47": "res://assets/kenney/weapon/machinegun.glb",
	"hunting_rifle": "res://assets/kenney/weapon/sniper.glb", "shotgun_12g": "res://assets/kenney/weapon/shotgun.glb",
	"hellfire": "res://assets/kenney/weapon/uzi.glb", "m9": "res://assets/kenney/weapon/pistol.glb",
	"r380": "res://assets/kenney/weapon/pistol.glb", "m1911": "res://assets/kenney/weapon/pistol.glb",
	"magnum44": "res://assets/quaternius/guns/Revolver.fbx", "combat_knife": "res://assets/kenney/weapon/knife_sharp.glb",
}
const TINTS := {"ak47": Color(0.45, 0.3, 0.18), "r380": Color(0.6, 0.6, 0.62), "m1911": Color(0.35, 0.3, 0.25)}
## Hand-tuned offsets per weapon class (position in hand space, euler degrees). Tune in the editor.
@export var mount_offset := Vector3(0.02, 0.0, 0.0)
@export var mount_rotation_deg := Vector3(0.0, 90.0, 0.0)

var mount: Node3D
var current_id: String = ""
var character: Node

func _ready() -> void:
	mount = Node3D.new()
	mount.name = "WeaponMount"
	add_child(mount)
	mount.position = mount_offset
	mount.rotation_degrees = mount_rotation_deg

func set_weapon(weapon_id: String, weapon_class: String) -> void:
	if weapon_id == current_id:
		return
	current_id = weapon_id
	for c in mount.get_children():
		c.queue_free()
	if weapon_id == "" or weapon_id == "fists" or not MODELS.has(weapon_id):
		return
	var scene: PackedScene = load(MODELS[weapon_id])
	if scene == null:
		return
	var model := scene.instantiate()
	mount.add_child(model)
	var aabb := _merged_aabb(model)
	var longest := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var target: float = TARGET_LENGTH.get(weapon_class, 0.8)
	var s := target / maxf(longest, 0.001)
	model.scale = Vector3.ONE * s
	# Barrel along the model's longest axis: rotate so it points along -Z of the mount.
	if aabb.size.x >= aabb.size.y and aabb.size.x >= aabb.size.z:
		model.rotation_degrees.y = -90.0
	elif aabb.size.y >= aabb.size.z:
		model.rotation_degrees.x = 90.0
	# Put the grip (30% from the back) at the hand.
	model.position = -Vector3(0, 0, -(aabb.position.z + aabb.size.z * 0.3)) * s if aabb.size.z >= aabb.size.x else Vector3(0, 0, 0)
	if TINTS.has(weapon_id):
		_tint(model, TINTS[weapon_id])
	if character and character.get("cosmetics") != null:
		var skins: Dictionary = character.cosmetics.get("weapons", {})
		if skins.has(weapon_id):
			SkinSystem.apply_to_weapon(model, SkinSystem.weapon_skin(String(skins[weapon_id])))

static func _merged_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = (m as MeshInstance3D).get_aabb()
		a = (m as Node3D).transform * a
		out = a if first else out.merge(a)
		first = false
	return out

static func _tint(n: Node, color: Color) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mi.set_surface_override_material(i, mat)
