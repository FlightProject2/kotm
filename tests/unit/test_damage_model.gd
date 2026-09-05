extends TestCase
## Executable form of tools/ttk.py: every number here must match its printed matrix.

const EXPECTED := {
	# id: [torso, torso+laminated, head, head+moto, head+tac]
	"ar15": [4, 7, 1, 2, 2],
	"ak47": [3, 6, 1, 2, 2],
	"hunting_rifle": [2, 3, 1, 1, 1],
	"shotgun_12g": [2, 2, 1, 2, 2],
	"hellfire": [7, 12, 3, 3, 3],
	"m9": [5, 9, 2, 3, 3],
	"r380": [6, 12, 2, 3, 3],
	"m1911": [4, 8, 2, 2, 3],
	"magnum44": [3, 5, 1, 1, 1],
	"recurve_bow": [3, 5, 1, 2, 2],
}

static func weapon(id: String) -> Dictionary:
	for w in DataLib.weapons()["weapons"]:
		if w["id"] == id:
			return w
	return {}

func _shots_to_kill(w: Dictionary, region: String, helmet: String, armor: String) -> int:
	var st := HealthState.new()
	if helmet != "":
		st.set_helmet(helmet)
	if armor != "":
		st.set_armor(armor)
	var pellets := int(w.get("pellets", 1))
	var n := 0
	while st.alive and n < 60:
		n += 1
		for i in pellets:
			DamageModel.hit(w, region, 0.0, st, pellets > 1, n)
	return n

func test_ttk_matrix_matches_python() -> void:
	for id in EXPECTED:
		var w := weapon(id)
		assert_false(w.is_empty(), "weapon exists: " + id)
		var got := [
			_shots_to_kill(w, "upperTorso", "", ""),
			_shots_to_kill(w, "upperTorso", "", "laminated_armor"),
			_shots_to_kill(w, "head", "", ""),
			_shots_to_kill(w, "head", "motorcycle_helmet", ""),
			_shots_to_kill(w, "head", "tactical_helmet", ""),
		]
		assert_eq(got, EXPECTED[id], "shots-to-kill for " + id)

func test_laminated_worked_example() -> void:
	var st := HealthState.new()
	st.set_armor("laminated_armor")
	var r := DamageModel.hit(weapon("ar15"), "upperTorso", 0.0, st)
	assert_near(r.damage, 5.6, 0.001, "player takes 5.6 on the first AR chest hit")
	assert_near(st.armor_dur, 90.0 - 22.4, 0.001, "armor absorbed 22.4")
	assert_eq(r.kind, DamageModel.KIND_ARMOR)
	assert_false(r.bleeds, "armor hits do not bleed")

func test_helmet_pop_and_pierce() -> void:
	var st := HealthState.new()
	st.set_helmet("tactical_helmet")
	var r := DamageModel.hit(weapon("ar15"), "head", 0.0, st)
	assert_eq(r.kind, DamageModel.KIND_HELMET_POP)
	assert_true(r.helmet_destroyed)
	assert_near(st.hp, 75.0, 0.001, "tactical helmet leaves 75 hp after an AR headshot")
	assert_false(st.has_helmet())
	var st2 := HealthState.new()
	st2.set_helmet("tactical_helmet")
	var r2 := DamageModel.hit(weapon("hunting_rifle"), "head", 0.0, st2)
	assert_true(r2.killed, "hunting rifle one-taps through any helmet")
	assert_true(r2.helmet_destroyed)

func test_shotgun_blast_shares_helmet_reduction() -> void:
	var st := HealthState.new()
	st.set_helmet("motorcycle_helmet")
	var w := weapon("shotgun_12g")
	for i in 8:
		DamageModel.hit(w, "head", 0.0, st, true, 1)
	assert_near(st.hp, 100.0 - 144.0 * 0.45, 0.01, "whole blast reduced by the helmet it popped")
	assert_true(st.alive)

func test_region_multipliers_and_shoes() -> void:
	var st := HealthState.new()
	var r := DamageModel.hit(weapon("ak47"), "arms", 0.0, st)
	assert_near(r.damage, 36.0 * 0.7, 0.001)
	var st2 := HealthState.new()
	st2.shoes_id = "military_boots"
	var r2 := DamageModel.hit(weapon("ak47"), "lowerLegs", 0.0, st2)
	assert_near(r2.damage, 36.0 * 0.6 * 0.9, 0.001, "military boots reduce lower leg hits")
	assert_true(r.bleeds and st.bleeding)

func test_falloff() -> void:
	var st := HealthState.new()
	var w := weapon("hellfire")
	var r := DamageModel.hit(w, "upperTorso", 60.0, st)
	assert_near(r.damage, 16.0 * 0.6, 0.001, "hellfire at 60 m is at end falloff")
	var st2 := HealthState.new()
	var r2 := DamageModel.hit(w, "head", 60.0, st2)
	assert_near(r2.damage, 45.0, 0.001, "no falloff on head hits")

func test_fall_and_gas() -> void:
	var st := HealthState.new()
	assert_near(DamageModel.fall_damage(4.0, st), 0.0)
	assert_near(DamageModel.fall_damage(9.5, st), 50.0, 0.01)
	assert_near(DamageModel.fall_damage(20.0, st), 100.0)
	st.shoes_id = "work_boots"
	assert_near(DamageModel.fall_damage(6.0, st), 0.0, 0.001, "work boots raise the safe threshold to 6 m")
	var st2 := HealthState.new()
	assert_false(DamageModel.gas(10.0, 9.0, st2))
	assert_true(DamageModel.gas(10.0, 1.0, st2))
