class_name StaticWorldBatcher
extends RefCounted
## Bake static scenery surfaces by material into spatial chunks. Physics and loot
## nodes remain in their original hierarchy. Animated/scripted props are excluded.
const CELL := 128.0
static var _material_keys: Dictionary = {}
static var _texture_keys: Dictionary = {}

static func _texture_key(texture: Texture2D) -> String:
	var id := texture.get_instance_id()
	if _texture_keys.has(id):
		return _texture_keys[id]
	var image := texture.get_image()
	var key := str(id)
	if image:
		key = "%s:%s:%s:%s" % [image.get_width(),image.get_height(),image.get_format(),image.get_data().hex_encode().sha256_text()]
	_texture_keys[id] = key
	return key

static func _material_key(material: Material) -> String:
	if material == null:
		return "none"
	var id := material.get_instance_id()
	if _material_keys.has(id):
		return _material_keys[id]
	# Shader materials may contain renderer-specific uniforms; share only exact resources.
	if not material is BaseMaterial3D:
		return str(id)
	var values: Array[String] = []
	for property: Dictionary in material.get_property_list():
		var name: String = property.name
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0 or name.begins_with("resource_") or name.begins_with("metadata/") or name == "script":
			continue
		var value: Variant = material.get(name)
		if value is Texture2D:
			values.append(name + "=" + _texture_key(value))
		elif value is Resource:
			values.append(name + "=" + str(value.get_instance_id()))
		else:
			values.append(name + "=" + str(value))
	var key := "|".join(values).sha256_text()
	_material_keys[id] = key
	return key

static func _static_path(mesh: MeshInstance3D, root: Node3D) -> bool:
	if mesh.has_meta("breakable_window") or mesh.skin != null or mesh.get_script() != null or mesh.get_child_count() > 0:
		return false
	var parent := mesh.get_parent()
	while parent != root and parent != null:
		if parent.get_script() != null or parent is RigidBody3D or parent is CharacterBody3D or parent is BoneAttachment3D:
			return false
		if parent.has_meta("destructible") or parent.has_meta("animated"):
			return false
		parent = parent.get_parent()
	return true

static func build(world: World) -> Dictionary:
	var output := Node3D.new()
	output.name = "StaticSceneryBatches"
	world.add_child(output)
	var chunks: Dictionary = {}
	var originals: Array[MeshInstance3D] = []
	var before := 0
	for source: Node3D in [world.buildings,world.props]:
		for node in source.find_children("*","MeshInstance3D",true,false):
			var mesh := node as MeshInstance3D
			if mesh.mesh == null or not mesh.is_visible_in_tree() or not _static_path(mesh,source):
				continue
			var center := (mesh.global_transform * mesh.mesh.get_aabb()).get_center()
			var cell := Vector2i(floori(center.x/CELL),floori(center.z/CELL))
			var key := "%d,%d" % [cell.x,cell.y]
			var origin := Vector3((cell.x+.5)*CELL,0,(cell.y+.5)*CELL)
			if not chunks.has(key):
				chunks[key] = {"origin":origin,"groups":{}}
			var groups: Dictionary = chunks[key].groups
			var transform := mesh.global_transform
			transform.origin -= origin
			for surface in mesh.mesh.get_surface_count():
				var material: Material = mesh.get_active_material(surface)
				var layout := ModelLib._format_key(mesh.mesh,surface)
				var group := _material_key(material) + "|" + layout + "|" + str(mesh.cast_shadow)
				if not groups.has(group):
					var tool := SurfaceTool.new()
					tool.begin(Mesh.PRIMITIVE_TRIANGLES)
					groups[group] = {"tool":tool,"material":material,"shadow":mesh.cast_shadow}
				(groups[group].tool as SurfaceTool).append_from(mesh.mesh,surface,transform)
				before += 1
			originals.append(mesh)
	var after := 0
	for key in chunks:
		var chunk: Dictionary = chunks[key]
		# Keep shadow modes separate, so non-shadow glass/decals retain their contract.
		var by_shadow: Dictionary = {}
		for group: Dictionary in chunk.groups.values():
			var shadow := int(group.shadow)
			if not by_shadow.has(shadow):
				by_shadow[shadow] = ArrayMesh.new()
			var merged: ArrayMesh = by_shadow[shadow]
			(group.tool as SurfaceTool).commit(merged)
			merged.surface_set_material(merged.get_surface_count()-1,group.material)
			after += 1
		for shadow in by_shadow:
			var mesh := MeshInstance3D.new()
			mesh.name = "Scenery_%s_%s" % [key.replace(",","_"),shadow]
			mesh.mesh = by_shadow[shadow]
			mesh.position = chunk.origin
			mesh.cast_shadow = shadow
			mesh.visibility_range_end = 1900.0
			mesh.visibility_range_end_margin = 100.0
			output.add_child(mesh)
	for mesh in originals:
		mesh.get_parent().remove_child(mesh)
		mesh.queue_free()
	# Interactive vehicles keep all moving parts and their animation nodes.
	for mesh in world.vehicles.find_children("*","GeometryInstance3D",true,false):
		mesh.visibility_range_end = 600.0
		mesh.visibility_range_end_margin = 60.0
	var report := {"static_meshes_batched":originals.size(),"static_surfaces_before":before,"static_surfaces_after":after,"static_chunks":output.get_child_count()}
	print("StaticWorldBatcher: ",report)
	return report
