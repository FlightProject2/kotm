class_name CharacterPreview
extends SubViewportContainer
## 3D character preview for the menus: the mannequin with the current cosmetic loadout, a gun in
## hand (optionally skinned), slowly turning on a lit pedestal in its own World3D.

const MANNEQUIN := preload("res://assets/characters/mannequiny/mannequiny-0.3.0.glb")

var viewport: SubViewport
var pivot: Node3D
var mannequin: Node3D
var skeleton: Skeleton3D
var hand_mount: BoneAttachment3D
var arm_pose: ArmPoseModifier
var gun_mount: Node3D
var cam: Camera3D
var loadout: Dictionary = {}
var weapon_id: String = "ar15"
var spin: float = 0.0
var auto_spin := true
var drag_spin := 0.0

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.world_3d = World3D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.66)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	cam = Camera3D.new()
	cam.environment = env
	cam.fov = 32.0
	viewport.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.05, 4.4), Vector3(0, 0.95, 0), Vector3.UP)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.7
	key.light_color = Color(1.0, 0.95, 0.88)
	key.rotation_degrees = Vector3(-42, 35, 0)
	key.shadow_enabled = true
	viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.6
	fill.light_color = Color(0.7, 0.8, 1.0)
	fill.rotation_degrees = Vector3(-15, -120, 0)
	viewport.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 1.2
	rim.light_color = Color(0.95, 0.4, 0.4)
	rim.rotation_degrees = Vector3(-25, 160, 0)
	viewport.add_child(rim)
	pivot = Node3D.new()
	viewport.add_child(pivot)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.7; cm.bottom_radius = 0.78; cm.height = 0.06
	disc.mesh = cm
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.12, 0.12, 0.14)
	dm.roughness = 0.35
	dm.metallic = 0.2
	disc.material_override = dm
	disc.position = Vector3(0, -0.03, 0)
	pivot.add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.76; tm.outer_radius = 0.8
	ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color("c8102e")
	rm.emission_enabled = true
	rm.emission = Color("c8102e")
	rm.emission_energy_multiplier = 1.6
	ring.material_override = rm
	ring.position = Vector3(0, 0.0, 0)
	pivot.add_child(ring)
	if loadout.is_empty():
		loadout = SkinSystem.default_loadout()
	rebuild()

func set_loadout(l: Dictionary) -> void:
	loadout = l.duplicate(true)
	rebuild()

func set_weapon(id: String) -> void:
	weapon_id = id
	_mount_gun()

func rebuild() -> void:
	if mannequin:
		mannequin.queue_free()
		mannequin = null
	mannequin = MANNEQUIN.instantiate()
	pivot.add_child(mannequin)
	var skels := mannequin.find_children("*", "Skeleton3D", true, false)
	skeleton = skels[0] if not skels.is_empty() else null
	SkinSystem.apply_to_character(mannequin, loadout)
	var att := SkinSystem.build_attachments(loadout)
	if skeleton:
		var head := BoneAttachment3D.new()
		head.bone_name = "head"
		skeleton.add_child(head)
		for m in mannequin.find_children("*", "MeshInstance3D", true, false):
			if (m as MeshInstance3D).skin != null:
				head.add_child(SkinSystem.build_face(skeleton, (m as MeshInstance3D).mesh, loadout))
				break
		if att["hat"]:
			att["hat"].position = Vector3(0, 0.04, 0)
			head.add_child(att["hat"])
		if att["mask"]:
			head.add_child(att["mask"])
		var chest := BoneAttachment3D.new()
		chest.bone_name = "spine_02"
		skeleton.add_child(chest)
		if att["back"]:
			chest.add_child(att["back"])
		arm_pose = ArmPoseModifier.new()
		arm_pose.aim_dir = Vector3(0.15, -0.3, 1.0)
		skeleton.add_child(arm_pose)
		hand_mount = BoneAttachment3D.new()
		hand_mount.bone_name = "hand.r"
		skeleton.add_child(hand_mount)
		gun_mount = Node3D.new()
		hand_mount.add_child(gun_mount)
		skeleton.skeleton_updated.connect(_align_gun)
	var players := mannequin.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		var ap: AnimationPlayer = players[0]
		var clip := "fight_idle" if ap.has_animation("fight_idle") else "idle"
		if ap.has_animation(clip):
			ap.play(clip)
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_mount_gun()

func _mount_gun() -> void:
	if gun_mount == null:
		return
	for c in gun_mount.get_children():
		c.queue_free()
	if weapon_id == "" or not WeaponHolder.MODELS.has(weapon_id):
		return
	var scene: PackedScene = load(WeaponHolder.MODELS[weapon_id])
	if scene == null:
		return
	var model: Node3D = scene.instantiate()
	gun_mount.add_child(model)
	var wclass := String(ItemCatalog.get_item(weapon_id).get("class", "rifle"))
	WeaponHolder.fit_model(model, wclass)
	if arm_pose:
		arm_pose.weapon_class = wclass
	if WeaponHolder.TINTS.has(weapon_id):
		WeaponHolder._tint(model, WeaponHolder.TINTS[weapon_id])
	var skins: Dictionary = loadout.get("weapons", {})
	if skins.has(weapon_id):
		SkinSystem.apply_to_weapon(model, SkinSystem.weapon_skin(String(skins[weapon_id])))

func _align_gun() -> void:
	if gun_mount == null or not gun_mount.is_inside_tree():
		return
	# The mannequin faces +Z in its own space; point the barrel (-Z of the mount) that way, a
	# little downward like a relaxed low-ready.
	var fwd := (pivot.global_transform.basis * Vector3(0.15, -0.3, 1.0)).normalized()
	var origin := hand_mount.global_transform.origin + hand_mount.global_transform.basis * Vector3(0, -0.02, 0)
	gun_mount.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), origin)

func _process(dt: float) -> void:
	if auto_spin and absf(drag_spin) < 0.001:
		spin += dt * 0.35
	spin += drag_spin
	drag_spin = lerpf(drag_spin, 0.0, minf(1.0, dt * 6.0))
	pivot.rotation.y = spin

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		drag_spin = event.relative.x * 0.01
		accept_event()
