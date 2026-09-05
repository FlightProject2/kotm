extends TestCase
## Render-cost budget of the built world (draw calls scale with mesh instances x surfaces).

func test_instance_budget() -> void:
	var w: World = load("res://game/world/world.tscn").instantiate()
	await add_to_tree(w)
	w.setup("mesh", null, true)
	await settle(2)
	var mi := 0; var surfaces := 0; var mats := {}; var mmi := 0; var bodies := 0; var by_group := {}
	for n in w.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n
		mi += 1
		if m.mesh:
			surfaces += m.mesh.get_surface_count()
			for i in m.mesh.get_surface_count():
				var mat: Material = m.get_active_material(i)
				if mat:
					mats[mat.get_rid()] = true
		var p: Node = m
		while p.get_parent() != null and p.get_parent().get_parent() != w:
			p = p.get_parent()
		var g: String = p.get_parent().name if p.get_parent() else "?"
		by_group[g] = int(by_group.get(g, 0)) + 1
	mmi = w.find_children("*", "MultiMeshInstance3D", true, false).size()
	bodies = w.find_children("*", "StaticBody3D", true, false).size()
	print("    world: mesh_instances=%d surfaces=%d materials=%d multimesh=%d static_bodies=%d groups=%s" % [mi, surfaces, mats.size(), mmi, bodies, by_group])
	assert_true(mi > 0)
	assert_true(int(by_group.get("Buildings", 0)) <= 200, "buildings merged to a few draw calls each (%d)" % int(by_group.get("Buildings", 0)))
	w.queue_free()
	await settle(1)
