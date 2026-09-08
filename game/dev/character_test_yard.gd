extends Node3D
## Playable integration yard: the real Character, Combat, Motor, CameraRig and Vehicle.
var character: Character
var camera_rig: CameraRig
var status: Label
var wardrobe := {"top": "DefaultTank", "bottom": "DefaultBoxers", "head": "None", "face": "None", "feet": "None"}
const OPTIONS := {
	"top": ["DefaultTank", "TankTop", "TShirt", "Hoodie"],
	"bottom": ["DefaultBoxers", "Shorts", "Leggings"],
	"head": ["None", "BaseballCap", "Beanie", "MotorcycleHelmet"],
	"face": ["None", "Sunglasses", "FaceBandana"],
	"feet": ["None", "Sneakers"],
}

func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.13, 0.18, 0.22)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.87, 1.0)
	environment.environment.ambient_light_energy = 0.7
	add_child(environment)
	character = preload("res://game/character/character.tscn").instantiate()
	character.name = "TestPlayer"
	character.display_name = "Character test"
	character.position = Vector3(0, 0.06, 3)
	character.cosmetics = SkinSystem.default_loadout()
	add_child(character)
	character.inventory.give_weapon("ar15")
	character.inventory.give_weapon("hunting_rifle")
	character.inventory.give_ammo("223", 240)
	character.inventory.give_ammo("308", 60)
	character.inventory.select(0)
	camera_rig = preload("res://game/camera/camera_rig.tscn").instantiate()
	add_child(camera_rig)
	camera_rig.target = character
	camera_rig.first_person = false
	var input := PlayerInputSource.new()
	input.character = character
	input.camera_rig = camera_rig
	character.add_child(input)
	var vehicle := Vehicle.new()
	add_child(vehicle)
	vehicle.setup("atv", null)
	vehicle.position = Vector3(-5, 0, 3)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(24, 22)
	status.add_theme_font_size_override("font_size", 18)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(status)
	var crosshair := Label.new()
	crosshair.text = "+"
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = get_viewport().get_visible_rect().size * 0.5
	canvas.add_child(crosshair)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_dt: float) -> void:
	if character == null or status == null:
		return
	var clip: String = character.visual.anim.current if character.visual.anim else "Loading"
	status.text = "KOTM / IN-GAME CHARACTER TEST\nWASD move · Shift sprint · C crouch · Space jump · Q shoulder\n1 fists · 2 AR-75 · 3 hunting rifle · RMB aim/scope · LMB fire · R reload\nF enter/exit vehicle · Esc cursor\n7 top · 8 bottom · 9 headwear · 0 footwear · K face\nF5 helmet · F6 armour · F7 backpack\n\n%s\n%s / %s / %s\n%s" % [character.inventory.current_id(), wardrobe.top, wardrobe.bottom, wardrobe.head, clip]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_7: cycle("top")
		KEY_8: cycle("bottom")
		KEY_9: cycle("head")
		KEY_0: cycle("feet")
		KEY_K: cycle("face")
		KEY_F5:
			if character.health.has_helmet(): character.health.remove_helmet()
			else: character.health.set_helmet("motorcycle_helmet")
		KEY_F6:
			if character.health.has_armor(): character.health.remove_armor()
			else: character.health.set_armor("laminated_armor")
		KEY_F7:
			character.inventory.backpack_id = "military_backpack" if character.inventory.backpack_id == "" else ""

func cycle(slot: String) -> void:
	var options: Array = OPTIONS[slot]
	wardrobe[slot] = options[(options.find(wardrobe[slot]) + 1) % options.size()]
	character.cosmetics["kotm_wardrobe"] = wardrobe.duplicate()
	character.visual.studio_rig.apply_loadout(character.cosmetics)
