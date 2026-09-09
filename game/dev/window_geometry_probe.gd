extends SceneTree
func _initialize() -> void:
	for path in ["res://assets/kenney/building/wall-window-square.glb", "res://assets/styled/kenney/building/wall-window-square.glb"]:
		var scene := load(path) as PackedScene
		var node := scene.instantiate()
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			var report := {"path":path,"mesh":mesh.name,"bounds":str(mesh.mesh.get_aabb()),"surfaces":[]}
			for s in mesh.mesh.get_surface_count():
				var axes := [{},{},{}]
				for p: Vector3 in mesh.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					for k in 3:axes[k][snappedf(p[k],.0001)] = true
				report.surfaces.append({"material":mesh.mesh.surface_get_material(s).resource_name,"axes":[axes[0].keys(),axes[1].keys(),axes[2].keys()]})
			print(JSON.stringify(report))
		node.free()
	quit()
