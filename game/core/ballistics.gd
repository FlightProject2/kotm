class_name Ballistics
extends RefCounted
## Projectile maths shared by the server simulation, tracer rendering and bot aim.

const GRAVITY := 9.81
const SUBSTEP_M := 2.5
const MAX_RANGE_DEFAULT := 800.0

static func gravity_for(weapon: Dictionary) -> float:
	return GRAVITY * float(weapon.get("gravityMultiplier", 1.0))

## Semi-implicit Euler step. Returns [pos, vel].
static func step(pos: Vector3, vel: Vector3, g: float, dt: float) -> Array:
	vel.y -= g * dt
	return [pos + vel * dt, vel]

static func substep_dt(vel: Vector3) -> float:
	return SUBSTEP_M / maxf(vel.length(), 1.0)

static func time_of_flight(distance_m: float, weapon: Dictionary) -> float:
	return distance_m / float(weapon["muzzleVelocity"])

## Analytic drop at a horizontal distance (ignores drag): 0.5 * g * t^2.
static func drop_at(distance_m: float, weapon: Dictionary) -> float:
	var t := time_of_flight(distance_m, weapon)
	return 0.5 * gravity_for(weapon) * t * t

## Aim point that compensates drop and target velocity (used by bots).
static func lead_point(muzzle: Vector3, target: Vector3, target_vel: Vector3, weapon: Dictionary,
		lead_factor := 0.8, drop_factor := 0.9) -> Vector3:
	var d := muzzle.distance_to(target)
	var tof := time_of_flight(d, weapon)
	var p := target + target_vel * tof * lead_factor
	p.y += 0.5 * gravity_for(weapon) * tof * tof * drop_factor
	return p

## Random direction inside a cone of [spread_deg] half-angle (uniform on the disc like the prototype).
static func jitter(dir: Vector3, spread_deg: float, rng: RandomNumberGenerator) -> Vector3:
	if spread_deg <= 0.0:
		return dir
	var r := deg_to_rad(spread_deg) * sqrt(rng.randf())
	var th := rng.randf() * TAU
	var up := Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP
	var t1 := dir.cross(up).normalized()
	var t2 := dir.cross(t1)
	return (dir + t1 * (cos(th) * tan(r)) + t2 * (sin(th) * tan(r))).normalized()

## Simulates a projectile in sub-steps over flat ground until it has flown [distance_m]
## horizontally. Returns the vertical drop in metres (positive = below the muzzle line).
static func simulate_drop(weapon: Dictionary, distance_m: float) -> float:
	var g := gravity_for(weapon)
	var pos := Vector3.ZERO
	var vel := Vector3(float(weapon["muzzleVelocity"]), 0, 0)
	while pos.x < distance_m:
		var dt := substep_dt(vel)
		var s := step(pos, vel, g, dt)
		var prev := pos
		pos = s[0]
		vel = s[1]
		if pos.x >= distance_m:
			var t := (distance_m - prev.x) / maxf(pos.x - prev.x, 0.0001)
			return -lerpf(prev.y, pos.y, t)
	return -pos.y
