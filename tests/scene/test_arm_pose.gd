extends TestCase
## With a rifle in hand both hands must move in front of the chest along the aim direction; the
## body-suit split must keep skin weights so the mesh still deforms with the skeleton.

func test_hands_reach_the_gun() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(50, 1, 50); cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position.y = -0.5
	await add_to_tree(floor_body)
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.position = Vector3(0, 0.05, 0)
	await add_to_tree(ch)
	await settle(30)
	var vis: CharacterVisuals = ch.visual
	var skel := vis.skeleton
	var hand_r := skel.find_bone("hand.r")
	var hand_l := skel.find_bone("hand.l")
	await skel.skeleton_updated
	var unarmed_r: Vector3 = skel.global_transform * skel.get_bone_global_pose(hand_r).origin
	ch.inventory.give_weapon("ar15")
	await settle(40)   # ramp is ~0.15 s
	await skel.skeleton_updated
	var r: Vector3 = skel.global_transform * skel.get_bone_global_pose(hand_r).origin
	var l: Vector3 = skel.global_transform * skel.get_bone_global_pose(hand_l).origin
	var chest: Vector3 = skel.global_transform * skel.get_bone_global_pose(skel.find_bone("spine_02")).origin
	assert_true(vis.arm_pose.weight > 0.95, "arm pose blended in (%.2f)" % vis.arm_pose.weight)
	# character faces -Z (yaw 0): hands ahead of the chest, left hand further along the barrel
	assert_true(r.z < chest.z - 0.15, "right hand in front of chest (dz %.2f)" % (r.z - chest.z))
	assert_true(l.z < r.z - 0.08, "left hand on the fore-grip (dz %.2f)" % (l.z - r.z))
	assert_true(r.distance_to(unarmed_r) > 0.15, "hand moved from the idle pose")
	# the fitted gun's muzzle must be ahead of the left hand too
	var muzzle := ch.combat.muzzle_position()
	assert_true(muzzle.z < l.z, "muzzle ahead of the support hand")
	# body suit was split and keeps skinning
	var body: MeshInstance3D = vis.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.mesh and m.mesh.get_surface_count() >= 5)[0]
	assert_eq(body.mesh.surface_get_name(0), "shirt")
	assert_eq(body.mesh.surface_get_name(3), "pants")
	assert_eq(body.mesh.surface_get_name(4), "shoes")
	var arr := body.mesh.surface_get_arrays(3)
	assert_true(arr[Mesh.ARRAY_BONES] != null and arr[Mesh.ARRAY_BONES].size() > 0, "pants keep bone indices")
	assert_true(arr[Mesh.ARRAY_WEIGHTS] != null and arr[Mesh.ARRAY_WEIGHTS].size() > 0, "pants keep weights")
	assert_true(body.get_surface_override_material(4) != null, "shoes recoloured")
	assert_eq(body.mesh.surface_get_name(5), "head")
	assert_eq(body.mesh.surface_get_name(6), "hands")
	var hb := SkinSystem.head_bounds(body.mesh)
	assert_true(hb.size.y > 0.15 and hb.position.y > 1.4, "head measured from head-weighted vertices (%s)" % hb)
	var face := vis.find_child("Face", true, false)
	assert_true(face != null and face.get_child_count() >= 8, "face parts built")
	ch.queue_free(); floor_body.queue_free()
	await settle(1)
