class_name ProjectileSystem
extends Node
## Server-side projectile simulation: sub-stepped rays against world, hitboxes and the height
## field, per-gun gravity, damage through DamageModel, tracer/impact events to all peers.

static var instance: ProjectileSystem

class Proj:
	var pos: Vector3
	var vel: Vector3
	var def: Dictionary
	var shooter: Character
	var dist: float = 0.0
	var shot_id: int = 0
	var pellet: bool = false
	var g: float = 9.81
	var alive: bool = true
	var tracer_id: int = 0

var projectiles: Array[Proj] = []
var world: World
var shots_fired: int = 0
var hits: int = 0
var _exclude_cache: Dictionary = {}
var _targets: Array[Node] = []

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null

func fire(shooter: Character, origin: Vector3, dir: Vector3, def: Dictionary, shot_id: int, pellet: bool, obstruction: Dictionary = {}) -> void:
	var p := Proj.new()
	p.pos = origin
	p.vel = dir.normalized() * float(def["muzzleVelocity"])
	p.def = def
	p.shooter = shooter
	p.shot_id = shot_id
	p.pellet = pellet
	p.g = Ballistics.gravity_for(def)
	projectiles.append(p)
	shots_fired += 1
	p.tracer_id = shots_fired
	Net.fx_all("projectile_tracer", [p.tracer_id, shooter.character_id, origin, p.vel, String(def["id"])])
	if not obstruction.is_empty():
		p.pos = obstruction.position
		p.alive = false
		_impact(p, obstruction)
		Net.fx_all("projectile_impact", [p.tracer_id, p.pos])

func _exclusions(shooter: Character) -> Array[RID]:
	if _exclude_cache.has(shooter) and is_instance_valid(shooter):
		return _exclude_cache[shooter]
	var ex: Array[RID] = [shooter.get_rid()]
	var rig := shooter.get_node_or_null("Hitboxes") as HitboxRig
	if rig:
		ex.append_array(rig.rids())
	_exclude_cache[shooter] = ex
	return ex

func _physics_process(dt: float) -> void:
	if projectiles.is_empty() or not multiplayer.is_server():
		return
	var space := get_viewport().get_world_3d().direct_space_state
	_targets = get_tree().get_nodes_in_group("characters")
	var max_range := 800.0
	for p in projectiles:
		if not p.alive:
			continue
		var remaining := dt
		while remaining > 0.0 and p.alive:
			var sub := minf(remaining, Ballistics.substep_dt(p.vel))
			remaining -= sub
			p.vel.y -= p.g * sub
			var to := p.pos + p.vel * sub
			var q := PhysicsRayQueryParameters3D.create(p.pos, to, 1 | 4 | 32)
			q.collide_with_areas = true
			q.collide_with_bodies = true
			q.hit_from_inside = true
			if is_instance_valid(p.shooter):
				q.exclude = _exclusions(p.shooter)
			var hit := space.intersect_ray(q)
			if hit.is_empty() or HitboxRig.character_of(hit.get("collider")) == null:
				# hit assist: a bullet has width. If the exact ray misses every hitbox, sweep a thin
				# capsule along the same segment against hitboxes only and take the nearest one
				# in front of whatever the ray did hit.
				var near := _near_miss(space, p, to)
				if not near.is_empty() and (hit.is_empty() or p.pos.distance_to(near["position"]) < p.pos.distance_to(hit["position"])):
					hit = near
			var t_hit := -1.0
			if not hit.is_empty():
				t_hit = p.pos.distance_to(hit["position"]) / maxf(p.pos.distance_to(to), 0.0001)
			if world:
				var tt := world.height_field.segment_hit(p.pos, to, 1.0)
				if tt >= 0.0 and (t_hit < 0.0 or tt < t_hit):
					hit = {"position": p.pos.lerp(to, tt), "normal": world.height_field.normal_at(to.x, to.z), "collider": null}
					t_hit = tt
			if t_hit >= 0.0:
				p.dist += p.pos.distance_to(hit["position"])
				p.pos = hit["position"]
				_impact(p, hit)
				Net.fx_all("projectile_impact", [p.tracer_id, p.pos])
				p.alive = false
			else:
				p.dist += p.pos.distance_to(to)
				p.pos = to
				if p.dist > float(p.def.get("maxRange", max_range)) or p.pos.y < -100.0:
					p.alive = false
	projectiles = projectiles.filter(func(x: Proj) -> bool: return x.alive)

const ASSIST_RADIUS := 0.06   # bullet "width" for the hitbox sweep (m)
var _assist_shape: CapsuleShape3D = CapsuleShape3D.new()

## Capsule sweep of one sub-step against hitboxes (layer 3). Returns a ray-like hit dictionary
## (position, normal, collider) for the hitbox nearest the start of the segment, or {}.
func _near_miss(space: PhysicsDirectSpaceState3D, p: Proj, to: Vector3) -> Dictionary:
	var seg := to - p.pos
	var len := seg.length()
	if len < 0.01:
		return {}
	# cheap gate: any living character within 3 m of the segment's midpoint?
	var mid := (p.pos + to) * 0.5
	var near_any := false
	for c in _targets:
		var ch := c as Character
		if ch and ch != p.shooter and ch.alive() and ch.global_position.distance_squared_to(mid) < (len * 0.5 + 3.0) * (len * 0.5 + 3.0):
			near_any = true
			break
	if not near_any:
		return {}
	_assist_shape.radius = ASSIST_RADIUS
	_assist_shape.height = len + 2.0 * ASSIST_RADIUS
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _assist_shape
	q.collision_mask = 4
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.transform = Transform3D(_capsule_basis(seg.normalized()), (p.pos + to) * 0.5)
	if is_instance_valid(p.shooter):
		q.exclude = _exclusions(p.shooter)
	var best: Dictionary = {}
	var best_d := INF
	for r in space.intersect_shape(q, 8):
		var col: Object = r.get("collider")
		var victim := HitboxRig.character_of(col)
		if victim == null or victim == p.shooter or not victim.alive():
			continue
		# closest point of the hitbox centre onto the segment = approximate impact point
		var c: Vector3 = (col as Node3D).global_position
		var t := clampf((c - p.pos).dot(seg) / (len * len), 0.0, 1.0)
		var d := t * len
		if d < best_d:
			best_d = d
			best = {"position": p.pos + seg * t, "normal": -seg.normalized(), "collider": col}
	return best

## A capsule's axis is its local Y; build a basis whose Y points along [dir].
static func _capsule_basis(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var helper := Vector3.UP if absf(y.y) < 0.99 else Vector3.RIGHT
	var x := helper.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)

func _impact(p: Proj, hit: Dictionary) -> void:
	var collider: Object = hit.get("collider")
	if collider != null and collider.has_meta("vehicle_owner"):
		collider = collider.get_meta("vehicle_owner")
	var victim := HitboxRig.character_of(collider)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if victim and victim != p.shooter and victim.alive():
		var region := HitboxRig.region_of(collider)
		var helmet_id := victim.health.helmet_id
		var r := DamageModel.hit(p.def, region, p.dist, victim.health, p.pellet, p.shot_id)
		hits += 1
		victim.apply_hit(r, p.shooter, String(p.def["name"]))
		if is_instance_valid(p.shooter) and not p.shooter.is_bot:
			Net.event_to(p.shooter.owner_peer_id, "hit_confirmed", [r.kind, r.killed])
		if victim.is_local():
			Events.damaged.emit(r.damage, (p.shooter.global_position - victim.global_position).normalized() if is_instance_valid(p.shooter) else Vector3.ZERO, r.kind)
		Net.fx_all("hit_fx", [p.pos, normal, "armor" if r.kind == DamageModel.KIND_ARMOR or r.kind == DamageModel.KIND_ARMOR_BREAK else ("helmet" if r.kind == DamageModel.KIND_HELMET_POP or r.helmet_destroyed else "flesh")])
		if r.helmet_destroyed:
			Net.fx_all("helmet_pop", [(victim.get_node("Hitboxes") as HitboxRig).head_world(), helmet_id])
	elif collider is Vehicle:
		(collider as Vehicle).apply_damage(float(p.def.get("bodyDamage", 20)) * 0.6, p.shooter)
		Net.fx_all("hit_fx", [p.pos, normal, "armor"])
	else:
		Net.fx_all("hit_fx", [p.pos, normal, "world"])
