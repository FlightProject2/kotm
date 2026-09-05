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

var projectiles: Array[Proj] = []
var world: World
var shots_fired: int = 0
var hits: int = 0
var _exclude_cache: Dictionary = {}

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null

func fire(shooter: Character, origin: Vector3, dir: Vector3, def: Dictionary, shot_id: int, pellet: bool) -> void:
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
	Net.fx_all("tracer", [shooter.character_id, origin, p.vel, String(def["id"])])

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
			var q := PhysicsRayQueryParameters3D.create(p.pos, to, 1 | 4 | 16)
			q.collide_with_areas = true
			q.collide_with_bodies = true
			if is_instance_valid(p.shooter):
				q.exclude = _exclusions(p.shooter)
			var hit := space.intersect_ray(q)
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
				p.alive = false
			else:
				p.dist += p.pos.distance_to(to)
				p.pos = to
				if p.dist > float(p.def.get("maxRange", max_range)) or p.pos.y < -100.0:
					p.alive = false
	projectiles = projectiles.filter(func(x: Proj) -> bool: return x.alive)

func _impact(p: Proj, hit: Dictionary) -> void:
	var collider: Object = hit.get("collider")
	var victim := HitboxRig.character_of(collider)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if victim and victim != p.shooter and victim.alive():
		var region := HitboxRig.region_of(collider)
		var r := DamageModel.hit(p.def, region, p.dist, victim.health, p.pellet, p.shot_id)
		hits += 1
		victim.apply_hit(r, p.shooter, String(p.def["name"]))
		if is_instance_valid(p.shooter) and p.shooter.is_local():
			Events.hit_confirmed.emit(r.kind, r.killed)
		if victim.is_local():
			Events.damaged.emit(r.damage, (p.shooter.global_position - victim.global_position).normalized() if is_instance_valid(p.shooter) else Vector3.ZERO, r.kind)
		Net.fx_all("hit_fx", [p.pos, normal, "armor" if r.kind == DamageModel.KIND_ARMOR or r.kind == DamageModel.KIND_ARMOR_BREAK else ("helmet" if r.kind == DamageModel.KIND_HELMET_POP or r.helmet_destroyed else "flesh")])
		if r.helmet_destroyed:
			Net.fx_all("helmet_pop", [victim.global_position + Vector3(0, 1.6, 0), "helmet"])
	elif collider is Vehicle:
		(collider as Vehicle).apply_damage(float(p.def.get("bodyDamage", 20)) * 0.6, p.shooter)
		Net.fx_all("hit_fx", [p.pos, normal, "armor"])
	else:
		Net.fx_all("hit_fx", [p.pos, normal, "world"])
