extends TestCase
## The menus are built in code; this walks every screen, the customize grid and the crate flow so
## a script error in any of them fails headless (the 3D preview is skipped without a display).

func test_screens_and_customize() -> void:
	var saved := Settings.cosmetics.duplicate(true)
	Progress.reset_for_tests()
	var m: Menus = load("res://game/ui/menus.gd").new()
	await add_to_tree(m)
	assert_eq(m.current, "main")
	for s in ["customize", "market", "stats", "settings", "pause", "end", "main"]:
		m.show_screen(s)
		await settle(1)
		assert_true(m.screens[s].visible, "screen %s visible" % s)
	m.show_screen("customize")
	await settle(1)
	assert_true(m.cust_grid.get_child_count() > 8, "clothing grid populated (%d)" % m.cust_grid.get_child_count())
	var before := String(m.loadout["chest"])
	m._cycle("chest", 1)
	assert_true(String(m.loadout["chest"]) != before, "cycling chest changes the item")
	m._cycle("head", 1)
	assert_true(String(m.loadout["head"]) != "", "cycling head from none picks a hat")
	m.cust_tab = "WEAPONS"
	m._refresh_customize()
	await settle(1)
	assert_true(m.cust_grid.get_child_count() >= 2, "weapon skins grid populated")
	m._cycle("weapon:ar15", 1)
	assert_true(m.loadout["weapons"].has("ar15"), "cycling a weapon skin sets it")
	m._cycle("weapon:ar15", -1)
	assert_false(m.loadout["weapons"].has("ar15"), "cycling back returns to standard")
	m.cust_tab = "HEAD"
	m._refresh_customize()
	assert_true(m.cust_labels["skin"].text != "" and m.cust_labels["hair"].text != "", "skin and hair labels")
	m.show_end(false, 7, "SUP3R", "AK-47", true, {"kills": 2, "damage": 310.0, "time": 125.0, "players": 31})
	assert_eq(m.end_title.text, "#7")
	assert_true(m.end_sub.text.contains("HEADSHOT"))
	m.show_end(true, 1, "", "", false, {"kills": 5, "damage": 900.0, "time": 600.0, "players": 31})
	assert_eq(m.end_title.text, "KING OF THE MOUNTAIN")
	assert_true(m.end_reward.text.contains("VICTORY CRATE"))
	m.hide_all()
	assert_false(m.visible)
	m.queue_free()
	Settings.cosmetics = saved
	await settle(1)

func test_crates_dailies_and_reel() -> void:
	Progress.reset_for_tests()
	assert_eq(Progress.dailies.size(), 4, "four dailies generated")
	assert_true(Progress.owns("shirt_grey") and not Progress.owns("shirt_hotshot"), "defaults owned, rares locked")
	assert_false(Progress.buy_crate("hot_shot_crate"), "300 coins cannot buy a 500 crate")
	Progress.coins = 1000
	assert_true(Progress.buy_crate("hot_shot_crate"))
	assert_eq(Progress.coins, 500)
	assert_eq(Progress.crate_count("hot_shot_crate"), 1)
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var drop := Progress.open_crate("hot_shot_crate", rng)
	assert_false(drop.is_empty(), "crate dropped something")
	assert_true(Progress.owns(String(drop["id"])), "drop is now owned")
	assert_eq(Progress.crate_count("hot_shot_crate"), 0)
	assert_true(Progress.open_crate("hot_shot_crate").is_empty(), "no crate left to open")
	# stats and dailies advance from local events; a win awards a victory crate
	Events.local_stat.emit("kill", 1.0)
	Events.local_stat.emit("damage", 120.0)
	assert_eq(int(Progress.stats["kills"]), 1)
	Events.match_ended.emit(true, 1, "", "", false)
	assert_eq(int(Progress.stats["wins"]), 1)
	assert_eq(Progress.crate_count("victory_crate"), 1)
	assert_true(Progress.coins > 500, "match reward paid")
	# the reel overlay drives the opening animation to the reveal
	var m: Menus = load("res://game/ui/menus.gd").new()
	await add_to_tree(m)
	m.show_screen("market")
	await settle(1)
	m._open_crate("victory_crate")
	assert_true(m.reel_layer.visible and m._reel_t >= 0.0, "reel running")
	assert_true(m.reel_strip.get_child_count() == 46, "reel tiles built")
	m._reel_t = m._reel_dur + 1.0
	for i in 3:
		await tree.process_frame
	assert_true(m.reel_result.visible, "drop revealed after the reel stops")
	assert_true(m.reel_result_name.text != "", "drop named")
	m.queue_free()
	Progress.reset_for_tests()
	await settle(1)
