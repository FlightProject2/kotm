class_name HitboxRig
extends Node
## Creates one Area3D per hit region (docs 06) and moves them every physics tick from the
## skeleton's bone poses. Areas live on physics layer 3 (hitboxes) and carry metadata:
## "region" (String) and "character" (Character).

const REGIONS := [
	# region, bone, child bone (for alignment; "" = sphere), shape, radius, length pad
	["head", "head", "", "sphere", 0.13, 0.0],
	["neck", "neck_01", "head", "capsule", 0.07, 0.0],
	["upperTorso", "spine_02", "neck_01", "box", 0.19, 0.02],
	["lowerTorso", "spine_01", "spine_02", "box", 0.17, 0.04],
	["arms", "upperarm.l", "lowerarm.l", "capsule", 0.065, 0.0],
	["arms", "upperarm.r", "lowerarm.r", "capsule", 0.065, 0.0],
	["arms", "lowerarm.l", "hand.l", "capsule", 0.055, 0.0],
	["arms", "lowerarm.r", "hand.r", "capsule", 0.055, 0.0],
	["upperLegs", "thigh.l", "calf.l", "capsule", 0.095, 0.0],
	["upperLegs", "thigh.r", "calf.r", "capsule", 0.095, 0.0],
	["lowerLegs", "calf.l", "foot.l", "capsule", 0.075, 0.0],
	["lowerLegs", "calf.r", "foot.r", "capsule", 0.075, 0.0],
	["lowerLegs", "foot.l", "ball.l", "capsule", 0.06, 0.03],
	["lowerLegs", "foot.r", "ball.r", "capsule", 0.06, 0.03],
]

var character: Character
var skeleton: Skeleton3D
var areas: Array[Area3D] = []
var _bone_idx: Array[int] = []
var _local: Array[Transform3D] = []   # shape transform relative to the bone pose

func _ready() -> void:
	character = get_parent() as Character
	var visual: Node = character.get_node_or_null("Visual")
	var skels: Array[Node] = visual.find_children("*", "Skeleton3D", true, false) if visual else []
	skeleton = skels[0] if skels.size() > 0 else null
	if skeleton == null:
		push_warning("HitboxRig: no Skeleton3D under Visual")
		return
	for r in REGIONS:
		var bi := skeleton.find_bone(r[1])
		if bi < 0:
			push_warning("HitboxRig: missing bone " + r[1])
			continue
		var shape: Shape3D
		var local := Transform3D.IDENTITY
		var axis := Vector3.UP
		var length := 0.0
		if r[2] != "":
			var ci := skeleton.find_bone(r[2])
			var rest_parent := skeleton.get_bone_global_rest(bi)
			var rest_child := skeleton.get_bone_global_rest(ci)
			var v: Vector3 = rest_parent.affine_inverse() * rest_child.origin
			length = v.length()
			axis = v.normalized() if length > 0.001 else Vector3.UP
		match r[3]:
			"sphere":
				var s := SphereShape3D.new(); s.radius = r[4]; shape = s
			"capsule":
				var s := CapsuleShape3D.new(); s.radius = r[4]; s.height = length + 2.0 * r[4] + r[5]; shape = s
			"box":
				var s := BoxShape3D.new(); s.size = Vector3(r[4] * 2.0, length + r[5], r[4] * 1.3); shape = s
		if r[2] != "":
			# align the shape's Y axis with the bone->child direction, centred on the bone segment
			local = Transform3D(_basis_from_y(axis), axis * (length * 0.5))
		var area := Area3D.new()
		area.name = "Hit_" + r[1].replace(".", "_")
		area.collision_layer = 4
		area.collision_mask = 0
		area.monitoring = false
		area.monitorable = true
		area.set_meta("region", r[0])
		area.set_meta("character", character)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.transform = local
		area.add_child(cs)
		add_child(area)
		areas.append(area)
		_bone_idx.append(bi)
		_local.append(Transform3D.IDENTITY)
	# Bone poses include modifiers only right after the skeleton update, so follow that signal
	# (the same way BoneAttachment3D does) instead of sampling during the physics step.
	skeleton.skeleton_updated.connect(_update_transforms)
	_update_transforms()

static func _basis_from_y(y: Vector3) -> Basis:
	var up := y.normalized()
	var helper := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := helper.cross(up).normalized()
	var z := x.cross(up).normalized()
	return Basis(x, up, z)

func _update_transforms() -> void:
	if skeleton == null:
		return
	var skel_xf := skeleton.global_transform
	for i in areas.size():
		var pose := skel_xf * skeleton.get_bone_global_pose(_bone_idx[i])
		areas[i].global_transform = pose.orthonormalized()

func rids() -> Array[RID]:
	var out: Array[RID] = []
	for a in areas:
		out.append(a.get_rid())
	return out

func set_enabled(on: bool) -> void:
	for a in areas:
		a.monitorable = on
		a.collision_layer = 4 if on else 0

## Region name for a physics hit on one of our areas, or "" if not ours.
static func region_of(collider: Object) -> String:
	if collider is Area3D and collider.has_meta("region"):
		return collider.get_meta("region")
	return ""

static func character_of(collider: Object) -> Character:
	if collider is Area3D and collider.has_meta("character"):
		return collider.get_meta("character")
	return null
