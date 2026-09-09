class_name WindowManager
extends Node3D
## Authoritative pane state with spatial rendering/physics batches and no idle processing.
static var instance: WindowManager
const CELL := 96.0
const MAX_SHARDS := 96
var panes: Array[Dictionary] = []
var broken: Dictionary = {}
var cells: Dictionary = {}
var body_lookup: Dictionary = {}
var shared_shapes: Dictionary = {}
var shards: Array[Dictionary] = []
var shard_cursor := 0
var shard_mesh: MultiMesh
var ready_for_hits := false
var pending: Dictionary = {}
var sound: AudioStreamWAV
var sounds: Array[AudioStreamPlayer3D] = []

func _ready() -> void:
	instance = self
	name = "WindowManager"
	set_meta("destructible", true)
	set_process(false)
	Events.window_broken.connect(_on_break)

func register_building(root: Node3D, local_panes: Array) -> void:
	for pane: Dictionary in local_panes:
		var xf: Transform3D = root.global_transform * pane.transform
		var size: Vector3 = pane.size * xf.basis.get_scale().abs()
		xf.basis = xf.basis.orthonormalized()
		panes.append({"id":panes.size(), "building":String(root.name), "transform":xf, "size":size})

func finish_registration() -> Dictionary:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.resource_name = "Intact window glass"
	material.albedo_color = Color(.28,.47,.54,.44)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.roughness = .17
	material.metallic = .15
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	box.material = material
	for pane: Dictionary in panes:
		var xf: Transform3D = pane.transform
		var coord := Vector2i(floori(xf.origin.x/CELL),floori(xf.origin.z/CELL))
		if not cells.has(coord):
			cells[coord] = {"origin":Vector3(coord.x*CELL,0,coord.y*CELL),"ids":[]}
		cells[coord].ids.append(pane.id)
	for coord: Vector2i in cells:
		var cell: Dictionary = cells[coord]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = box
		mm.instance_count = cell.ids.size()
		var visual := MultiMeshInstance3D.new()
		visual.name = "IntactWindowCell_%d_%d" % [coord.x,coord.y]
		visual.set_meta("breakable_window", true)
		visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		visual.multimesh = mm
		visual.position = cell.origin
		visual.visibility_range_end = 450.0
		visual.visibility_range_end_margin = 35.0
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(visual)
		var body := PhysicsServer3D.body_create()
		PhysicsServer3D.body_set_mode(body,PhysicsServer3D.BODY_MODE_STATIC)
		PhysicsServer3D.body_set_space(body,get_world_3d().space)
		PhysicsServer3D.body_attach_object_instance_id(body,get_instance_id())
		PhysicsServer3D.body_set_collision_layer(body,1|32)
		PhysicsServer3D.body_set_collision_mask(body,0)
		PhysicsServer3D.body_set_state(body,PhysicsServer3D.BODY_STATE_TRANSFORM,Transform3D(Basis.IDENTITY,cell.origin))
		cell["body"] = body
		cell["visual"] = visual
		body_lookup[body] = cell.ids
		for slot in cell.ids.size():
			var pane: Dictionary = panes[cell.ids[slot]]
			var xf: Transform3D = pane.transform
			xf.origin -= cell.origin
			mm.set_instance_transform(slot,Transform3D(xf.basis*Basis.from_scale(pane.size),xf.origin))
			var key := str(pane.size)
			if not shared_shapes.has(key):
				var shape := PhysicsServer3D.box_shape_create()
				PhysicsServer3D.shape_set_data(shape,pane.size*.5)
				shared_shapes[key] = shape
			PhysicsServer3D.body_add_shape(body,shared_shapes[key],xf)
			pane["body"] = body
			pane["slot"] = slot
			pane["visual"] = visual
	ready_for_hits = true
	for id: int in pending:
		_apply_break(id,Vector3.ZERO,Vector3.UP,false)
	pending.clear()
	if not Net.is_server():
		call_deferred("_ask_snapshot")
	return {"windows":panes.size(),"window_batches":cells.size(),"window_physics_bodies":cells.size()}

func pane_for_hit(hit: Dictionary) -> int:
	var rid: RID = hit.get("rid",RID())
	var shape := int(hit.get("shape",-1))
	if not body_lookup.has(rid) or shape < 0 or shape >= body_lookup[rid].size():
		return -1
	return int(body_lookup[rid][shape])

func break_hit(hit: Dictionary, cause := "bullet") -> bool:
	return break_pane(pane_for_hit(hit),hit.get("position",Vector3.ZERO),hit.get("normal",Vector3.UP),cause)

func break_pane(id: int, position: Vector3, normal: Vector3, cause := "impact") -> bool:
	if not Net.is_server() or id < 0 or id >= panes.size() or broken.has(id):
		return false
	# Reliable and call_local: authority and all peers apply the same state once.
	Net.event_all("window_broken",[id,position,normal,cause])
	return true

func melee(origin: Vector3, direction: Vector3, reach: float, exclude: Array[RID] = []) -> bool:
	if not Net.is_server() or not ready_for_hits:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin,origin+direction.normalized()*reach,1|32,exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return break_hit(hit,"punch") if not hit.is_empty() else false

func break_in_radius(position: Vector3, radius: float, cause := "blast") -> int:
	if not Net.is_server() or not ready_for_hits or radius <= 0.0:
		return 0
	var count := 0
	for pane: Dictionary in panes:
		if broken.has(pane.id):
			continue
		var xf: Transform3D = pane.transform
		var local: Vector3 = xf.affine_inverse()*position
		var half: Vector3 = pane.size*.5
		var closest := xf * local.clamp(-half,half)
		if position.distance_squared_to(closest) > radius*radius:
			continue
		var normal := (position-xf.origin).normalized()
		if break_pane(pane.id,closest,normal,cause):
			count += 1
	return count

func _on_break(id: int, position: Vector3, normal: Vector3, _cause: String) -> void:
	if not ready_for_hits:
		pending[id] = true
		return
	_apply_break(id,position,normal,true)

func _apply_break(id: int, position: Vector3, normal: Vector3, effects: bool) -> void:
	if id < 0 or id >= panes.size() or broken.has(id):
		return
	broken[id] = true
	var pane: Dictionary = panes[id]
	var visual: MultiMeshInstance3D = pane.visual
	visual.multimesh.set_instance_transform(pane.slot,Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO))
	PhysicsServer3D.body_set_shape_disabled(pane.body,pane.slot,true)
	if effects:
		_spawn_shards(pane,position,normal)

func _ask_snapshot() -> void:
	_request_snapshot.rpc_id(1)

@rpc("any_peer","call_remote","reliable")
func _request_snapshot() -> void:
	if Net.is_server():
		_receive_snapshot.rpc_id(multiplayer.get_remote_sender_id(),broken.keys())

@rpc("authority","call_remote","reliable")
func _receive_snapshot(ids: Array) -> void:
	for id: int in ids:
		if ready_for_hits:
			_apply_break(id,Vector3.ZERO,Vector3.UP,false)
		else:
			pending[id] = true

func _init_effects() -> void:
	if shard_mesh != null:
		return
	var mesh := PrismMesh.new()
	mesh.size = Vector3(.065,.09,.007)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.62,.83,.90)
	material.metallic = .25
	material.roughness = .20
	mesh.material = material
	shard_mesh = MultiMesh.new()
	shard_mesh.transform_format = MultiMesh.TRANSFORM_3D
	shard_mesh.mesh = mesh
	shard_mesh.instance_count = MAX_SHARDS
	for i in MAX_SHARDS:
		shards.append({"life":0.0,"pos":Vector3.ZERO,"velocity":Vector3.ZERO,"spin":0.0})
		shard_mesh.set_instance_transform(i,Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO))
	var visual := MultiMeshInstance3D.new()
	visual.name = "BoundedGlassShards"
	visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visual.multimesh = shard_mesh
	visual.set_meta("breakable_window",true)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	var bytes := PackedByteArray()
	var count := 7200
	bytes.resize(count*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 271
	for i in count:
		var t := float(i)/24000.0
		var envelope := exp(-t*19.0)
		var wave := (rng.randf_range(-1,1)*.6+sin(t*TAU*3100)*.16+sin(t*TAU*4700)*.13)*envelope
		bytes.encode_s16(i*2,int(wave*22000))
	sound = AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 24000
	sound.data = bytes
	for i in 3:
		var player := AudioStreamPlayer3D.new()
		player.stream = sound
		player.max_distance = 55
		add_child(player)
		sounds.append(player)

func _spawn_shards(pane: Dictionary, _position: Vector3, normal: Vector3) -> void:
	_init_effects()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pane.id)*739+broken.size()
	var xf: Transform3D = pane.transform
	for i in 12:
		var slot := shard_cursor%MAX_SHARDS
		shard_cursor += 1
		var local: Vector3 = Vector3(rng.randf_range(-.42,.42),rng.randf_range(-.42,.42),rng.randf_range(-.42,.42))*pane.size
		shards[slot] = {"life":rng.randf_range(.65,1.3),"pos":xf*local,"velocity":normal*rng.randf_range(.4,1.5)+Vector3(rng.randf_range(-1.4,1.4),rng.randf_range(.5,2.2),rng.randf_range(-1.4,1.4)),"spin":rng.randf_range(-8,8)}
	var audio: AudioStreamPlayer3D = sounds[int(pane.id)%sounds.size()]
	audio.global_position = xf.origin
	audio.play()
	set_process(true)

func _process(dt: float) -> void:
	var active := 0
	for i in MAX_SHARDS:
		var shard: Dictionary = shards[i]
		if shard.life <= 0.0:
			continue
		shard.life -= dt
		if shard.life <= 0.0:
			shard_mesh.set_instance_transform(i,Transform3D(Basis.from_scale(Vector3.ZERO),Vector3.ZERO))
			continue
		active += 1
		shard.velocity.y -= 9.81*dt
		shard.pos += shard.velocity*dt
		shard_mesh.set_instance_transform(i,Transform3D(Basis(Vector3(1,1,0).normalized(),shard.spin*shard.life),shard.pos))
	if active == 0:
		set_process(false)

func _exit_tree() -> void:
	for cell: Dictionary in cells.values():
		if cell.has("body"):
			PhysicsServer3D.free_rid(cell.body)
	for shape: RID in shared_shapes.values():
		PhysicsServer3D.free_rid(shape)
	if instance == self:
		instance = null
