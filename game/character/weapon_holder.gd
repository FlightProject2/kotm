class_name WeaponHolder
extends BoneAttachment3D
## Holds the current weapon model on the right hand and aims it procedurally: the mount is
## re-oriented after every skeleton update so the barrel follows the character's aim direction
## (the mannequin has no gun-holding animation). Models are auto-fitted: the thin end of the
## longest axis is the barrel, scaled to a per-class length, grip placed at the hand, and a
## "Muzzle" marker sits at the barrel tip for projectiles, tracers and the flash.

const TARGET_LENGTH := {"rifle": 0.82, "sniper": 1.1, "shotgun": 1.0, "smg": 0.58, "pistol": 0.26, "bow": 1.2, "melee": 0.4}
const GRIP_FRACTION := {"rifle": 0.38, "sniper": 0.4, "shotgun": 0.4, "smg": 0.35, "pistol": 0.15, "bow": 0.5, "melee": 0.2}
const MODELS := {
	"ar15": "res://assets/kenney/weapon/machinegun.glb", "ak47": "res://assets/kenney/weapon/machinegun.glb",
	"hunting_rifle": "res://assets/kenney/weapon/sniper.glb", "shotgun_12g": "res://assets/kenney/weapon/shotgun.glb",
	"hellfire": "res://assets/kenney/weapon/uzi.glb", "m9": "res://assets/kenney/weapon/pistol.glb",
	"r380": "res://assets/kenney/weapon/pistol.glb", "m1911": "res://assets/kenney/weapon/pistol.glb",
	"magnum44": "res://assets/quaternius/guns/Revolver.fbx", "combat_knife": "res://assets/kenney/weapon/knife_sharp.glb",
}
const TINTS := {"ak47": Color(0.45, 0.3, 0.18), "r380": Color(0.6, 0.6, 0.62), "m1911": Color(0.35, 0.3, 0.25)}
## Where the grip sits relative to the hand bone (hand space). Tune in the editor.
@export var grip_offset := Vector3(0.0, -0.02, 0.0)
## Max angle the gun may deviate from the arm's natural direction while tracking the aim.
@export var max_track_deg := 75.0

var mount: Node3D
var muzzle: Marker3D
var flash: Node3D
var current_id: String = ""
var current_class: String = ""
var character: Node
var length: float = 0.0
var _flash_t: float = 0.0
var _kick: float = 0.0
var _last_dir: Vector3 = Vector3.FORWARD

func _ready() -> void:
	mount = Node3D.new()
	mount.name = "WeaponMount"
	add_child(mount)
	muzzle = Marker3D.new()
	muzzle.name = "Muzzle"
	mount.add_child(muzzle)
	_build_flash()
	var skel := get_parent() as Skeleton3D
	if skel:
		skel.skeleton_updated.connect(_align)

func _build_flash() -> void:
	flash = Node3D.new()
	flash.name = "MuzzleFlash"
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.28, 0.28)
	q.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.85, 0.5, 0.9)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material_override = m
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.add_child(q)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.5)
	light.light_energy = 3.0
	light.omni_range = 4.0
	light.shadow_enabled = false
	flash.add_child(light)
	flash.visible = false
	mount.add_child(flash)

func set_weapon(weapon_id: String, weapon_class: String) -> void:
	if weapon_id == current_id:
		return
	current_id = weapon_id
	current_class = weapon_class
	for c in mount.get_children():
		if c != muzzle and c != flash:
			c.queue_free()
	length = 0.0
	muzzle.position = Vector3(0, 0, -0.5)
	if weapon_id == "" or weapon_id == "fists" or not MODELS.has(weapon_id):
		return
	var scene: PackedScene = load(MODELS[weapon_id])
	if scene == null:
		return
	var model: Node3D = scene.instantiate()
	mount.add_child(model)
	var fit := fit_model(model, weapon_class)
	length = fit["length"]
	muzzle.position = fit["muzzle"]
	flash.position = fit["muzzle"]
	if TINTS.has(weapon_id):
		_tint(model, TINTS[weapon_id])
	if character and character.get("cosmetics") != null:
		var skins: Dictionary = character.cosmetics.get("weapons", {})
		if skins.has(weapon_id):
			SkinSystem.apply_to_weapon(model, SkinSystem.weapon_skin(String(skins[weapon_id])))

func has_weapon_model() -> bool:
	return length > 0.0

func muzzle_global() -> Vector3:
	return muzzle.global_position

## Fires the flash and a small kick; called from the character's fired signal.
func fire_effects() -> void:
	_flash_t = 0.045
	_kick = 0.05
	flash.visible = true
	flash.rotation.z = randf() * TAU

func _process(dt: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= dt
		if _flash_t <= 0.0:
			flash.visible = false
	_kick = maxf(0.0, _kick - dt * 0.6)

## Orient the mount so its -Z follows the aim direction, at the hand position.
func _align() -> void:
	if character == null or not is_inside_tree():
		return
	var dir: Vector3 = _last_dir
	var inp = character.get("input")
	if inp != null and inp.aim_dir.length_squared() > 0.5 and character.get("mode") != 2:
		dir = inp.aim_dir.normalized()
	else:
		var yaw: float = character.yaw
		var pitch: float = character.pitch
		dir = Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	_last_dir = dir
	var hand := global_transform
	var origin := hand.origin + hand.basis * grip_offset
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.FORWARD
	var basis := Basis.looking_at(dir, up)
	mount.global_transform = Transform3D(basis, origin + dir * -_kick)

# ---------- model fitting ----------
## Returns {"length": float, "muzzle": Vector3 (mount space)} and sets the model transform so the
## barrel runs along -Z from the grip at the origin.
static func fit_model(model: Node3D, weapon_class: String) -> Dictionary:
	var verts := _gather_vertices(model)
	if verts.is_empty():
		return {"length": 0.0, "muzzle": Vector3(0, 0, -0.5)}
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	var axis := 0
	if aabb.size.y >= aabb.size.x and aabb.size.y >= aabb.size.z:
		axis = 1
	elif aabb.size.z >= aabb.size.x:
		axis = 2
	var centre := aabb.get_center()
	# Thin end = barrel: compare the spread of the two halves on the other axes.
	var spread_pos := 0.0
	var spread_neg := 0.0
	var n_pos := 0
	var n_neg := 0
	for v in verts:
		var d := v - centre
		var along := d[axis]
		var lateral := (d - Vector3.ZERO)
		lateral[axis] = 0.0
		if along >= 0.0:
			spread_pos += lateral.length_squared(); n_pos += 1
		else:
			spread_neg += lateral.length_squared(); n_neg += 1
	spread_pos /= maxf(n_pos, 1)
	spread_neg /= maxf(n_neg, 1)
	var muzzle_sign := 1.0 if spread_pos < spread_neg else -1.0
	var length_model := aabb.size[axis]
	var target: float = TARGET_LENGTH.get(weapon_class, 0.8)
	var s := target / maxf(length_model, 0.001)
	# Rotation: map the model's barrel axis (with sign) onto -Z; keep model +Y up when possible.
	var barrel := Vector3.ZERO
	barrel[axis] = muzzle_sign
	var up_model := Vector3.UP if axis != 1 else Vector3.BACK
	var basis := Basis.looking_at(barrel, up_model).inverse()   # model -> mount: barrel -> -Z
	var grip_frac: float = GRIP_FRACTION.get(weapon_class, 0.35)
	# Point in model space that should sit at the hand: grip_frac along the length from the back.
	var grip := centre
	grip[axis] = centre[axis] - muzzle_sign * (0.5 - grip_frac) * length_model
	model.transform = Transform3D(basis.scaled(Vector3.ONE * s), -(basis * grip) * s)
	var front := centre
	front[axis] = centre[axis] + muzzle_sign * 0.5 * length_model
	var muzzle_local: Vector3 = model.transform * front
	muzzle_local.x = 0.0
	return {"length": target, "muzzle": muzzle_local}

static func _gather_vertices(model: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != model:
			if n is Node3D:
				xf = (n as Node3D).transform * xf
			n = n.get_parent()
		for i in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(i)
			var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var step := maxi(1, vs.size() / 400)
			for k in range(0, vs.size(), step):
				out.append(xf * vs[k])
	return out

static func _tint(n: Node, color: Color) -> void:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var mat := StandardMaterial3D.new()
			mat.albedo_color = color
			mi.set_surface_override_material(i, mat)
