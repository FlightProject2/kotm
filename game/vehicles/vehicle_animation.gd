class_name VehicleAnimation
extends Node3D
## Cosmetic mechanics shared by local players, bots and spectators. Pivots and contact
## sockets are authored in the GLBs; distance drives the belts/wheels in either direction.

var wheels: Array[Dictionary] = []
var steering: Array[Dictionary] = []
var tracks: Array[Dictionary] = []
var wipers: Array[Dictionary] = []
var doors: Array[Dictionary] = []
var body: Node3D
var distance := 0.0
var _body_rest := Transform3D.IDENTITY
var _body_pitch := 0.0
var _body_roll := 0.0
var _body_lift := 0.0
var _previous_speed := 0.0
var _wiper_time := 0.0
var _door_time := -1.0

func setup(model: Node3D) -> void:
	# Exported demonstration clips are for DCC inspection; gameplay owns these pivots.
	for player: AnimationPlayer in model.find_children("*", "AnimationPlayer", true, false):
		player.stop()
	body = model.find_child("BodySuspension", true, false) as Node3D
	if body:
		_body_rest = body.transform
	var nodes := model.find_children("*", "Node3D", true, false)
	for item in nodes:
		var node := item as Node3D
		var key := String(node.name)
		if key.begins_with("WheelSpin_") or key.begins_with("TrackWheel_"):
			wheels.append({"node": node, "rest": node.transform, "radius": _wheel_radius(node)})
		elif key.begins_with("WheelSteer_") or key.begins_with("SkiSteer_") or key == "HandlebarsSteer":
			# The handlebar steering linkage needs less travel than the skis; this also
			# keeps both fitted wrists reachable throughout the steering range.
			var limit := 18.0 if key == "HandlebarsSteer" else 25.0
			steering.append({"node": node, "rest": node.transform, "axis": Vector3.UP, "limit": deg_to_rad(limit)})
		elif key == "SteeringWheel":
			steering.append({"node": node, "rest": node.transform, "axis": Vector3.BACK, "limit": deg_to_rad(55.0)})
		elif key.begins_with("WiperPivot_"):
			wipers.append({"node": node, "rest": node.transform})
		elif key.begins_with("DoorPivot_"):
			doors.append({"node": node, "rest": node.transform, "sign": -1.0 if key.ends_with("L") else 1.0})
	for label in ["L", "R", "FL", "FR", "RL", "RR"]:
		_build_track(model, label)

func _wheel_radius(node: Node3D) -> float:
	var radius := 0.0
	for vertex in WeaponHolder._gather_vertices(node):
		radius = maxf(radius, Vector2(vertex.y, vertex.z).length())
	if node is MeshInstance3D and node.mesh:
		var bounds: AABB = node.mesh.get_aabb()
		radius = maxf(bounds.size.y, bounds.size.z) * 0.5
	return maxf(radius, 0.05)

func _build_track(model: Node3D, label: String) -> void:
	var treads := model.find_children("TrackTread_" + label + "_*", "Node3D", true, false)
	if treads.is_empty():
		return
	var path_nodes := model.find_children("TrackPath_" + label + "_*", "Node3D", true, false)
	path_nodes.sort_custom(func(a: Node, b: Node) -> bool: return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	var reference: Node3D
	var points := PackedVector3Array()
	if path_nodes.size() >= 3:
		reference = path_nodes[0].get_parent() as Node3D
		for marker: Node3D in path_nodes:
			points.append(reference.to_local(marker.global_position))
	else:
		var front := model.find_child("TrackPathFront_" + label, true, false) as Node3D
		var rear := model.find_child("TrackPathRear_" + label, true, false) as Node3D
		var top := model.find_child("TrackPathTop_" + label, true, false) as Node3D
		if front == null or rear == null or top == null:
			return
		reference = front.get_parent() as Node3D
		var a := reference.to_local(rear.global_position)
		var b := reference.to_local(front.global_position)
		var forward := (b - a).normalized()
		var to_top := reference.to_local(top.global_position) - a
		var vertical := to_top - forward * to_top.dot(forward)
		var radius := vertical.length()
		var up := vertical.normalized()
		if radius < 0.001 or a.distance_to(b) < 0.001:
			return
		# Top runs toward the nose, the front wraps down, and the ground run goes back.
		points.append(a + up * radius)
		for i in range(17):
			var angle := PI * float(i) / 16.0
			points.append(b + up * cos(angle) * radius + forward * sin(angle) * radius)
		for i in range(17):
			var angle := PI * float(i) / 16.0
			points.append(a - up * cos(angle) * radius - forward * sin(angle) * radius)
	var cumulative: Array[float] = [0.0]
	var total := 0.0
	for index in points.size():
		total += points[index].distance_to(points[(index + 1) % points.size()])
		cumulative.append(total)
	if total < 0.01:
		return
	var track := {"reference": reference, "points": points, "cumulative": cumulative, "length": total, "treads": []}
	for item in treads:
		var node := item as Node3D
		var rest := reference.global_transform.affine_inverse() * node.global_transform
		var phase := _nearest_phase(track, rest.origin)
		var sample := _sample_track(track, phase)
		# Preserve each authored tread's radial clearance, rather than forcing its origin
		# onto a path that may describe the belt's inner surface.
		track.treads.append({"node": node, "rest": rest, "phase": phase, "tangent": sample.tangent, "offset": rest.origin - sample.position})
	tracks.append(track)

func _nearest_phase(track: Dictionary, point: Vector3) -> float:
	var points: PackedVector3Array = track.points
	var best := INF
	var phase := 0.0
	for index in points.size():
		var a := points[index]
		var span := points[(index + 1) % points.size()] - a
		var t := clampf((point - a).dot(span) / maxf(span.length_squared(), 0.000001), 0.0, 1.0)
		var error := point.distance_squared_to(a + span * t)
		if error < best:
			best = error
			phase = float(track.cumulative[index]) + t * span.length()
	return phase

func _sample_track(track: Dictionary, phase: float) -> Dictionary:
	var points: PackedVector3Array = track.points
	var wrapped := fposmod(phase, float(track.length))
	for index in points.size():
		var finish := float(track.cumulative[index + 1])
		if wrapped <= finish:
			var start := float(track.cumulative[index])
			var next := (index + 1) % points.size()
			var span := points[next] - points[index]
			var t := clampf((wrapped - start) / maxf(finish - start, 0.000001), 0.0, 1.0)
			return {"position": points[index].lerp(points[next], t), "tangent": span.normalized()}
	return {"position": points[0], "tangent": (points[1] - points[0]).normalized()}

func play_door_cycle() -> void:
	_door_time = 0.0

func update_motion(dt: float, speed: float, steer: float, occupied: bool, wrecked: bool) -> void:
	if dt <= 0.0:
		return
	var moving_speed := 0.0 if wrecked else speed
	distance += moving_speed * dt
	for part in wheels:
		var node: Node3D = part.node
		var rest: Transform3D = part.rest
		node.transform = rest * Transform3D(Basis(Vector3.RIGHT, fposmod(distance / float(part.radius), TAU)), Vector3.ZERO)
	for part in steering:
		var node: Node3D = part.node
		var rest: Transform3D = part.rest
		node.transform = rest * Transform3D(Basis(part.axis, steer * float(part.limit)), Vector3.ZERO)
	for track in tracks:
		var reference: Node3D = track.reference
		for tread: Dictionary in track.treads:
			var sample := _sample_track(track, float(tread.phase) + distance)
			var original_tangent: Vector3 = tread.tangent
			var tangent: Vector3 = sample.tangent
			var rotation_delta := Basis(Vector3.RIGHT, original_tangent.signed_angle_to(tangent, Vector3.RIGHT))
			var rest: Transform3D = tread.rest
			var posed := Transform3D(rotation_delta * rest.basis, sample.position + rotation_delta * tread.offset)
			var node: Node3D = tread.node
			node.transform = posed if node.get_parent() == reference else (node.get_parent() as Node3D).global_transform.affine_inverse() * reference.global_transform * posed
	_update_body(dt, moving_speed, steer)
	if occupied and not wrecked:
		_wiper_time = fposmod(_wiper_time + dt, 2.4)
	else:
		_wiper_time = move_toward(_wiper_time, 0.0, dt * 4.0)
	var wipe := (0.5 - 0.5 * cos(TAU * _wiper_time / 2.4)) * deg_to_rad(72.0)
	for part in wipers:
		var rest: Transform3D = part.rest
		(part.node as Node3D).transform = rest * Transform3D(Basis(Vector3.BACK, wipe), Vector3.ZERO)
	var opening := 0.0
	if _door_time >= 0.0:
		_door_time += dt
		opening = sin(PI * clampf(_door_time / 1.6, 0.0, 1.0)) * deg_to_rad(55.0)
		if _door_time >= 1.6:
			_door_time = -1.0
	for part in doors:
		var rest: Transform3D = part.rest
		(part.node as Node3D).transform = rest * Transform3D(Basis(Vector3.UP, opening * float(part.sign)), Vector3.ZERO)

func _update_body(dt: float, speed: float, steer: float) -> void:
	var acceleration := clampf((speed - _previous_speed) / dt, -18.0, 12.0)
	_previous_speed = speed
	if body == null:
		return
	var travel := clampf(absf(speed) / 12.0, 0.0, 1.0)
	var smoothing := 1.0 - exp(-dt * 9.0)
	_body_pitch = lerpf(_body_pitch, -acceleration * 0.0018, smoothing)
	_body_roll = lerpf(_body_roll, -steer * travel * 0.022, smoothing)
	_body_lift = lerpf(_body_lift, sin(distance * 3.5) * travel * 0.014, smoothing)
	var pose := Transform3D(Basis.from_euler(Vector3(_body_pitch, 0.0, _body_roll)), Vector3(0, _body_lift, 0))
	body.transform = _body_rest * pose
