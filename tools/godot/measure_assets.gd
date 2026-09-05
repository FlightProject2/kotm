extends SceneTree
## Prints AABBs of asset scenes so prefab generation can align pieces by their bounds.
func _initialize() -> void: _run()
func _run() -> void:
	await process_frame
	var files := {
		"kit": ["wall", "wall-doorway-square", "wall-doorway-wide-square", "wall-window-square", "wall-window-wide-square", "wall-half", "wall-low", "floor", "floor-half", "border", "border-corner", "stairs-open", "stairs-closed", "roof-flat-side", "roof-flat-corner", "roof-flat-center", "column", "barricade-window-a"],
	}
	for f in files["kit"]:
		_measure("res://assets/kenney/building/%s.glb" % f)
	for f in ["Barn", "BigBarn", "SmallBarn", "OpenBarn", "Silo", "WaterTower", "Windmill", "Fence", "Well"]:
		_measure("res://assets/quaternius/farm/%s.fbx" % f)
	for f in ["police", "suv", "truck", "sedan", "van"]:
		_measure("res://assets/kenney/car/%s.glb" % f)
	for f in ["barrel", "box-large", "fence", "fence-fortified", "chest", "signpost", "tent", "campfire-pit", "workbench"]:
		_measure("res://assets/kenney/survival/%s.glb" % f)
	for f in ["detail-bench", "detail-light-single", "detail-light-double", "roof-metal-poles", "roof-metal-type-a", "detail-dumpster-closed", "pallet", "wall-a-garage"]:
		_measure("res://assets/kenney/retro-urban/%s.glb" % f)
	for f in ["tree_oak", "tree_default", "tree_detailed", "tree_tall", "tree_thin", "tree_pineTallA", "tree_pineDefaultA", "tree_pineRoundA", "rock_largeA", "plant_bush", "grass_large"]:
		_measure("res://assets/kenney/nature/%s.glb" % f)
	_measure("res://assets/quaternius/guns/Revolver.fbx")
	quit(0)

func _measure(path: String) -> void:
	var s: PackedScene = load(path)
	if s == null:
		print("%-60s MISSING" % path); return
	var inst := s.instantiate()
	root.add_child(inst)
	var aabb := AABB()
	var first := true
	var meshes := 0
	var mats := 0
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var a: AABB = mi.global_transform * mi.get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
		meshes += 1
		mats += mi.mesh.get_surface_count() if mi.mesh else 0
	print("%-58s min=(%.2f,%.2f,%.2f) size=(%.2f,%.2f,%.2f) meshes=%d surfaces=%d" % [path.get_file(), aabb.position.x, aabb.position.y, aabb.position.z, aabb.size.x, aabb.size.y, aabb.size.z, meshes, mats])
	inst.queue_free()
