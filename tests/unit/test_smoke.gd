extends TestCase

func test_data_files_load() -> void:
	assert_true(DataLib.weapons().has("weapons"), "weapons.json has a weapons array")
	assert_eq(DataLib.weapons()["playerHp"], 100.0)
	assert_true(DataLib.armor().has("helmets"))
	assert_true(DataLib.gas_phases().has("phases"))
	assert_true(DataLib.loot_tables().has("nodeClasses"))
	assert_true(DataLib.movement().has("sprintSpeed"))
	assert_eq(DataLib.preset("slice_2km")["id"], "slice_2km")
