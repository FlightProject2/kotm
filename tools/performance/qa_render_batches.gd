extends Node
var errors: Array[String] = []

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)

func _ready() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	var registry := LootRegistry.new()
	add_child(registry)
	var original: Array = []
	for i in 270:
		original.append(registry.add({"kind":"ammo", "id":"5.56", "qty":30}, Vector3(10+i*.1,2,10)))
	var batch: String = original[0].batch_key
	var mmi: MultiMeshInstance3D = registry._mm[batch]
	check(mmi.multimesh.instance_count == 512, "Capacity grows with all transforms retained")
	check(mmi.multimesh.visible_instance_count == 270, "Only live loot is submitted")
	await get_tree().process_frame
	await get_tree().process_frame
	print("FIRST_TRANSFORM=",mmi.position," actual=",mmi.multimesh.get_instance_transform(0)," expected=",original[0].visual_transform)
	for e in original:
		var p: Vector3 = mmi.position + mmi.multimesh.get_instance_transform(e.slot).origin
		check(p.distance_to(e.pos+Vector3(0,.15,0)) < .0001, "Chunk transform retained after growth")
	registry.remove(original[5].id)
	check(original[269].slot == 5, "Removing a middle slot updates moved entry")
	registry.remove(original[269].id)
	check(mmi.multimesh.visible_instance_count == 268, "Moved entry can be removed")
	var far_entry := registry.add({"kind":"ammo", "id":"5.56", "qty":30},Vector3(-200,2,400))
	check(far_entry.batch_key != batch, "Distant loot has an independent culling chunk")
	check(registry.in_radius(Vector3(-200,2,400),1).size() == 1, "Spatial gameplay query remains accurate")
	check(registry.nearest(Vector3(-200,2,400),1) == far_entry, "Nearest item remains available beyond visual range")
	for e in original:
		registry.remove(e.id)
	check(mmi.multimesh.visible_instance_count == 0, "An emptied batch submits no instances")
	check(registry.count() == 1, "All removals preserve the other chunk")
	registry.queue_free()
	var world := load("res://game/world/world.tscn").instantiate() as World
	add_child(world)
	world.vehicles = Node3D.new()
	world.add_child(world.vehicles)
	var body := StaticBody3D.new()
	world.buildings.add_child(body)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	var bounds := AABB()
	for i in 2:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(.2,.5,.3)
		box.material = material
		mi.mesh = box
		mi.position = Vector3(10+i*2,1,10)
		world.buildings.add_child(mi)
		bounds = mi.global_transform * box.get_aabb() if i == 0 else bounds.merge(mi.global_transform * box.get_aabb())
	var report := StaticWorldBatcher.build(world)
	check(report.static_meshes_batched == 2, "Static meshes are batched")
	check(report.static_surfaces_before == 2 and report.static_surfaces_after == 1, "Equivalent imported materials share a surface")
	check(is_instance_valid(body) and is_instance_valid(shape) and shape.get_parent() == body, "Collision nodes stay intact")
	var merged: MeshInstance3D = world.get_node("StaticSceneryBatches").get_child(0)
	var result_bounds := merged.global_transform * merged.mesh.get_aabb()
	check(result_bounds.position.distance_to(bounds.position) < .001 and result_bounds.size.distance_to(bounds.size) < .001, "Baking retains world geometry bounds")
	world.queue_free()
	await get_tree().process_frame
	var result := {"errors":errors,"checks":"dense slots, growth, chunk transforms, gameplay queries, material deduplication, world bounds and collision preservation","static_report":report}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--report="):
			FileAccess.open(arg.substr(9),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("RENDER_BATCH_QA="+JSON.stringify(result))
	get_tree().quit(0 if errors.is_empty() else 1)
