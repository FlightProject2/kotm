extends SceneTree
## Preserve the native FBX import's skin/bone transforms while refining its materials.

func _initialize() -> void:
	var root: Node3D = load("res://assets/quaternius/guns/Revolver.fbx").instantiate()
	var count := 0
	for node: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		for surface in node.mesh.get_surface_count():
			var source := node.get_active_material(surface) as StandardMaterial3D
			if source:
				var role := "timber" if source.resource_name.to_lower().contains("wood") else "metal"
				node.set_surface_override_material(surface, KOTMWorldStyle.surface(source, role))
				count += 1
	var scene := PackedScene.new()
	var result := scene.pack(root)
	if result == OK:
		result = ResourceSaver.save(scene, "res://assets/styled/quaternius/guns/Revolver.tscn")
	print("KOTM_NATIVE_REVOLVER_STYLE ", result, " materials=", count)
	root.free()
	quit(result)
