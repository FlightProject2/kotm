extends TestCase

func test_crafting_is_atomic_and_uses_the_real_inventory() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.mode = Character.Mode.GROUND
	ch.inventory.give_med("first_aid_kit", 1)
	ch.inventory.give_med("bandage", 9)
	assert_false(Crafting.make(ch, "coagulant"), "missing ingredient cannot consume resources")
	assert_eq(ch.inventory.meds["first_aid_kit"], 1)
	ch.inventory.give_med("bandage", 1)
	assert_true(Crafting.make(ch, "coagulant"))
	assert_eq(ch.inventory.meds["first_aid_kit"], 0)
	assert_eq(ch.inventory.meds["bandage"], 0)
	assert_eq(ch.inventory.meds["blood_coagulant"], 1)
	assert_false(Crafting.make(ch, "coagulant"), "cannot craft twice from consumed ingredients")
	ch.health.bleeding = true
	ch.combat._use_med("blood_coagulant")
	ch._tick_heal(0.9)
	assert_true(ch.health.bleeding)
	ch._tick_heal(0.11)
	assert_false(ch.health.bleeding, "coagulant stops bleeding after one second")
	ch.inventory.backpack_id = "military_backpack"
	ch.health.set_helmet("tactical_helmet")
	ch.inventory.give_material("duct_tape")
	assert_true(Crafting.make(ch, "makeshift_armor"))
	assert_false(ch.health.has_helmet(), "helmet is consumed")
	assert_eq(ch.inventory.backpack_id, "", "backpack is consumed")
	assert_eq(ch.health.armor_id, "makeshift_armor")
	ch.queue_free()
	await settle(1)

func test_inventory_panel_reads_gameplay_state_and_closes_cleanly() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	var hud := HUD.new()
	await add_to_tree(hud)
	hud.character = ch
	ch.inventory.give_med("bandage", 3)
	hud.inventory_panel.set_open(true)
	assert_true(hud.inventory_panel.visible)
	assert_true(hud.inventory_panel.carried.get_child_count() >= 2)
	assert_true(hud.inventory_panel.recipes.get_child_count() >= 6)
	hud.inventory_panel.set_open(false)
	assert_false(hud.inventory_panel.visible)
	var camera := CameraRig.new()
	hud.camera_rig = camera
	camera.look_enabled = false
	var toggle := InputEventAction.new()
	toggle.action = "inventory"
	toggle.pressed = true
	hud.inventory_panel._input(toggle)
	assert_false(hud.inventory_panel.open, "inventory cannot steal input from pause/settings")
	camera.free()
	hud.camera_rig = null
	hud.queue_free(); ch.queue_free()
	await settle(1)
