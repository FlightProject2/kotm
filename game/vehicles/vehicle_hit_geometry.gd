class_name VehicleHitGeometry
extends RefCounted
## Bullet hull follows visible opaque geometry. The movement box must not seal windows.
## Cache one triangle shape per imported model, shared by every vehicle instance.
static var shapes: Dictionary = {}

static func attach(vehicle: Vehicle) -> void:
	var key := vehicle.model.scene_file_path
	if not shapes.has(key):
		var faces := PackedVector3Array()
		var meshes := vehicle.model.find_children("*", "MeshInstance3D", true, false)
		if vehicle.model is MeshInstance3D:
			meshes.append(vehicle.model)
		for node: MeshInstance3D in meshes:
			if node.mesh == null:
				continue
			var xf := Transform3D.IDENTITY
			var ancestor: Node = node
			while ancestor != vehicle and ancestor != null:
				if ancestor is Node3D:
					xf = (ancestor as Node3D).transform * xf
				ancestor = ancestor.get_parent()
			for surface in node.mesh.get_surface_count():
				var mat := node.get_active_material(surface) as BaseMaterial3D
				var label := (String(node.name) + " " + (mat.resource_name if mat else "")).to_lower()
				if label.contains("glass") or label.contains("window") or label.contains("windshield"):
					continue
				var arrays := node.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				if indices.is_empty():
					for vertex in vertices:
						faces.append(xf * vertex)
				else:
					for index in indices:
						faces.append(xf * vertices[index])
		var hull := ConcavePolygonShape3D.new()
		hull.backface_collision = true
		hull.set_faces(faces)
		shapes[key] = hull
	var body := StaticBody3D.new()
	body.name = "BulletHull"
	body.collision_layer = 32
	body.collision_mask = 0
	body.set_meta("vehicle_owner", vehicle)
	var collision := CollisionShape3D.new()
	collision.shape = shapes[key]
	body.add_child(collision)
	vehicle.add_child(body)
