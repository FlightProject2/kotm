extends SceneTree
## Dumps the mannequin's bone names, rest heights and animation clips (headless).

func _initialize() -> void:
	_run()

func _run() -> void:
	await process_frame
	var scene: PackedScene = load("res://assets/characters/mannequiny/mannequiny-0.3.0.glb")
	if scene == null:
		print("SKELETON: cannot load glb"); quit(1); return
	var inst := scene.instantiate()
	root.add_child(inst)
	await process_frame
	var skel: Skeleton3D = _find_skel(inst)
	if skel == null:
		print("SKELETON: no Skeleton3D"); quit(1); return
	print("SKELETON: %d bones, skeleton path %s" % [skel.get_bone_count(), inst.get_path_to(skel)])
	for i in skel.get_bone_count():
		var g := skel.get_bone_global_rest(i)
		print("  bone %2d %-16s parent=%2d rest_y=%.3f" % [i, skel.get_bone_name(i), skel.get_bone_parent(i), g.origin.y])
	var ap: AnimationPlayer = _find_ap(inst)
	if ap:
		print("ANIMATIONS: " + ", ".join(ap.get_animation_list()))
		for a in ap.get_animation_list():
			print("  %-24s %.2fs loop=%s" % [a, ap.get_animation(a).length, ap.get_animation(a).loop_mode])
	var aabb := AABB()
	for m in inst.find_children("*", "MeshInstance3D", true, false):
		aabb = aabb.merge(m.get_aabb()) if aabb.size != Vector3.ZERO else m.get_aabb()
	print("MESH AABB: %s" % aabb)
	quit(0)

func _find_skel(n: Node) -> Skeleton3D:
	for c in n.find_children("*", "Skeleton3D", true, false):
		return c
	return null

func _find_ap(n: Node) -> AnimationPlayer:
	for c in n.find_children("*", "AnimationPlayer", true, false):
		return c
	return null
