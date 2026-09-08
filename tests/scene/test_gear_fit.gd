extends TestCase
## Worn gear has to fit the body: the backpack sits on the back at pack size, the armour covers
## the chest and neither is scaled up by the bone it hangs from.

func _wearer() -> Character:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.display_name = "Wearer"
	await add_to_tree(ch)
	ch.interaction._apply({"kind": "backpack", "id": "military_backpack"}, ch.global_position)
	ch.interaction._apply({"kind": "armor", "id": "laminated_armor"}, ch.global_position)
	await settle(6)
	return ch

func test_backpack_and_armour_fit_the_body() -> void:
	var ch := await _wearer()
	var vis: CharacterVisuals = ch.get_node("Visual")
	var skel: Skeleton3D = vis.skeleton
	var chest := skel.find_bone("spine_02")
	var chest_pos: Vector3 = skel.global_transform * skel.get_bone_global_pose(chest).origin
	print("    skeleton scale=%s   chest bone pose scale=%s" % [skel.global_transform.basis.get_scale(), skel.get_bone_global_pose(chest).basis.get_scale()])
	for pair in [["backpack", vis.backpack_mesh], ["armour", vis.armor_mesh]]:
		var mi: MeshInstance3D = pair[1]
		assert_true(mi != null, "%s mesh exists" % pair[0])
		if mi == null:
			continue
		var box: AABB = mi.global_transform * mi.get_aabb()
		var c: Vector3 = box.get_center()
		print("    %-9s size=(%.2f, %.2f, %.2f) centre=(%.2f, %.2f, %.2f) rel chest=(%.2f, %.2f, %.2f)" %
			[pair[0], box.size.x, box.size.y, box.size.z, c.x, c.y, c.z, c.x - chest_pos.x, c.y - chest_pos.y, c.z - chest_pos.z])
	# a worn pack is roughly 0.35 x 0.46 x 0.4 m; anything near torso-sized reads as a bug
	var bp: AABB = vis.backpack_mesh.global_transform * vis.backpack_mesh.get_aabb()
	assert_between(bp.size.y, 0.35, 0.60, "backpack is pack-sized, not torso-sized (%.2f m tall)" % bp.size.y)
	assert_between(bp.size.x, 0.25, 0.50, "backpack width (%.2f m)" % bp.size.x)
	var am: AABB = vis.armor_mesh.global_transform * vis.armor_mesh.get_aabb()
	assert_between(am.size.y, 0.25, 0.45, "armour is chest-sized (%.2f m tall)" % am.size.y)
	# the vest has to be no wider than the torso (~0.34 m) or it pokes out through the arms
	assert_between(am.size.x, 0.26, 0.36, "armour width (%.2f m)" % am.size.x)
	_check_placement(ch, vis, chest_pos, "resting")
	# and again while armed and crouched: the arm pose twists spine_02, which the pack hangs from,
	# and the crouch drops the pelvis, so the pack must not swing off the back
	ch.inventory.give_weapon("ar15")
	ch.inventory.give_ammo("223", 60)
	ch.crouching = true
	await settle(30)
	var chest2: Vector3 = skel.global_transform * skel.get_bone_global_pose(chest).origin
	_check_placement(ch, vis, chest2, "armed + crouched")
	ch.queue_free()
	await settle(1)

## The pack rides the back, centred, at chest height, in the character's own frame.
func _check_placement(ch: Character, vis: CharacterVisuals, chest_pos: Vector3, label: String) -> void:
	var centre: Vector3 = (vis.backpack_mesh.global_transform * vis.backpack_mesh.get_aabb()).get_center()
	var d := centre - chest_pos
	var behind := d.dot(-ch.forward())     # forward is -Z, so behind is positive here
	var side := d.dot(ch.right())
	print("    pack %-16s behind=%.2f side=%.2f up=%.2f" % [label, behind, side, d.y])
	assert_between(behind, 0.08, 0.32, "%s: the pack rides behind the spine (%.2f m)" % [label, behind])
	assert_true(absf(side) < 0.12, "%s: the pack stays centred on the back (%.2f m off)" % [label, side])
	assert_between(d.y, -0.25, 0.20, "%s: the pack rides the back, not the hips (%.2f m)" % [label, d.y])
