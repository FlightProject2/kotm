extends Node
var errors: Array[String] = []
var reports: Array = []

func _ready() -> void:
	call_deferred("run_check")

func geometry(vehicle: Vehicle) -> Dictionary:
	var bounds := AABB()
	var first := true
	var materials: Dictionary = {}
	var surfaces := 0
	for mesh: MeshInstance3D in vehicle.model.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var transform := ModelLib._relative(mesh,vehicle)
		for surface in mesh.mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh.mesh.surface_get_arrays(surface)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var point := transform * vertex
				bounds = AABB(point,Vector3.ZERO) if first else bounds.expand(point)
				first = false
			var indices = arrays[Mesh.ARRAY_INDEX]
			var triangles := int((indices.size() if indices != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3)
			var material := mesh.get_active_material(surface)
			var key := StaticWorldBatcher._material_key(material)
			materials[key] = int(materials.get(key,0)) + triangles
	return {"bounds":bounds,"materials":materials,"surfaces":surfaces}

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)

func run_check() -> void:
	for id in ["pickup_truck","atv"]:
		var reference := Vehicle.new()
		reference.set_meta("disable_render_batching",true)
		add_child(reference)
		reference.setup(id,null)
		reference.process_mode = Node.PROCESS_MODE_DISABLED
		var revised := Vehicle.new()
		add_child(revised)
		revised.setup(id,null)
		revised.process_mode = Node.PROCESS_MODE_DISABLED
		var frames := 0
		var max_error := 0.0
		for state in [[0.0,0.0,false],[6.0,.6,true],[12.0,-.5,true],[-5.0,.8,true],[0.0,0.0,false]]:
			for frame in 40:
				reference.animator.update_motion(1.0/60.0,state[0],state[1],state[2],false)
				revised.animator.update_motion(1.0/60.0,state[0],state[1],state[2],false)
				revised.render_batches.update(revised.animator.distance)
			var before := geometry(reference)
			var after := geometry(revised)
			var error: float = maxf(before.bounds.position.distance_to(after.bounds.position),before.bounds.size.distance_to(after.bounds.size))
			max_error = maxf(max_error,error)
			check(error < .003,id+" geometry bounds through motion/stop")
			check(before.materials == after.materials,id+" every triangle and material retained through motion/stop")
			frames += 40
		var before := geometry(reference)
		var after := geometry(revised)
		check(after.surfaces < before.surfaces,id+" parked surface count reduced")
		for socket in ["HandGrip_L","HandGrip_R","FootRest_L","FootRest_R"]:
			check(reference.contact_marker(socket).global_transform.origin.distance_to(revised.contact_marker(socket).global_transform.origin) < .0001,id+" contact retained "+socket)
		reports.append({"vehicle":id,"frames_compared":frames,"max_bounds_error_m":max_error,"surfaces_before":before.surfaces,"surfaces_after":after.surfaces,"batch_stats":revised.get_meta("render_batch_stats")})
		reference.queue_free()
		revised.queue_free()
		await get_tree().process_frame
	var report := {"errors":errors,"vehicles":reports}
	FileAccess.open("E:/Users/Scott/Documents/ChatGPT/KOTM assets/character/style_revision/performance/vehicle_batch_geometry_qa.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("VEHICLE_BATCH_QA="+JSON.stringify(report))
	get_tree().quit(0 if errors.is_empty() else 1)
