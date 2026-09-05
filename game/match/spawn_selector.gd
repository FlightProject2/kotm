class_name SpawnSelector
extends RefCounted
## Random-point parachute spawns (docs/game-plan/02): uniform over the playable mask, rejecting
## steep ground and the mountain top, with a minimum spacing that relaxes after many tries.

static func pick(count: int, hf: HeightField, preset: Dictionary, rng: RandomNumberGenerator) -> Array:
	var half := float(preset["mapHalfSizeM"]) - float(preset["borderMarginM"])
	var spacing := float(preset["spawnMinSpacingM"])
	var relax_after := int(preset["spawnRelaxAfterTries"])
	var relax_per := float(preset["spawnRelaxPerTryM"])
	var max_slope := float(preset["spawnMaxSlopeDeg"])
	var max_h := float(preset["spawnMaxHeightM"])
	var alt := float(preset["spawnAltitudeM"])
	var chosen: Array = []
	for n in count:
		var placed := false
		for t in 80:
			var x := rng.randf_range(-half, half)
			var z := rng.randf_range(-half, half)
			var h := hf.height_at(x, z)
			if h > max_h or hf.slope_deg_at(x, z) > max_slope:
				continue
			var need := spacing - relax_per * maxf(0.0, t - relax_after)
			var ok := true
			for p in chosen:
				if Vector2(p.x - x, p.z - z).length() < need:
					ok = false
					break
			if not ok:
				continue
			chosen.append(Vector3(x, h + alt, z))
			placed = true
			break
		if not placed:
			var x := rng.randf_range(-half, half)
			var z := rng.randf_range(-half, half)
			chosen.append(Vector3(x, hf.height_at(x, z) + alt, z))
	return chosen
