class_name CameraRig
extends Node3D
## Third-person over-the-shoulder camera (docs 04): aim zoom, scope view, first-person toggle,
## parachute pull-back, free look. Collides with buildings only (layer camera_blockers) and is
## clamped above the height field.

var target: Character
var yaw: float = 0.0
var pitch: float = 0.0
var free_look_yaw: float = 0.0
var first_person: bool = false
var aiming: bool = false
var scoped: bool = false
var recoil_pitch: float = 0.0
var recoil_yaw: float = 0.0
var look_enabled: bool = true
var cfg: Dictionary = DataLib.movement()["camera"]

@onready var pivot: Node3D = $Pivot
@onready var shoulder: Node3D = $Pivot/Shoulder
@onready var arm: SpringArm3D = $Pivot/Shoulder/Arm
@onready var camera: Camera3D = $Pivot/Shoulder/Arm/Camera3D

func _ready() -> void:
	arm.collision_mask = 32   # camera_blockers
	arm.margin = 0.08
	camera.fov = float(cfg["fov"])
	if Settings:
		first_person = Settings.first_person_default

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and look_enabled and (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or Input.mouse_mode == Input.MOUSE_MODE_VISIBLE):
		var sens: float = Settings.mouse_sensitivity if Settings else 0.0022
		if scoped:
			sens *= float(cfg["scopeSensMult"])
		elif aiming:
			sens *= float(cfg["aimSensMult"])
		var inv := -1.0 if (Settings and Settings.invert_y) else 1.0
		if Input.is_action_pressed("free_look"):
			free_look_yaw -= event.relative.x * sens
		else:
			yaw -= event.relative.x * sens
		var lim := deg_to_rad(float(cfg["pitchLimitDeg"]))
		pitch = clampf(pitch - event.relative.y * sens * inv, -lim, lim)
	if event.is_action_pressed("toggle_first_person"):
		first_person = not first_person

## Yaw the body should face: the camera yaw (free look does not turn the body).
func body_yaw() -> float:
	return yaw

func view_direction() -> Vector3:
	var y := yaw + free_look_yaw
	return Vector3(-sin(y) * cos(pitch), sin(pitch), -cos(y) * cos(pitch))

func kick(vertical_deg: float, horizontal_deg: float) -> void:
	var k := float(cfg["recoilToCamera"])
	pitch = minf(deg_to_rad(float(cfg["pitchLimitDeg"])), pitch + deg_to_rad(vertical_deg) * k)
	yaw += deg_to_rad(horizontal_deg) * k

## World direction from the muzzle to whatever the crosshair is on (camera-convergent aim).
func aim_direction(ch: Character) -> Vector3:
	var dir := view_direction()
	if ch == null or not is_inside_tree():
		return dir
	var from := camera.global_position
	var to := from + dir * 300.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 16)
	q.collide_with_areas = true
	q.exclude = [ch.get_rid()]
	var hit := space.intersect_ray(q)
	var point := to
	if not hit.is_empty() and not _is_own_hitbox(hit.get("collider"), ch):
		point = hit["position"]
	if ch.world:
		var t := ch.world.height_field.segment_hit(from, point, 2.0)
		if t > 0.0:
			point = from.lerp(point, t)
	var muzzle := ch.eye_position() + ch.right() * 0.28 - Vector3(0, 0.3, 0)
	var d := point - muzzle
	if d.length() < 1.5:
		return dir
	return d.normalized()

static func _is_own_hitbox(collider: Object, ch: Character) -> bool:
	return collider != null and collider is Node and (collider as Node).is_ancestor_of(ch) == false and ch.is_ancestor_of(collider)

var _bound: Character

func _process(_dt: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	if _bound != target:
		_bound = target
		target.fired.connect(kick)
	if not Input.is_action_pressed("free_look"):
		free_look_yaw = lerpf(free_look_yaw, 0.0, 0.25)
	aiming = target.input.pressed(CharacterInput.B_AIM) and target.mode != Character.Mode.PARACHUTE
	scoped = aiming and target.has_method("current_weapon_scoped") and target.current_weapon_scoped()
	var chute := target.mode == Character.Mode.PARACHUTE
	var fp := (first_person or scoped) and not chute
	var length: float
	if chute:
		length = float(cfg["armParachute"])
	elif fp:
		length = 0.0
	elif aiming:
		length = float(cfg["armAim"])
	else:
		length = float(cfg["armThirdPerson"])
	var side := 0.0 if fp else (float(cfg["shoulderAim"]) if aiming else float(cfg["shoulder"]))
	global_position = target.global_position + Vector3(0, target.height() + float(cfg["pivotOffset"]), 0)
	rotation = Vector3(pitch, yaw + free_look_yaw, 0)
	shoulder.position.x = side
	arm.spring_length = lerpf(arm.spring_length, length, 0.35)
	var fov := float(cfg["fovScope"]) if scoped else (float(cfg["fovAim"]) if aiming else float(cfg["fov"]))
	camera.fov = lerpf(camera.fov, fov, 0.35)
	# keep the camera above the terrain
	if target.world:
		var min_y := target.world.height_at(camera.global_position.x, camera.global_position.z) + float(cfg["terrainClamp"])
		if camera.global_position.y < min_y:
			camera.global_position.y = min_y
	# hide the local body in first person / scope via the visual layer
	target.visual.visible = not fp

func is_first_person_view() -> bool:
	return (first_person or scoped) and target != null and target.mode != Character.Mode.PARACHUTE
