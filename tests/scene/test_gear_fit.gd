extends TestCase
## Measure the actual multi-part studio gear in the moving chest frame.

func _bounds(root: Node3D, frame: Transform3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var box := frame.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func test_backpack_and_armour_fit_the_body() -> void:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	var rig: KOTMCharacterRig = ch.visual.studio_rig
	assert_true(rig != null, "gameplay uses the authored character rig")
	if rig == null:
		ch.queue_free()
		await settle(1)
		return
	ch.interaction._apply({"kind": "backpack", "id": "military_backpack"}, ch.global_position)
	ch.interaction._apply({"kind": "armor", "id": "laminated_armor"}, ch.global_position)
	await settle(6)
	var initial := {}
	for crouched in [false, true]:
		ch.crouching = crouched
		if crouched:
			ch.inventory.give_weapon("ar15")
		await settle(30)
		await rig.skeleton.skeleton_updated
		var chest := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone("chest"))
		for key in ["Backpack", "Armour"]:
			var root: Node3D = rig.roots.get(key)
			assert_true(root != null and root.is_visible_in_tree(), key + " is equipped")
			if root == null:
				continue
			var box := _bounds(root, chest)
			print("    %s crouched=%s chest-space bounds=%s" % [key, crouched, box])
			assert_between(box.size.length(), 0.35, 1.1, key + " is human-sized")
			assert_true(box.get_center().length() < 0.45, key + " stays close to the chest")
			if not crouched:
				initial[key] = box
			else:
				assert_true(box.get_center().distance_to(initial[key].get_center()) < 0.06, key + " follows chest while crouched")
	ch.queue_free()
	await settle(1)
