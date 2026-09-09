extends Node3D
## Server owns fuse, bounce and damage. Peers predict visuals between server corrections.
static var instance
static var _blast_audio: AudioStreamWAV
const WINDOWS := preload("res://game/world/window_manager.gd")
const THROW_SPEED := 19.0
const THROW_LIFT := 3.2
const GRAVITY := 16.0
const RADIUS := 0.065
const WORLD_MASK := 1 | 16
var grenades: Dictionary = {}
var explosions: Array = []
var _next_id := 1
var _sync_time := 0.0
var _shell_mesh: SphereMesh
var _cap_mesh: CylinderMesh
var _shell_material: StandardMaterial3D
var _cap_material: StandardMaterial3D
var _blast_mesh: SphereMesh
var _shape: SphereShape3D
var detonations := 0

func _ready() -> void:
	instance = self
	_shell_mesh = SphereMesh.new()
	_shell_mesh.radius = RADIUS
	_shell_mesh.height = RADIUS * 2.4
	_shell_mesh.radial_segments = 12
	_shell_mesh.rings = 6
	_cap_mesh = CylinderMesh.new()
	_cap_mesh.top_radius = 0.023
	_cap_mesh.bottom_radius = 0.032
	_cap_mesh.height = 0.045
	_cap_mesh.radial_segments = 8
	_shell_material = StandardMaterial3D.new()
	_shell_material.albedo_color = Color("#4b5732")
	_shell_material.roughness = 0.78
	_cap_material = StandardMaterial3D.new()
	_cap_material.albedo_color = Color("#34383b")
	_cap_material.metallic = 0.55
	_shape = SphereShape3D.new()
	_shape.radius = RADIUS
	_blast_mesh = SphereMesh.new()
	_blast_mesh.radius = 0.5
	_blast_mesh.height = 1.0
	_blast_mesh.radial_segments = 16
	_blast_mesh.rings = 8
	if _blast_audio == null:
		_build_audio()
	Events.grenade_thrown.connect(_on_thrown)
	Events.grenade_state.connect(_on_state)
	Events.grenade_exploded.connect(_on_exploded)
	set_physics_process(false)

func _build_audio() -> void:
	# One original short noise/low-frequency burst, shared by all explosions.
	var samples := PackedByteArray()
	var sample_rate := 22050
	samples.resize(sample_rate * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 81473
	var low := 0.0
	for i in sample_rate:
		var t := float(i) / sample_rate
		var noise := rng.randf_range(-1.0, 1.0)
		low = low * 0.91 + noise * 0.09
		var attack := minf(1.0, t / 0.0015)
		var value := attack * (noise * exp(-t * 35) * 0.48 + low * exp(-t * 5.8) * 1.8 + sin(TAU * (58 * t - 9 * t * t)) * exp(-t * 7.2) * 0.32)
		var encoded := int(clampf(value, -1, 1) * 30000) & 0xffff
		samples[i * 2] = encoded & 255
		samples[i * 2 + 1] = (encoded >> 8) & 255
	_blast_audio = AudioStreamWAV.new()
	_blast_audio.format = AudioStreamWAV.FORMAT_16_BITS
	_blast_audio.mix_rate = sample_rate
	_blast_audio.data = samples

func _exit_tree() -> void:
	if instance == self:
		instance = null

func throw_frag(shooter: Character) -> int:
	if not multiplayer.is_server() or shooter == null or not shooter.alive():
		return -1
	var definition: Dictionary = ItemCatalog.get_item("frag_grenade").get("def", {})
	var forward := shooter.input.aim_dir.normalized() if shooter.input.aim_dir.length_squared() > 0.5 else shooter.forward()
	var eye := shooter.eye_position()
	var origin := eye + shooter.right() * 0.22 + forward * 0.35 + Vector3.DOWN * 0.15
	var query := PhysicsRayQueryParameters3D.create(eye, origin, WORLD_MASK)
	var obstruction := shooter.get_world_3d().direct_space_state.intersect_ray(query)
	if not obstruction.is_empty():
		origin = obstruction.position + obstruction.normal * (RADIUS + 0.01)
	var velocity := forward * THROW_SPEED + Vector3.UP * THROW_LIFT + shooter.velocity * 0.5
	var id := _next_id
	_next_id += 1
	Net.event_all("grenade_thrown", [id, shooter.character_id, origin, velocity, float(definition.get("fuseSec", 4.0))])
	if grenades.has(id):
		grenades[id].owner = shooter
	return id

func _on_thrown(id: int, shooter_id: int, origin: Vector3, velocity: Vector3, fuse: float) -> void:
	if grenades.has(id):
		return
	var body := CharacterBody3D.new()
	body.name = "Frag_%d" % id
	body.collision_layer = 0
	body.collision_mask = WORLD_MASK
	var shape := CollisionShape3D.new()
	shape.shape = _shape
	body.add_child(shape)
	var shell := MeshInstance3D.new()
	shell.name = "OliveShell"
	shell.mesh = _shell_mesh
	shell.material_override = _shell_material
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(shell)
	var cap := MeshInstance3D.new()
	cap.mesh = _cap_mesh
	cap.material_override = _cap_material
	cap.position.y = 0.084
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shell.add_child(cap)
	add_child(body)
	body.global_position = origin
	body.velocity = velocity
	var owner: Character
	for node in get_tree().get_nodes_in_group("characters"):
		if node.character_id == shooter_id:
			owner = node
			break
	grenades[id] = {"body": body, "shell": shell, "remaining": fuse, "owner": owner}
	set_physics_process(true)

func _on_state(id: int, position: Vector3, velocity: Vector3, remaining: float) -> void:
	if multiplayer.is_server() or not grenades.has(id):
		return
	var entry: Dictionary = grenades[id]
	entry.body.global_position = position
	entry.body.velocity = velocity
	entry.remaining = remaining

func _physics_process(dt: float) -> void:
	advance(dt)

func advance(dt: float) -> void:
	_sync_time += dt
	var sync := _sync_time >= 0.1
	if sync:
		_sync_time = 0.0
	for id in grenades.keys():
		var entry: Dictionary = grenades[id]
		var body: CharacterBody3D = entry.body
		entry.remaining -= dt
		body.velocity.y -= GRAVITY * dt
		var motion := body.velocity * dt
		for bounce in 3:
			var collision := body.move_and_collide(motion)
			if collision == null:
				break
			var normal := collision.get_normal()
			body.velocity = body.velocity.bounce(normal) * 0.48
			if normal.y > 0.65:
				body.velocity.x *= 0.72
				body.velocity.z *= 0.72
				if body.velocity.length_squared() < 0.04:
					body.velocity = Vector3.ZERO
			motion = collision.get_remainder().bounce(normal) * 0.48
		entry.shell.rotate_x(dt * body.velocity.length())
		entry.shell.rotate_z(dt * 2.0)
		if multiplayer.is_server():
			if entry.remaining <= 0.0:
				detonate(id)
			elif sync:
				Net.fx_all("grenade_state", [id, body.global_position, body.velocity, entry.remaining])
	_update_explosions(dt)
	if grenades.is_empty() and explosions.is_empty():
		set_physics_process(false)

static func damage_at_distance(distance: float, definition: Dictionary) -> float:
	var inner := float(definition.get("innerRadiusM", 3.0))
	var outer := float(definition.get("outerRadiusM", 8.0))
	var damage := float(definition.get("damageInner", 100.0))
	return damage * (1.0 - clampf((distance - inner) / maxf(outer - inner, 0.001), 0, 1))

func detonate(id: int) -> void:
	if not multiplayer.is_server() or not grenades.has(id):
		return
	var entry: Dictionary = grenades[id]
	var origin: Vector3 = entry.body.global_position
	var definition: Dictionary = ItemCatalog.get_item("frag_grenade").get("def", {})
	var outer := float(definition.get("outerRadiusM", 8.0))
	var owner: Character = entry.owner if is_instance_valid(entry.owner) else null
	# Glass changes and radial damage are authoritative; cosmetic RPCs never apply damage.
	if is_instance_valid(WINDOWS.instance):
		WINDOWS.instance.break_in_radius(origin, outer, "blast")
	for node in get_tree().get_nodes_in_group("characters"):
		var victim := node as Character
		if victim == null or not victim.alive():
			continue
		var target := victim.global_position + Vector3.UP * victim.height() * 0.5
		var damage := damage_at_distance(origin.distance_to(target), definition)
		if damage <= 0.0 or _blocked(origin, target):
			continue
		victim.take_plain_damage(damage, owner, "Frag Grenade")
		if owner and owner.is_local() and owner != victim:
			Net.event_to(owner.owner_peer_id, "hit_confirmed", [DamageModel.KIND_FLESH, not victim.alive()])
	for node in get_tree().get_nodes_in_group("vehicles"):
		var vehicle := node as Vehicle
		if vehicle == null or vehicle.wrecked:
			continue
		var damage := damage_at_distance(vehicle.distance_to_body(origin), definition)
		if damage > 0.0 and not _blocked(origin, vehicle.global_position + Vector3.UP, [vehicle.get_rid()]):
			vehicle.apply_damage(damage, owner)
	detonations += 1
	Net.event_all("grenade_exploded", [id, origin, outer])

func _blocked(origin: Vector3, target: Vector3, exclude: Array[RID] = []) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.03, target, WORLD_MASK)
	query.exclude = exclude
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _on_exploded(id: int, position: Vector3, _radius: float) -> void:
	if not grenades.has(id):
		return # Reliable duplicate/stale events never spawn a second burst.
	grenades[id].body.queue_free()
	grenades.erase(id)
	var visual := Node3D.new()
	visual.name = "FragBlast"
	add_child(visual)
	visual.global_position = position
	var flame := MeshInstance3D.new()
	flame.mesh = _blast_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 0.43, 0.07, 0.95)
	flame.material_override = material
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(flame)
	var smoke := MeshInstance3D.new()
	smoke.mesh = _blast_mesh
	var soot := StandardMaterial3D.new()
	soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	soot.albedo_color = Color(0.20, 0.22, 0.24, 0.3)
	smoke.material_override = soot
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.add_child(smoke)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.5, 0.12)
	light.light_energy = 3.0
	light.omni_range = 9.0
	light.shadow_enabled = false
	visual.add_child(light)
	var sound := AudioStreamPlayer3D.new()
	sound.stream = _blast_audio
	sound.unit_size = 20.0
	sound.max_distance = 220.0
	sound.max_db = 1.0
	visual.add_child(sound)
	sound.play()
	explosions.append({"root": visual, "flame": flame, "material": material, "smoke": smoke, "soot": soot, "light": light, "age": 0.0})
	set_physics_process(true)

func _update_explosions(dt: float) -> void:
	for index in range(explosions.size() - 1, -1, -1):
		var effect: Dictionary = explosions[index]
		effect.age += dt
		var t: float = effect.age
		if t >= 1.1:
			effect.root.queue_free()
			explosions.remove_at(index)
			continue
		effect.flame.visible = t < 0.16
		effect.flame.scale = Vector3.ONE * (0.3 + minf(t / 0.16, 1.0) * 2.6)
		effect.material.albedo_color.a = maxf(0.0, 1.0 - t / 0.16)
		effect.light.light_energy = maxf(0.0, 3.0 * (1.0 - t / 0.18))
		effect.smoke.scale = Vector3.ONE * (0.3 + t * 4.0)
		effect.smoke.visible = t < 0.7
		effect.smoke.position.y = t * 0.8
		effect.soot.albedo_color.a = sin(clampf(t / 0.7, 0, 1) * PI) * 0.28
