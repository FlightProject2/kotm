extends Node3D
var world: World
var camera: Camera3D
var caption: Label
var target_pane: Dictionary
var output := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--window-output="):
			output = arg.trim_prefix("--window-output=")
	assert(not output.is_empty())
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("capture")

func capture() -> void:
	world = preload("res://game/world/world.tscn").instantiate() as World
	add_child(world)
	world.setup("mesh",null,true)
	var manager := WindowManager.instance
	for pane: Dictionary in manager.panes:
		if String(pane.building).begins_with("frontier_house_ranch_sage"):
			target_pane = pane
			break
	assert(not target_pane.is_empty(),"Actual map ranch has registered windows")
	var building := world.buildings.get_node(NodePath(target_pane.building)) as Node3D
	var front := building.global_basis.z.normalized()
	var focus: Vector3 = building.global_transform * Vector3(0,2.0,4.2)
	camera = Camera3D.new()
	camera.fov = 58
	camera.far = 3000
	add_child(camera)
	camera.global_position = focus + front*8.5 + building.global_basis.x*1.3 + Vector3.UP*1.2
	camera.look_at(focus,Vector3.UP)
	camera.make_current()
	var layer := CanvasLayer.new()
	add_child(layer)
	caption = Label.new()
	caption.position = Vector2(24,22)
	caption.add_theme_font_size_override("font_size",26)
	caption.add_theme_color_override("font_outline_color",Color(.02,.03,.04,.9))
	caption.add_theme_constant_override("outline_size",7)
	layer.add_child(caption)
	caption.text = "KING OF THE MOUNTAIN  /  INTACT WINDOWS"
	await get_tree().create_timer(2.5).timeout
	await save("windows_01_intact.png")
	var xf: Transform3D = target_pane.transform
	var shooter := Character.new()
	shooter.character_id = -701
	ProjectileSystem.instance.fire(shooter,xf.origin+front*1.2,-front,ItemCatalog.weapon_def("ar15"),901,false)
	await get_tree().create_timer(.18).timeout
	assert(manager.broken.has(target_pane.id),"Simulated bullet hit actual map window")
	caption.text = "KING OF THE MOUNTAIN  /  BULLET SHATTERS GLASS"
	await save("windows_02_bullet.png")
	shooter.free()
	await get_tree().create_timer(1.0).timeout
	var grenade = preload("res://game/combat/grenade_system.gd").instance
	var blast_position := focus + front*1.1 - Vector3.UP*.4
	grenade._on_thrown(900001,-1,blast_position,Vector3.ZERO,4.0)
	grenade.detonate(900001)
	grenade.set_physics_process(false)
	grenade.advance(.035)
	caption.text = "KING OF THE MOUNTAIN  /  FRAG BLAST BREAKS NEARBY PANES"
	await save("windows_03_frag_blast.png")
	grenade.advance(.7)
	await get_tree().create_timer(1.5).timeout
	caption.text = "KING OF THE MOUNTAIN  /  OPEN APERTURES AFTER THE BLAST"
	await save("windows_04_open_apertures.png")
	print("KOTM_WINDOW_CAPTURE="+JSON.stringify({"world_windows":manager.panes.size(),"window_batches":manager.cells.size(),"broken":manager.broken.size(),"building":target_pane.building,"output":output}))
	get_tree().quit()

func save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join(name))
