extends TestCase

func _spawn() -> Character:
	var ch: Character = load("res://game/character/character.tscn").instantiate()
	await add_to_tree(ch)
	ch.set_physics_process(false)
	ch.visual.anim.set_process(false)
	ch.visual.studio_rig.player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	return ch

func _deform(vertex: Vector3, arrays: Array, index: int, skin: Skin, skeleton: Skeleton3D) -> Vector3:
	var count: int = arrays[Mesh.ARRAY_BONES].size() / arrays[Mesh.ARRAY_VERTEX].size()
	var result := Vector3.ZERO
	for influence in count:
		var offset := index * count + influence
		var weight: float = arrays[Mesh.ARRAY_WEIGHTS][offset]
		if weight == 0:
			continue
		var bind: int = arrays[Mesh.ARRAY_BONES][offset]
		var bone := skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		result += (skeleton.get_bone_global_pose(bone) * skin.get_bind_pose(bind) * vertex) * weight
	return skeleton.global_transform * result

func test_visible_masks_materials_and_deformed_vertices_match_sources() -> void:
	var ch: Character = await _spawn()
	var rig: KOTMCharacterRig = ch.visual.studio_rig
	var composite = rig.body_composite
	assert_true(composite.compatible, "all imported body regions share parent, transform and skin bindings")
	assert_true(composite.output != null and composite.output.skin != null)
	var masks := [
		{},
		{"top": "HoodieZip", "bottom": "ShortShorts", "feet": "CanvasShoes", "hands": "FingerlessGloves"},
		{"top": "TShirt", "bottom": "Leggings", "feet": "Sneakers"},
		{"top": "None", "bottom": "None", "feet": "None", "hands": "None"}]
	for skin_id in ["skin_medium", "skin_light", "skin_dark"]:
		for mask in masks:
			var loadout := SkinSystem.default_loadout()
			loadout["skin"] = skin_id
			loadout["kotm_wardrobe"] = mask
			rig.apply_loadout(loadout)
			var visible := {}
			for region in rig.body_regions:
				assert_eq(region.layers, 0, "original data nodes retained without duplicate rendering")
				if region.visible:
					visible[String(region.name)] = region
			assert_eq(composite.segments.size(), visible.size(), "exactly the active partition mask is composed")
			assert_eq(composite.output.mesh.get_surface_count(), 1, "shared skin material produces one body draw")
			assert_eq(composite.output.skeleton, rig.body_regions[0].skeleton)
			assert_true(composite.output.transform.is_equal_approx(rig.body_regions[0].transform))
			for segment in composite.segments:
				var region: MeshInstance3D = visible[segment.name]
				var source := region.mesh.surface_get_arrays(segment.source_surface)
				var merged: Array = composite.output.mesh.surface_get_arrays(segment.surface)
				var offset: int = segment.vertex_offset
				assert_true(composite.output.mesh.surface_get_material(segment.surface) == region.get_active_material(segment.source_surface), "material/skin tint is the active source material")
				for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
					if source[channel] == null:
						continue
					var per_vertex: int = source[channel].size() / segment.vertex_count
					var actual = merged[channel].slice(offset * per_vertex, (offset + segment.vertex_count) * per_vertex)
					assert_eq(actual, source[channel], "%s channel%d preserves authored attributes" % [segment.name, channel])
				var indices: PackedInt32Array = merged[Mesh.ARRAY_INDEX]
				var original_indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
				for index in original_indices.size():
					if indices[segment.index_offset + index] != original_indices[index] + offset:
						fail("triangle topology changed for " + segment.name)
						break
			for clip in ["KOTM_Idle", "KOTM_AR75_Aim", "KOTM_Crouch_Walk"]:
				rig.play(clip, 0)
				rig.player.seek(0.27, true)
				rig.player.advance(0)
				for segment in composite.segments:
					var region: MeshInstance3D = visible[segment.name]
					var source := region.mesh.surface_get_arrays(segment.source_surface)
					var merged: Array = composite.output.mesh.surface_get_arrays(segment.surface)
					for index in range(0, segment.vertex_count, maxi(1, segment.vertex_count / 7)):
						var a := _deform(source[Mesh.ARRAY_VERTEX][index], source, index, region.skin, rig.skeleton)
						var target_index: int = index + segment.vertex_offset
						var b := _deform(merged[Mesh.ARRAY_VERTEX][target_index], merged, target_index, composite.output.skin, rig.skeleton)
						assert_near(a.distance_to(b), 0, 0.000001, "rest/aim/crouch deformation identical")
			var count: int = composite.build_count
			rig.apply_visibility()
			assert_eq(composite.build_count, count, "unchanged outfit does not rebuild")
	ch.visual.visible = false
	assert_false(composite.output.is_visible_in_tree(), "first-person/death ancestor visibility hides composite")
	ch.queue_free()
	await settle(2)

func test_cache_reuse_and_face_detail_distance_preserve_silhouette() -> void:
	var first: Character = await _spawn()
	var second: Character = await _spawn()
	var a: KOTMCharacterRig = first.visual.studio_rig
	var b: KOTMCharacterRig = second.visual.studio_rig
	assert_true(a.body_composite.output.mesh == b.body_composite.output.mesh, "same outfit/skin shares ArrayMesh across actors")
	var faces := 0
	for mesh in b.avatar.find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name).begins_with("Eyes_sclera") or String(mesh.name).begins_with("Iris") or String(mesh.name).begins_with("Limbal") or String(mesh.name).begins_with("Pupil") or String(mesh.name).begins_with("Eyebrow"):
			faces += 1
			assert_near(mesh.visibility_range_end, 70.0)
			assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(faces, 10)
	assert_near(b.body_composite.output.visibility_range_end, 0, 0.001, "body silhouette has no new distance cutoff")
	assert_near(b.avatar.find_child("KOTM_Hair_SweptCrop", true, false).visibility_range_end, 0, 0.001, "hair silhouette retained")
	first.queue_free()
	second.queue_free()
	await settle(2)
