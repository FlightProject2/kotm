extends Node3D
var failures: Array[String] = []
func _ready() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)
func run() -> void:
	var world := preload("res://game/world/world.tscn").instantiate() as World
	add_child(world)
	world.setup("mesh", null, true)
	var manager := WindowManager.instance
	check(manager != null and manager.panes.size() > 0,"Full world registers existing, frontier and resort windows")
	var families := {"legacy":false,"frontier":false,"resort":false}
	for pane: Dictionary in manager.panes:
		var building := String(pane.building)
		if building.begins_with("frontier_resort_"): families.resort = true
		elif building.begins_with("frontier_"): families.frontier = true
		else: families.legacy = true
	check(families.legacy and families.frontier and families.resort,"All three building families supply panes")
	check(manager.broken.is_empty(),"Full world starts with every pane intact")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var queries: Array = []
	var space := get_world_3d().direct_space_state
	for pane: Dictionary in manager.panes:
		var size: Vector3 = pane.size
		var thin := 0 if size.x <= size.y and size.x <= size.z else (1 if size.y <= size.z else 2)
		var xf: Transform3D = pane.transform
		var n: Vector3 = xf.basis[thin]
		var query := PhysicsRayQueryParameters3D.create(xf.origin+n*.30,xf.origin-n*.30,1|32)
		var hit := space.intersect_ray(query)
		check(manager.pane_for_hit(hit) == pane.id,"Intact window catches ray: %d %s" % [pane.id,pane.building])
		queries.append(query)
		manager._apply_break(pane.id,Vector3.ZERO,Vector3.UP,false)
	await get_tree().physics_frame
	var clear_count := 0
	for i in queries.size():
		var hit := space.intersect_ray(queries[i])
		check(hit.is_empty(),"Broken window has open wall collision: %d %s" % [i,manager.panes[i].building])
		if hit.is_empty(): clear_count += 1
	print("KOTM_WORLD_WINDOWS="+JSON.stringify({"issues":failures,"panes":manager.panes.size(),"batches":manager.cells.size(),"clear_apertures":clear_count,"idle_processing":manager.is_processing()}))
	get_tree().quit(0 if failures.is_empty() else 1)
