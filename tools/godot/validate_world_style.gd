extends SceneTree
## Load actual imported source + derived models and measure their visual/marker contracts.

var errors: Array[String] = []
var results: Array = []

func _initialize() -> void:
	call_deferred("run")

func measure(root: Node3D) -> Dictionary:
	var bounds := AABB()
	var first := true
	var count := 0
	var markers: Dictionary = {}
	var surfaces := 0
	for node in root.find_children("*", "Node3D", true, false):
		var xf := Transform3D.IDENTITY
		var ancestor: Node = node
		while ancestor != null and ancestor != root:
			if ancestor is Node3D:
				xf = ancestor.transform * xf
			ancestor = ancestor.get_parent()
		if node is MeshInstance3D and node.mesh:
			var box: AABB = xf * node.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			count += 1
			surfaces += node.mesh.get_surface_count()
		elif String(node.name).contains("Seat") or String(node.name).contains("Grip") or String(node.name).contains("Footrest"):
			markers[String(node.name)] = xf.origin
	return {"bounds": bounds, "meshes": count, "surfaces": surfaces, "markers": markers}

func run() -> void:
	var paths: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/styled/paths.json"))
	for source: String in paths:
		var derived := String(paths[source])
		if not ResourceLoader.exists(derived):
			errors.append("Missing derivative: " + derived)
			continue
		if not source.begins_with("res://assets/"):
			var prefab: PackedScene = load(derived)
			if prefab == null:
				errors.append("Invalid styled prefab: " + derived)
			continue
		var original_scene: PackedScene = load(source)
		var derived_scene: PackedScene = load(derived)
		if original_scene == null or derived_scene == null:
			errors.append("Cannot import comparison: " + source)
			continue
		var original := original_scene.instantiate() as Node3D
		var styled := derived_scene.instantiate() as Node3D
		var before := measure(original)
		var after := measure(styled)
		var a: AABB = before.bounds
		var b: AABB = after.bounds
		var delta := maxf(a.position.distance_to(b.position), a.end.distance_to(b.end))
		var tolerance := maxf(0.025, a.size.length() * 0.006)
		if after.meshes == 0:
			errors.append("Empty derivative: " + derived)
		if delta > tolerance:
			errors.append("Bounds changed by %.5fm: %s" % [delta, source])
		var marker_error := 0.0
		for name: String in before.markers:
			if not after.markers.has(name):
				errors.append("Missing marker %s: %s" % [name, source])
			else:
				var position: Vector3 = before.markers[name]
				marker_error = maxf(marker_error, position.distance_to(after.markers[name]))
		if marker_error > 0.0001:
			errors.append("Marker moved: " + source)
		results.append({"source": source, "derived": derived, "bounds_delta_m": delta,
			"bounds_source": [a.position.x, a.position.y, a.position.z, a.end.x, a.end.y, a.end.z],
			"bounds_derived": [b.position.x, b.position.y, b.position.z, b.end.x, b.end.y, b.end.z],
			"markers_error_m": marker_error, "source_meshes": before.meshes, "derived_meshes": after.meshes,
			"source_surfaces": before.surfaces, "derived_surfaces": after.surfaces})
		original.free()
		styled.free()
	var output := {"models": results.size(), "errors": errors, "results": results}
	var report := FileAccess.open("res://assets/styled/import_validation.json", FileAccess.WRITE)
	report.store_string(JSON.stringify(output, "  "))
	print("KOTM_WORLD_STYLE_VALIDATION ", results.size(), " models, ", errors.size(), " errors")
	for error in errors:
		push_error(error)
	quit(0 if errors.is_empty() else 1)
