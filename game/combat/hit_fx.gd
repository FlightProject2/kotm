class_name HitFx
extends Node3D
## Cosmetic impact effects on every peer: blood puff, sparks, dust, and the popped helmet prop.

var _puff_mesh := SphereMesh.new()

func _ready() -> void:
	_puff_mesh.radius = 0.12
	_puff_mesh.height = 0.24
	Events.hit_fx.connect(_on_hit_fx)
	Events.helmet_pop.connect(_on_helmet_pop)

func _on_hit_fx(position: Vector3, normal: Vector3, kind: String) -> void:
	var col := Color(0.6, 0.05, 0.05)
	var size := 1.0
	match kind:
		"armor": col = Color(1.0, 0.85, 0.3); size = 0.6
		"helmet": col = Color(1.0, 0.3, 0.2); size = 0.8
		"world": col = Color(0.55, 0.5, 0.42); size = 0.7
	var mi := MeshInstance3D.new()
	mi.mesh = _puff_mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	add_child(mi)
	mi.global_position = position + normal * 0.05
	mi.scale = Vector3.ONE * size
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size * 2.2, 0.25)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.25)
	tw.tween_callback(mi.queue_free)

func _on_helmet_pop(position: Vector3, _helmet_id: String) -> void:
	var body := RigidBody3D.new()
	body.collision_layer = 0
	body.collision_mask = 1
	var cs := CollisionShape3D.new()
	var s := SphereShape3D.new()
	s.radius = 0.15
	cs.shape = s
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.22
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.15, 0.35, 0.7)
	mi.material_override = m
	body.add_child(mi)
	add_child(body)
	body.global_position = position
	body.linear_velocity = Vector3(randf_range(-2, 2), 5.0, randf_range(-2, 2))
	body.angular_velocity = Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
	get_tree().create_timer(30.0).timeout.connect(body.queue_free)
