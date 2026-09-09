extends TestCase
## The studio Blender assets convert to one merged mesh each with the artist's sockets.

func test_models_merge_and_sockets() -> void:
	for id in ["ar75", "motorcycle_helmet", "military_backpack", "snow_truck", "snowmobile"]:
		assert_true(ModelLib.exists(id), "%s.glb exported" % id)
		var m := ModelLib.mesh(id)
		assert_true(m != null and m.get_surface_count() >= 2, "%s merged into surfaces per material (%d)" % [id, m.get_surface_count() if m else 0])
		var box := ModelLib.aabb(id)
		assert_true(box.size.length() > 0.2, "%s has a size" % id)
	var rifle_size := ModelLib.aabb("ar75").size
	var longest_side := maxf(rifle_size.x, maxf(rifle_size.y, rifle_size.z))
	assert_true(longest_side > 0.9, "rifle is about a metre long along its authored axis")
	assert_true(ModelLib.aabb("snow_truck").size.y > 2.0, "truck is over 2 m tall")
	assert_true(ModelLib.socket("motorcycle_helmet", "Helmet_Socket").y < 0.0, "helmet socket below the shell centre")
	assert_true(ModelLib.sockets("military_backpack").has("Backpack_Socket"))
	var inst := ModelLib.instance("ar75", 0.75)
	assert_true(absf(inst.scale.x * longest_side - 0.75) < 0.01, "fit_to scales the longest side")
	inst.free()

func test_studio_models_reach_the_game() -> void:
	assert_eq(WeaponHolder.MODELS["ar15"], "res://assets/models/kotm/KOTM_AR15.glb")
	assert_true(Vehicle.MODELS["pickup_truck"].ends_with("snow_truck.glb"))
	assert_true(Vehicle.MODELS["offroader"].ends_with("snowmobile.glb"))
