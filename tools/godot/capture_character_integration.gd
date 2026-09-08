extends SceneTree
## Native-render evidence using the production character/controller in the playable yard.
var yard: Node3D
var ch
var report := {"captures": [], "engine": Engine.get_version_info().string}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame
	yard = load("res://game/dev/character_test_yard.tscn").instantiate()
	root.add_child(yard)
	current_scene = yard
	await process_frame
	ch = yard.character
	ch.set_physics_process(false)
	ch.mode = 0
	ch.position = Vector3(0, 0.02, 3)
	for child in ch.get_children():
		if child.get_script() and String(child.get_script().resource_path).ends_with("player_input_source.gd"):
			child.set_physics_process(false)
	yard.camera_rig.set_process(false)
	yard.camera_rig.set_process_unhandled_input(false)
	yard.camera_rig.camera.reparent(yard, true) # keep SpringArm's internal update out of fixed review views
	ch.visual.anim.set_process(false)
	var rig = ch.visual.studio_rig
	rig.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/character/captures"))
	await capture("default", "KOTM_Idle", Vector3(2.1, 1.55, 0.1), Vector3(0, 1.0, 3))
	ch.show_weapon("ar15", "rifle")
	ch.input.aim_dir = Vector3.FORWARD
	await capture("ar_ready", "KOTM_AR75_Ready", Vector3(2.2, 1.7, 0.8), Vector3(0, 1.1, 3))
	ch.input.set_button(16, true)
	await capture("ar_aim", "KOTM_AR75_Aim", Vector3(2.2, 1.7, 0.8), Vector3(0, 1.1, 3))
	ch.cosmetics.kotm_wardrobe = {"top": "Hoodie", "bottom": "Leggings", "feet": "Sneakers", "head": "Beanie"}
	rig.apply_loadout(ch.cosmetics)
	ch.health.set_armor("laminated_armor")
	ch.inventory.backpack_id = "military_backpack"
	await capture("layered_aim", "KOTM_AR75_Aim", Vector3(2.2, 1.7, 0.8), Vector3(0, 1.1, 3))
	ch.crouching = true
	await capture("layered_crouch", "KOTM_AR75_Crouch_Aim", Vector3(2.2, 1.45, 0.8), Vector3(0, 0.7, 3))
	ch.show_weapon("hunting_rifle", "sniper")
	await capture("hunting_crouch_fire", "KOTM_Hunting_Crouch_Fire", Vector3(2.2, 1.45, 0.8), Vector3(0, 0.7, 3))
	ch.crouching = false
	var vehicle = yard.get_children().filter(func(node): return node.has_method("seat_global"))[0]
	ch.vehicle = vehicle
	ch.position = vehicle.seat_global()
	await capture("seated_driver", "KOTM_Snowmobile_Seated", ch.position + Vector3(3, 2, -3), ch.position + Vector3(0, 0.9, 0))
	report["asset_sha256"] = FileAccess.get_sha256("res://assets/characters/kotm/KOTM_Character.glb")
	report["utc"] = Time.get_datetime_string_from_system(true)
	FileAccess.open("res://docs/character/captures/report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	quit()

func capture(label: String, clip: String, from: Vector3, target: Vector3) -> void:
	var rig = ch.visual.studio_rig
	rig.play(clip, 0)
	rig.player.seek(0.1 if clip.ends_with("Fire") else 0.3, true)
	rig.player.advance(0)
	rig.player.pause()
	ch.visual.anim.current = clip
	yard.camera_rig.camera.look_at_from_position(from, target, Vector3.UP)
	yard.camera_rig.camera.fov = 38
	ch.reset_physics_interpolation()
	for frame in 24:
		rig.player.advance(0)
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/character/captures/" + label + ".png")
	report.captures.append({"image": label + ".png", "clip": clip})
