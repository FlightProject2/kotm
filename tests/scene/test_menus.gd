extends TestCase
## The menus are built in code; this walks every screen and the customize cycling so a script
## error in any of them fails headless (the 3D preview is skipped without a display).

func test_screens_and_customize() -> void:
	var saved := Settings.cosmetics.duplicate(true)
	var m: Menus = load("res://game/ui/menus.gd").new()
	await add_to_tree(m)
	assert_eq(m.current, "main")
	for s in ["customize", "settings", "pause", "end", "main"]:
		m.show_screen(s)
		await settle(1)
		assert_true(m.screens[s].visible, "screen %s visible" % s)
	m.show_screen("customize")
	var before := String(m.loadout["chest"])
	m._cycle("chest", 1)
	assert_true(String(m.loadout["chest"]) != before, "cycling chest changes the item")
	m._cycle("head", 1)
	assert_true(String(m.loadout["head"]) != "", "cycling head from none picks a hat")
	m._cycle("weapon:ar15", 1)
	assert_true(m.loadout["weapons"].has("ar15"), "cycling a weapon skin sets it")
	m._cycle("weapon:ar15", -1)
	assert_false(m.loadout["weapons"].has("ar15"), "cycling back returns to standard")
	assert_true(m.cust_labels["chest"].text != "", "label refreshed")
	m.show_end(false, 7, "SUP3R", "AK-47", true, {"kills": 2, "damage": 310.0, "time": 125.0, "players": 31})
	assert_eq(m.end_title.text, "#7")
	assert_true(m.end_sub.text.contains("HEADSHOT"))
	m.show_end(true, 1, "", "", false, {"kills": 5, "damage": 900.0, "time": 600.0, "players": 31})
	assert_eq(m.end_title.text, "KING OF THE MOUNTAIN")
	m.hide_all()
	assert_false(m.visible)
	m.queue_free()
	Settings.cosmetics = saved
	await settle(1)

func test_weapon_icon_cache_headless_is_blank() -> void:
	var c := WeaponIconCache.new()
	await add_to_tree(c)
	assert_true(c.has_model("ar15"))
	assert_true(c.get_icon("ar15") == null, "no icon without a renderer")
	assert_true(c.get_icon("fists") == null)
	c.queue_free()
	await settle(1)
