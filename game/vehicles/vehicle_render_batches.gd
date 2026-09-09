extends RefCounted
## Preserve every mechanism/socket node while sharing static render surfaces.
## Parked tracks use a merged mesh; moving tracks retain their authored pivots.
static var _cache: Dictionary = {}
var tracks: Array[Dictionary] = []
var last_distance := 0.0
var moving := false
var source_id := ""
var model: Node3D

func setup(vehicle: Vehicle) -> Dictionary:
	model = vehicle.model
	source_id = model.scene_file_path
	var animator := vehicle.animator
	var anchors: Dictionary = {model: true}
	if animator.body:
		anchors[animator.body] = true
	for family in [animator.wheels, animator.steering, animator.wipers, animator.doors]:
		for part: Dictionary in family:
			anchors[part.node] = true
	var tread_nodes: Dictionary = {}
	for track: Dictionary in animator.tracks:
		var parts: Array[MeshInstance3D] = []
		for tread: Dictionary in track.treads:
			anchors[tread.node] = true
			tread_nodes[tread.node] = parts
		tracks.append({"reference":track.reference,"parts":parts,"render":null})
	var groups: Dictionary = {}
	var before := 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.skin != null:
			continue
		before += mesh.mesh.get_surface_count()
		var anchor: Node3D = mesh
		while not anchors.has(anchor):
			anchor = anchor.get_parent() as Node3D
		if tread_nodes.has(anchor):
			(tread_nodes[anchor] as Array).append(mesh)
			continue
		if not groups.has(anchor):
			groups[anchor] = []
		groups[anchor].append(mesh)
	var after := 0
	for anchor: Node3D in groups:
		var cache_key := source_id + ":" + String(model.get_path_to(anchor))
		var merged := _merge(anchor, groups[anchor], cache_key)
		var render := MeshInstance3D.new()
		render.name = "MechanismBatch"
		render.mesh = merged
		anchor.add_child(render)
		after += merged.get_surface_count()
		# MeshInstance nodes are retained: animation and external references stay valid.
		for original: MeshInstance3D in groups[anchor]:
			original.mesh = null
	for index in tracks.size():
		var track: Dictionary = tracks[index]
		var render := MeshInstance3D.new()
		render.name = "ParkedTrack_%d" % index
		render.mesh = _merge(track.reference, track.parts, source_id + ":track:" + str(index))
		track.reference.add_child(render)
		track.render = render
		after += render.mesh.get_surface_count()
		for original: MeshInstance3D in track.parts:
			original.visible = false
	return {"before":before,"parked_after":after,"tracks":tracks.size()}

func update(distance: float) -> void:
	var changed := absf(distance-last_distance) > .000001
	last_distance = distance
	if changed == moving:
		return
	moving = changed
	for track: Dictionary in tracks:
		if not moving:
			track.render.mesh = _merge(track.reference, track.parts, "")
		track.render.visible = not moving
		for original: MeshInstance3D in track.parts:
			original.visible = moving

static func _merge(anchor: Node3D, parts: Array, cache_key: String) -> ArrayMesh:
	if not cache_key.is_empty() and _cache.has(cache_key):
		return _cache[cache_key]
	var groups: Dictionary = {}
	for mesh: MeshInstance3D in parts:
		var xf := ModelLib._relative(mesh, anchor)
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface)
			var key := StaticWorldBatcher._material_key(material) + "|" + ModelLib._format_key(mesh.mesh,surface)
			if not groups.has(key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"tool":st,"material":material}
			(groups[key].tool as SurfaceTool).append_from(mesh.mesh,surface,xf)
	var merged := ArrayMesh.new()
	for group: Dictionary in groups.values():
		(group.tool as SurfaceTool).commit(merged)
		merged.surface_set_material(merged.get_surface_count()-1,group.material)
	if not cache_key.is_empty():
		_cache[cache_key] = merged
	return merged
