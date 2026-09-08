extends TestCase
## The studio baseball cap has to sit on the head at head size with the peak over the face,
## and give way to a helmet when one is picked up.

const HEAD_TOP := 1.793      # the mannequin's crown, measured off the body mesh
const HEAD_WIDTH := 0.215

func _capped() -> Character:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	ch.display_name = "Capped"
	ch.cosmetics = SkinSystem.default_loadout()
	ch.cosmetics["head"] = "hat_police_cap"
	await add_to_tree(ch)
	await settle(6)
	return ch

func test_cap_model_exists_and_is_split_for_skinning() -> void:
	assert_true(ModelLib.exists(SkinSystem.CAP_MODEL), "baseball_cap.glb is imported")
	var mesh := ModelLib.mesh(SkinSystem.CAP_MODEL)
	assert_true(mesh != null and mesh.get_surface_count() >= 3, "crown, peak and accent surfaces")
	var names := {}
	for i in mesh.get_surface_count():
		var m := mesh.surface_get_material(i)
		if m:
			names[m.resource_name] = true
	print("    cap surfaces: %s  size=%s" % [names.keys(), ModelLib.aabb(SkinSystem.CAP_MODEL).size])
	assert_true(names.has("CapCrown") and names.has("CapPeak") and names.has("CapAccent"),
		"materials the skin system recolours by name (%s)" % [names.keys()])
	# authored to a real head: about 0.19 m across, and the peak reaching forward past the crown
	var box := ModelLib.aabb(SkinSystem.CAP_MODEL)
	assert_between(box.size.x, 0.17, 0.22, "cap is head-width (%.3f m)" % box.size.x)
	assert_between(box.size.z, 0.27, 0.34, "crown plus peak front to back (%.3f m)" % box.size.z)
	# the mannequin faces +Z, so the peak has to stick out further on +Z than the crown does on -Z
	assert_true(box.end.z > -box.position.z + 0.05, "the peak points the way the character faces")

func test_cap_sits_on_the_head() -> void:
	var ch := await _capped()
	var vis: CharacterVisuals = ch.get_node("Visual")
	assert_true(vis.hat != null, "the cap was built")
	var mi: MeshInstance3D = vis.hat.find_children("*", "MeshInstance3D", true, false)[0]
	# Measure in the head bone's own frame. World space is no good here: the idle clip carries the
	# head well forward of its rest position and a character with no ground under it sinks, but the
	# cap is skinned to the head through the bone attachment, so the bone-local fit is the truth.
	var box: AABB = mi.transform * mi.get_aabb()
	print("    cap on head (head-bone frame): size=(%.2f, %.2f, %.2f) opening=%.3f top=%.3f peak_z=%.3f" %
		[box.size.x, box.size.y, box.size.z, box.position.y, box.end.y, box.end.z])
	assert_between(box.size.x, HEAD_WIDTH * 0.90, HEAD_WIDTH * 1.15, "worn at head width (%.2f m)" % box.size.x)
	assert_true(absf(box.get_center().x) < 0.04, "centred on the head (%.2f m off)" % box.get_center().x)
	# the head bone sits at the base of the skull, which is about 0.21 m below its crown: the cap's
	# opening rides above the bone and the top of the crown caps the skull
	assert_between(box.position.y, 0.07, 0.16, "the opening rides the skull (%.3f m above the bone)" % box.position.y)
	assert_between(box.end.y, 0.17, 0.28, "the crown caps the skull (%.3f m above the bone)" % box.end.y)
	# the mannequin faces +Z in skeleton space, so the peak has to reach out over the face
	assert_true(box.end.z > 0.06, "the peak reaches over the face (%.3f m)" % box.end.z)
	ch.queue_free()
	await settle(1)

func test_helmet_replaces_the_cap() -> void:
	var ch := await _capped()
	var vis: CharacterVisuals = ch.get_node("Visual")
	await settle(2)
	assert_true(vis.hat.visible, "the cap shows with no helmet")
	ch.health.set_helmet("motorcycle_helmet")
	await settle(4)
	assert_false(vis.hat.visible, "the cap comes off when a helmet goes on")
	assert_true(vis.helmet_mesh.visible, "the helmet shows instead")
	ch.queue_free()
	await settle(1)
