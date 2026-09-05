class_name DamageModel
extends RefCounted
## Pure damage rules from docs/game-plan/06. Mirrors tools/ttk.py exactly
## (tests/unit/test_damage_model.gd reproduces its shots-to-kill matrix).

const KIND_FLESH := "flesh"
const KIND_ARMOR := "armor"
const KIND_ARMOR_BREAK := "armor_break"
const KIND_HELMET_POP := "helmet_pop"

class HitResult:
	var damage: float = 0.0
	var kind: String = KIND_FLESH
	var region: String = ""
	var headshot: bool = false
	var bleeds: bool = false
	var helmet_destroyed: bool = false
	var armor_destroyed: bool = false
	var killed: bool = false

static func region_multiplier(region: String) -> float:
	var mults: Dictionary = DataLib.weapons()["regionMultipliers"]
	return float(mults.get(region, 1.0))

static func is_torso(region: String) -> bool:
	return region == "upperTorso" or region == "lowerTorso"

## Applies one projectile (or pellet) hit to [state] and returns what happened.
## [weapon] is an entry of weapons.json. [travel_m] is the distance flown (for falloff).
## [pellet] true when the weapon has a pellets field and this is one of them.
## [shot_id] groups pellets of one trigger pull so a helmet absorbs the whole blast.
static func hit(weapon: Dictionary, region: String, travel_m: float, state: HealthState,
		pellet := false, shot_id := 0) -> HitResult:
	var r := HitResult.new()
	r.region = region
	var pellets := int(weapon.get("pellets", 1))
	var dmg: float
	if region == "head":
		r.headshot = true
		dmg = float(weapon["headDamage"])
		if pellet:
			dmg /= float(pellets)
		if state.has_helmet():
			r.kind = KIND_HELMET_POP
			r.helmet_destroyed = true
			if not bool(weapon.get("pierceHelmet", false)):
				dmg *= state.helmet_take
			state.helmet_popped_by_shot = shot_id
			state.remove_helmet()
		elif state.helmet_popped_by_shot == shot_id and pellet:
			# Same blast that popped the helmet: remaining pellets are still reduced.
			r.kind = KIND_HELMET_POP
			if not bool(weapon.get("pierceHelmet", false)):
				dmg *= state.helmet_popped_take
		else:
			r.kind = KIND_FLESH
	else:
		dmg = float(weapon.get("pelletDamage", weapon["bodyDamage"])) if pellet else float(weapon["bodyDamage"])
		dmg *= region_multiplier(region)
		if region == "lowerLegs":
			dmg *= float(state.shoes().get("lowerLegDamageMult", 1.0))
		var falloff: Variant = weapon.get("falloff", null)
		if falloff != null and travel_m > float(falloff["startM"]):
			var t := clampf((travel_m - float(falloff["startM"])) / (float(falloff["endM"]) - float(falloff["startM"])), 0.0, 1.0)
			dmg *= lerpf(1.0, float(falloff["endMultiplier"]), t)
		r.kind = KIND_FLESH
		if is_torso(region) and state.has_armor():
			var absorbed := minf(state.armor_dur, dmg * state.armor_absorb)
			state.armor_dur -= absorbed
			dmg -= absorbed
			r.kind = KIND_ARMOR
			if state.armor_dur <= 0.0001:
				state.remove_armor()
				r.kind = KIND_ARMOR_BREAK
				r.armor_destroyed = true
	r.damage = dmg
	r.bleeds = r.kind == KIND_FLESH or r.kind == KIND_ARMOR_BREAK
	if r.bleeds:
		state.bleeding = true
	r.killed = state.apply_damage(dmg)
	return r

## Melee: flat damage, head x1.5, ignores gear (docs 06).
static func melee(melee_def: Dictionary, region: String, state: HealthState) -> HitResult:
	var r := HitResult.new()
	r.region = region
	r.damage = float(melee_def["damage"]) * (1.5 if region == "head" else 1.0)
	r.headshot = region == "head"
	r.kind = KIND_FLESH
	r.killed = state.apply_damage(r.damage)
	return r

## Fall damage from a fall height in metres, using the shoes' safe threshold.
static func fall_damage(height_m: float, state: HealthState) -> float:
	var safe := float(state.shoes().get("fallDamageThresholdM", DataLib.armor()["fallDamage"]["safeM"]))
	var lethal := float(DataLib.armor()["fallDamage"]["lethalM"])
	if height_m <= safe:
		return 0.0
	return clampf((height_m - safe) / (lethal - safe), 0.0, 1.0) * 100.0

## Gas damage ignores gear.
static func gas(dps: float, seconds: float, state: HealthState) -> bool:
	return state.apply_damage(dps * seconds)

## Bleed tick: 1 HP per tick (armor.json bleeding.damagePerTick).
static func bleed_tick(state: HealthState) -> bool:
	if not state.bleeding:
		return false
	return state.apply_damage(float(DataLib.armor()["bleeding"]["damagePerTick"]))
