class_name WindowAssetAdapter
extends RefCounted
## Extract glass before scenery merging and retain real openings in wall collision.
static var stripped_meshes: Dictionary = {}

static func prepare(root: Node3D) -> Array:
	var panes: Array = []
	if root.has_meta("frontier_asset"):
		var id := String(root.get_meta("frontier_asset"))
		var spec: Dictionary = FrontierExpansion._assets().get(id, {})
		for window: Dictionary in spec.get("windows", []):
			panes.append({"transform":Transform3D(Basis.IDENTITY, _vector(window.position)), "size":_vector(window.size)})
		if not panes.is_empty():
			for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
				mesh.mesh = _without_glass(mesh.mesh)
	else:
		for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null:
				continue
			var box := mesh.mesh.get_aabb()
			var thin := 0 if box.size.x <= box.size.y and box.size.x <= box.size.z else (1 if box.size.y <= box.size.z else 2)
			if box.size[thin] > .065 or box.size[(thin+1)%3] < .2 or box.size[(thin+2)%3] < .2:
				continue
			var glass := false
			for s in mesh.mesh.get_surface_count():
				var material: Material = mesh.get_active_material(s)
				glass = glass or (material != null and material.resource_name.to_lower().contains("glass"))
			if not glass:
				continue
			var xf := relative_transform(mesh, root)
			var size := box.size
			size[thin] = maxf(size[thin], .028)
			panes.append({"transform":xf * Transform3D(Basis.IDENTITY, box.get_center()), "size":size})
			mesh.get_parent().remove_child(mesh)
			mesh.queue_free()
	for pane: Dictionary in panes:
		_carve_collision(root, pane)
	return panes

static func _without_glass(mesh: Mesh) -> Mesh:
	if stripped_meshes.has(mesh.get_rid()):
		return stripped_meshes[mesh.get_rid()]
	var result := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var material: Material = mesh.surface_get_material(surface)
		if material != null and material.resource_name == "KOTM_glass":
			continue
		result.add_surface_from_arrays(mesh.surface_get_primitive_type(surface), mesh.surface_get_arrays(surface))
		result.surface_set_material(result.get_surface_count()-1, material)
	stripped_meshes[mesh.get_rid()] = result
	return result

static func relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != root and cursor != null:
		if cursor is Node3D:
			xf = cursor.transform * xf
		cursor = cursor.get_parent()
	return xf

static func _carve_collision(root: Node3D, pane: Dictionary) -> void:
	for collision: CollisionShape3D in root.find_children("*", "CollisionShape3D", true, false):
		if not collision.shape is BoxShape3D or collision.disabled:
			continue
		var size: Vector3 = collision.shape.size
		var thin := 0 if size.x <= size.y and size.x <= size.z else (1 if size.y <= size.z else 2)
		if size[thin] > .6:
			continue
		var relative := relative_transform(collision, root).affine_inverse() * (pane.transform as Transform3D)
		var hole: AABB = relative * AABB(-pane.size * .5, pane.size)
		var centre := hole.get_center()
		var u := (thin+1)%3
		var v := (thin+2)%3
		if hole.size[thin] > .15 or absf(centre[thin]) > size[thin]*.5+.15:
			continue
		if hole.position[u] < -size[u]*.5-.005 or hole.end[u] > size[u]*.5+.005 or hole.position[v] < -size[v]*.5-.005 or hole.end[v] > size[v]*.5+.005:
			continue
		var ranges := [
			[-size[u]*.5, size[u]*.5, -size[v]*.5, hole.position[v]],
			[-size[u]*.5, size[u]*.5, hole.end[v], size[v]*.5],
			[-size[u]*.5, hole.position[u], hole.position[v], hole.end[v]],
			[hole.end[u], size[u]*.5, hole.position[v], hole.end[v]],
		]
		for bounds: Array in ranges:
			if bounds[1]-bounds[0] < .005 or bounds[3]-bounds[2] < .005:
				continue
			var piece_size := size
			piece_size[u] = bounds[1]-bounds[0]
			piece_size[v] = bounds[3]-bounds[2]
			var offset := Vector3.ZERO
			offset[u] = (bounds[1]+bounds[0])*.5
			offset[v] = (bounds[3]+bounds[2])*.5
			var shape := BoxShape3D.new()
			shape.size = piece_size
			var piece := CollisionShape3D.new()
			piece.name = "WindowApertureWall"
			piece.shape = shape
			piece.transform = collision.transform * Transform3D(Basis.IDENTITY, offset)
			collision.get_parent().add_child(piece)
		collision.get_parent().remove_child(collision)
		collision.queue_free()

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))
