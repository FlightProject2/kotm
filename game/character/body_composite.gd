extends RefCounted
## Merge visible skin partitions in their shared authored space, once per mask/material state.
## Source nodes retain visibility, skinning and mesh data for wardrobe/hitbox tooling.
const CACHE_LIMIT := 64
static var mesh_cache: Dictionary = {}
var sources: Array[MeshInstance3D] = []
var output: MeshInstance3D
var compatible := false
var last_key := ""
var segments: Array = []
var build_count := 0
var cache_hits := 0

func setup(regions: Array[MeshInstance3D]) -> bool:
	if regions.is_empty():
		return false
	var reference := regions[0]
	if reference.skin == null or reference.mesh == null:
		return false
	for region in regions:
		if region.get_parent() != reference.get_parent() or not region.transform.is_equal_approx(reference.transform):
			return false # A future differently transformed asset keeps its original rendering.
		if region.skin == null or region.skeleton != reference.skeleton or region.skin.get_bind_count() != reference.skin.get_bind_count():
			return false
		for bind in reference.skin.get_bind_count():
			if region.skin.get_bind_bone(bind) != reference.skin.get_bind_bone(bind) or region.skin.get_bind_name(bind) != reference.skin.get_bind_name(bind) or not region.skin.get_bind_pose(bind).is_equal_approx(reference.skin.get_bind_pose(bind)):
				return false
		if region.mesh == null or region.mesh.get_blend_shape_count() > 0:
			return false
	sources = regions
	output = MeshInstance3D.new()
	output.name = "KOTM_VisibleBodyComposite"
	output.transform = reference.transform
	output.skin = reference.skin
	output.skeleton = reference.skeleton
	output.layers = reference.layers
	output.cast_shadow = reference.cast_shadow
	output.extra_cull_margin = reference.extra_cull_margin
	output.visible = false
	reference.get_parent().add_child(output)
	compatible = true
	return true

func update() -> void:
	if not compatible:
		return
	var key_parts := PackedStringArray()
	var visible_regions: Array[MeshInstance3D] = []
	for region in sources:
		region.layers = 0
		if not region.visible:
			continue
		visible_regions.append(region)
		key_parts.append(str(region.mesh.get_rid()))
		for surface in region.mesh.get_surface_count():
			var material := region.get_active_material(surface)
			key_parts.append(str(material.get_rid()) if material else "none")
	var key := "|".join(key_parts)
	output.visible = not visible_regions.is_empty()
	if key == last_key:
		return
	last_key = key
	if visible_regions.is_empty():
		output.mesh = null
		segments = []
		return
	if not mesh_cache.has(key):
		if mesh_cache.size() >= CACHE_LIMIT:
			mesh_cache.erase(mesh_cache.keys()[0])
		mesh_cache[key] = _combine(visible_regions)
		build_count += 1
	else:
		cache_hits += 1
	output.mesh = mesh_cache[key].mesh
	segments = mesh_cache[key].segments

func _combine(regions: Array[MeshInstance3D]) -> Dictionary:
	var groups: Dictionary = {}
	var mapping: Array = []
	for region in regions:
		for surface in region.mesh.get_surface_count():
			var material := region.get_active_material(surface)
			var format: int = region.mesh.surface_get_format(surface)
			var key := (str(material.get_rid()) if material else "none") + ":" + str(format)
			var arrays := region.mesh.surface_get_arrays(surface)
			if not groups.has(key):
				var empty := arrays.duplicate(true)
				for channel in Mesh.ARRAY_MAX:
					if empty[channel] != null:
						empty[channel].resize(0)
				empty[Mesh.ARRAY_INDEX] = PackedInt32Array()
				groups[key] = {"arrays": empty, "material": material, "surface": groups.size(), "flags": format & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS}
			var group: Dictionary = groups[key]
			var combined: Array = group.arrays
			var vertex_base: int = combined[Mesh.ARRAY_VERTEX].size()
			var vertex_count: int = arrays[Mesh.ARRAY_VERTEX].size()
			mapping.append({"name": String(region.name), "source_surface": surface, "surface": group.surface, "vertex_offset": vertex_base, "vertex_count": vertex_count, "index_offset": combined[Mesh.ARRAY_INDEX].size()})
			for channel in Mesh.ARRAY_INDEX:
				if arrays[channel] != null:
					var values = combined[channel]
					values.append_array(arrays[channel])
					combined[channel] = values
			var indices: PackedInt32Array = combined[Mesh.ARRAY_INDEX]
			var source_indices = arrays[Mesh.ARRAY_INDEX]
			if source_indices == null or source_indices.is_empty():
				for index in vertex_count:
					indices.append(vertex_base + index)
			else:
				for index in source_indices:
					indices.append(vertex_base + index)
			combined[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.resource_name = "Visible body skin partitions"
	for group: Dictionary in groups.values():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, group.arrays, [], {}, group.flags)
		mesh.surface_set_material(group.surface, group.material)
	return {"mesh": mesh, "segments": mapping}
