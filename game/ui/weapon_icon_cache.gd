class_name WeaponIconCache
extends Node
## Renders each weapon model once, side-on, into a small SubViewport and caches the result as a
## texture for the hotbar (so the gun bar shows the actual gun, not just its name). Icons are
## rendered lazily the first time a weapon shows up in a slot; headless runs never get here
## because the HUD is only built for a local player with a real display.

const ICON_SIZE := Vector2i(112, 56)
const ICON_LENGTH := 1.0   ## world metres the icon frame spans horizontally

var _icons: Dictionary = {}          # weapon_id -> ImageTexture
var _pending: Dictionary = {}        # weapon_id -> SubViewport
var _frames_left: Dictionary = {}    # weapon_id -> int

signal icon_ready(weapon_id: String, texture: Texture2D)

func get_icon(weapon_id: String) -> Texture2D:
	if _icons.has(weapon_id):
		return _icons[weapon_id]
	if weapon_id == "" or not WeaponHolder.MODELS.has(weapon_id):
		return null
	if not _pending.has(weapon_id):
		_start_render(weapon_id)
	return null

func has_model(weapon_id: String) -> bool:
	return WeaponHolder.MODELS.has(weapon_id)

func _start_render(weapon_id: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var scene: PackedScene = load(WeaponHolder.MODELS[weapon_id])
	if scene == null:
		return
	var vp := SubViewport.new()
	vp.size = ICON_SIZE
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_4X
	var world := World3D.new()
	vp.world_3d = world
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 1.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var cam := Camera3D.new()
	cam.environment = env
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = ICON_LENGTH * float(ICON_SIZE.y) / float(ICON_SIZE.x) * 1.0
	cam.near = 0.01
	cam.far = 10.0
	vp.add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.rotation_degrees = Vector3(-38, 30, 0)
	vp.add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.light_energy = 0.7
	rim.light_color = Color(0.7, 0.8, 1.0)
	rim.rotation_degrees = Vector3(-20, -140, 0)
	vp.add_child(rim)

	var mount := Node3D.new()
	var model: Node3D = scene.instantiate()
	mount.add_child(model)
	vp.add_child(mount)
	var wclass := _class_of(weapon_id)
	var fit := WeaponHolder.fit_model(model, wclass)
	if WeaponHolder.TINTS.has(weapon_id):
		WeaponHolder._tint(model, WeaponHolder.TINTS[weapon_id])
	# fit_model puts the grip at the origin with the barrel along -Z. Show the gun side-on:
	# rotate so -Z (barrel) points to +X (screen right), camera looks down -Z at the XY plane.
	mount.rotation = Vector3(0, -PI * 0.5, 0)
	var length: float = maxf(fit["length"], 0.3)
	var muzzle: Vector3 = fit["muzzle"]
	# centre the gun horizontally: grip at x = 0 so the barrel tip is at x = length*(1-grip)
	var grip_frac: float = WeaponHolder.GRIP_FRACTION.get(wclass, 0.35)
	var centre_x := length * (0.5 - grip_frac)
	var scale := minf(1.0, (ICON_LENGTH * 0.9) / length)
	mount.scale = Vector3.ONE * scale
	mount.position = Vector3(-centre_x * scale, -muzzle.y * scale * 0.5, 0)
	add_child(vp)
	cam.look_at_from_position(Vector3(0, 0, 3), Vector3.ZERO, Vector3.UP)
	_pending[weapon_id] = vp
	_frames_left[weapon_id] = 3

func _process(_dt: float) -> void:
	if _pending.is_empty():
		return
	for id in _pending.keys():
		_frames_left[id] -= 1
		if _frames_left[id] > 0:
			continue
		var vp: SubViewport = _pending[id]
		var img := vp.get_texture().get_image()
		if img == null or img.is_empty():
			continue
		var tex := ImageTexture.create_from_image(img)
		_icons[id] = tex
		_pending.erase(id)
		_frames_left.erase(id)
		vp.queue_free()
		icon_ready.emit(id, tex)

static func _class_of(weapon_id: String) -> String:
	var item := ItemCatalog.get_item(weapon_id)
	return String(item.get("class", "rifle"))
