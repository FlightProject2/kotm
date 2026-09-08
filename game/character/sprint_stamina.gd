class_name SprintStamina
extends RefCounted
## KOTM movement rule: eight seconds of sprint, then recover before sprint resumes.
var value := 100.0
var exhausted := false
var rest_time := 0.0

func tick(dt: float, requested: bool, moving: bool, sneakers: bool, cfg: Dictionary) -> bool:
	var capacity := float(cfg.get("capacity", 100.0))
	if sneakers:
		value = capacity
		exhausted = false
		rest_time = 0.0
		return requested
	if requested and moving and not exhausted:
		value = maxf(0.0, value - float(cfg.get("drainPerSec", 12.5)) * dt)
		rest_time = 0.0
		exhausted = value <= 0.00001
	else:
		var delay := float(cfg.get("recoveryDelaySec", 0.8))
		var before := maxf(0.0, rest_time - delay)
		rest_time += dt
		value = minf(capacity, value + (maxf(0.0, rest_time - delay) - before) * float(cfg.get("recoveryPerSec", 20.0)))
		if value >= float(cfg.get("resumeAt", 35.0)):
			exhausted = false
	return requested and not exhausted
