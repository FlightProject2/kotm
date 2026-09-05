class_name SkinSystem
extends RefCounted
## Cosmetic skins (docs 11, design/data/cosmetics.json). Recolours the mannequin's material
## slots and gun surfaces with procedural patterns; adds hat / mask / backpack attachments and
## the parachute canopy colour. Purely visual: never touches HealthState or weapon stats.

static var _tex_cache: Dictionary = {}

static func data() -> Dictionary:
	return DataLib.json("cosmetics")

static func item(id: String) -> Dictionary:
	for it in data()["items"]:
		if it["id"] == id:
			return it
	return {}

static func weapon_skin(id: String) -> Dictionary:
	for it in data()["weaponSkins"]:
		if it["id"] == id:
			return it
	return {}

static func items_for_slot(slot: String) -> Array:
	return data()["items"].filter(func(it): return it["slot"] == slot)

static func skins_for_weapon(weapon_id: String) -> Array:
	return data()["weaponSkins"].filter(func(it): return it["weapon"] == weapon_id)

static func default_loadout() -> Dictionary:
	var l: Dictionary = data()["defaultLoadout"].duplicate()
	l["weapons"] = {}
	return l

static func random_loadout(rng: RandomNumberGenerator) -> Dictionary:
	var l := default_loadout()
	for slot in data()["slots"]:
		var options := items_for_slot(slot)
		if options.is_empty():
			continue
		var optional: bool = slot in ["head", "face", "hands", "back"]
		if optional and rng.randf() < 0.45:
			l[slot] = ""
		else:
			l[slot] = options[rng.randi_range(0, options.size() - 1)]["id"]
	var weapons := {}
	for w in ["ar15", "ak47", "hunting_rifle", "shotgun_12g", "hellfire", "m9", "magnum44"]:
		var options := skins_for_weapon(w)
		if not options.is_empty() and rng.randf() < 0.5:
			weapons[w] = options[rng.randi_range(0, options.size() - 1)]["id"]
	l["weapons"] = weapons
	return l

# ---------- procedural pattern textures ----------
static func pattern_texture(pattern: String, base: Color, accent: Color) -> Texture2D:
	var key := "%s|%s|%s" % [pattern, base.to_html(), accent.to_html()]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var n := 128
	var img := Image.create_empty(n, n, true, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = pattern.hash()
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	var cell := FastNoiseLite.new()
	cell.seed = 7
	cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cell.frequency = 0.09
	var dark := base.darkened(0.35)
	for y in n:
		for x in n:
			var c := base
			match pattern:
				"stripe":
					c = accent if int(floor((x + y) / 12.0)) % 2 == 0 else base
				"checker":
					c = accent if (int(x / 16) + int(y / 16)) % 2 == 0 else base
				"camo":
					var v := noise.get_noise_2d(x, y)
					c = accent if v > 0.18 else (dark if v < -0.2 else base)
				"flames":
					var v := noise.get_noise_2d(x * 1.5, y * 0.6) * 0.35
					var t := float(y) / n + v
					c = accent if t > 0.55 else (accent.lerp(base, 0.5) if t > 0.45 else base)
				"snakeskin":
					var v := cell.get_noise_2d(x, y)
					c = accent if v < -0.55 else (base.lerp(accent, 0.25) if v < -0.35 else base)
				_:
					c = base
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex

static func make_material(color_hex: String, pattern: String, accent_hex: String, roughness := 0.85, tri_scale := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var base := Color(color_hex)
	m.roughness = roughness
	m.metallic = 0.0
	if pattern == "" or pattern == "solid":
		m.albedo_color = base
	else:
		m.albedo_color = Color.WHITE
		m.albedo_texture = pattern_texture(pattern, base, Color(accent_hex if accent_hex != "" else "#222222"))
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE * tri_scale
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m

static func recipe_material(recipe: Dictionary, roughness := 0.85, tri_scale := 2.0) -> StandardMaterial3D:
	return make_material(String(recipe.get("color", recipe.get("base", "#888888"))), String(recipe.get("pattern", "solid")), String(recipe.get("accent", "")), roughness, tri_scale)

# ---------- characters ----------
const SHIRT_MIN_Y := 0.98    ## waist: body-suit faces above this become the shirt
const SHOE_MAX_Y := 0.12     ## ankle: faces below this become shoes
static var _split_cache: Dictionary = {}   # source mesh RID -> split ArrayMesh

## The mannequin is one body suit ('Azul'). Split that surface into shirt / pants / shoes (by
## height) and head / hands (by the dominant skin bone) so clothes read as clothes and the skin
## shows. Skin weights are preserved. Cached per source mesh and shared by every character.
static var _head_bounds: Dictionary = {}   # source mesh RID -> AABB of the head in skeleton space

static func split_body_mesh(src: Mesh, mi: MeshInstance3D = null, skel: Skeleton3D = null) -> ArrayMesh:
	var key := src.get_rid()
	if _split_cache.has(key):
		return _split_cache[key]
	var out := ArrayMesh.new()
	var azul := -1
	for i in src.get_surface_count():
		var mat := src.surface_get_material(i)
		if mat and mat.resource_name == "Azul" and azul < 0:
			azul = i
	if azul < 0:
		_split_cache[key] = src
		return src
	var mdt := MeshDataTool.new()
	if mdt.create_from_surface(src, azul) != OK:
		_split_cache[key] = src
		return src
	# bind index -> part name for the skin bones
	var bone_part: Dictionary = {}
	if mi and mi.skin and skel:
		for b in mi.skin.get_bind_count():
			var bname := String(mi.skin.get_bind_name(b))
			if bname == "":
				var bi := mi.skin.get_bind_bone(b)
				bname = skel.get_bone_name(bi) if bi >= 0 else ""
			if bname == "head" or bname == "neck_01":
				bone_part[b] = "head"
			elif bname.begins_with("hand.") or bname.begins_with("thumb_") or bname.begins_with("ring_") or bname.begins_with("middle_") or bname.begins_with("index_"):
				bone_part[b] = "hands"
	var arrays := src.surface_get_arrays(azul)
	var vcount: int = arrays[Mesh.ARRAY_VERTEX].size()
	var bones_per := 4
	if arrays[Mesh.ARRAY_BONES] != null and vcount > 0:
		bones_per = int(arrays[Mesh.ARRAY_BONES].size() / vcount)
	var parts := {"shirt": SurfaceTool.new(), "pants": SurfaceTool.new(), "shoes": SurfaceTool.new(), "head": SurfaceTool.new(), "hands": SurfaceTool.new()}
	for name in parts:
		var st: SurfaceTool = parts[name]
		st.set_skin_weight_count(SurfaceTool.SKIN_8_WEIGHTS if bones_per == 8 else SurfaceTool.SKIN_4_WEIGHTS)
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var counts := {"shirt": 0, "pants": 0, "shoes": 0, "head": 0, "hands": 0}
	var head_aabb := AABB()
	var head_seen := false
	for f in mdt.get_face_count():
		var idx := [mdt.get_face_vertex(f, 0), mdt.get_face_vertex(f, 1), mdt.get_face_vertex(f, 2)]
		var y := 0.0
		var votes := {"head": 0.0, "hands": 0.0}
		for vi in idx:
			y += mdt.get_vertex(vi).y
			var vb := mdt.get_vertex_bones(vi)
			var vw := mdt.get_vertex_weights(vi)
			for k in vb.size():
				if bone_part.has(vb[k]):
					votes[bone_part[vb[k]]] += vw[k]
		y /= 3.0
		var part := "shirt" if y >= SHIRT_MIN_Y else ("shoes" if y < SHOE_MAX_Y else "pants")
		if votes["head"] > 1.5:
			part = "head"
		elif votes["hands"] > 1.5:
			part = "hands"
		var st: SurfaceTool = parts[part]
		counts[part] += 1
		for vi in idx:
			var v := mdt.get_vertex(vi)
			if part == "head":
				if not head_seen:
					head_aabb = AABB(v, Vector3.ZERO)
					head_seen = true
				else:
					head_aabb = head_aabb.expand(v)
			st.set_normal(mdt.get_vertex_normal(vi))
			st.set_uv(mdt.get_vertex_uv(vi))
			st.set_bones(mdt.get_vertex_bones(vi))
			st.set_weights(mdt.get_vertex_weights(vi))
			st.add_vertex(v)
	_head_bounds[key] = head_aabb
	var azul_mat := src.surface_get_material(azul)
	for i in src.get_surface_count():
		var arr: Array = src.surface_get_arrays(i) if i != azul else []
		if i == azul:
			# shirt takes the original slot so surface indices of the others stay stable
			var st: SurfaceTool = parts["shirt"]
			st.index()
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
			out.surface_set_name(out.get_surface_count() - 1, "shirt")
			out.surface_set_material(out.get_surface_count() - 1, azul_mat)
		else:
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			out.surface_set_name(out.get_surface_count() - 1, src.surface_get_name(i))
			out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(i))
	for name in ["pants", "shoes", "head", "hands"]:
		if counts[name] == 0:
			continue
		var st: SurfaceTool = parts[name]
		st.index()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays())
		out.surface_set_name(out.get_surface_count() - 1, name)
		out.surface_set_material(out.get_surface_count() - 1, azul_mat)
	_split_cache[key] = out
	return out

static func head_bounds(mesh: Mesh) -> AABB:
	# the split mesh is cached under the source RID; look up either
	for k in _split_cache:
		if _split_cache[k] == mesh or k == mesh.get_rid():
			return _head_bounds.get(k, AABB(Vector3(-0.1, 1.55, -0.1), Vector3(0.2, 0.25, 0.2)))
	return AABB(Vector3(-0.1, 1.55, -0.1), Vector3(0.2, 0.25, 0.2))

static func skin_material(loadout: Dictionary) -> StandardMaterial3D:
	var tone := item(String(loadout.get("skin", "")))
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(String(tone.get("recipe", {}).get("color", "#d9a37a")))
	m.roughness = 0.72
	m.metallic = 0.0
	return m

## Dresses the mannequin: shirt <- chest item, pants (+ 'Blanco' accents) <- legs item, shoes <-
## feet item, head and hands <- skin tone (hands <- gloves item when worn).
static func apply_to_character(vis: Node3D, loadout: Dictionary) -> void:
	var chest := item(String(loadout.get("chest", "")))
	var legs := item(String(loadout.get("legs", "")))
	var feet := item(String(loadout.get("feet", "")))
	var gloves := item(String(loadout.get("hands", "")))
	var skels := vis.find_children("*", "Skeleton3D", true, false)
	var skel: Skeleton3D = skels[0] if not skels.is_empty() else null
	for m in vis.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.get_parent_node_3d() == null:
			continue
		if mi.skin != null or mi.get_parent() is Skeleton3D:
			mi.mesh = split_body_mesh(mi.mesh, mi, skel)
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			var mname := mat.resource_name if mat else ""
			var sname: String = mi.mesh.surface_get_name(i)
			if sname == "shirt" or (mname == "Azul" and sname == ""):
				if not chest.is_empty():
					mi.set_surface_override_material(i, recipe_material(chest["recipe"], 0.9, 2.5))
			elif sname == "pants":
				if not legs.is_empty():
					mi.set_surface_override_material(i, recipe_material(legs["recipe"], 0.9, 2.5))
			elif sname == "shoes":
				if not feet.is_empty():
					mi.set_surface_override_material(i, recipe_material(feet["recipe"], 0.7, 4.0))
			elif sname == "head":
				mi.set_surface_override_material(i, skin_material(loadout))
			elif sname == "hands":
				mi.set_surface_override_material(i, recipe_material(gloves["recipe"], 0.8, 6.0) if not gloves.is_empty() else skin_material(loadout))
			elif mname == "Blanco" and not legs.is_empty():
				mi.set_surface_override_material(i, recipe_material(legs["recipe"], 0.9, 2.5))

## Eyes, brows, nose, mouth and hair built around the measured head, in the head bone's space.
## Returns a Node3D to parent under a BoneAttachment3D on "head".
static func build_face(skel: Skeleton3D, body_mesh: Mesh, loadout: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Face"
	var head_bi := skel.find_bone("head")
	if head_bi < 0:
		return root
	var hb := head_bounds(body_mesh)
	var c := hb.get_center()
	var w := maxf(hb.size.x, 0.12)
	var h := maxf(hb.size.y, 0.18)
	var front := hb.end.z
	var to_bone := skel.get_bone_global_rest(head_bi).affine_inverse()
	var skin := skin_material(loadout)
	var hair_item := item(String(loadout.get("hair", "")))
	var hair_col := Color(String(hair_item.get("recipe", {}).get("color", "#3b2617")))
	var style := String(hair_item.get("recipe", {}).get("style", "short"))
	var eye_white := StandardMaterial3D.new(); eye_white.albedo_color = Color(0.95, 0.95, 0.93); eye_white.roughness = 0.3
	var pupil := StandardMaterial3D.new(); pupil.albedo_color = Color(0.09, 0.07, 0.06); pupil.roughness = 0.25
	var brow_mat := StandardMaterial3D.new(); brow_mat.albedo_color = hair_col.darkened(0.2); brow_mat.roughness = 0.9
	var mouth_mat := StandardMaterial3D.new(); mouth_mat.albedo_color = skin.albedo_color.darkened(0.45).lerp(Color(0.5, 0.15, 0.15), 0.4); mouth_mat.roughness = 0.8
	var hair_mat := StandardMaterial3D.new(); hair_mat.albedo_color = hair_col; hair_mat.roughness = 0.85
	var nose_mat := StandardMaterial3D.new(); nose_mat.albedo_color = skin.albedo_color.darkened(0.08); nose_mat.roughness = 0.72
	for side_v in [-1.0, 1.0]:
		var side: float = side_v
		var ex: float = c.x + side * w * 0.2
		var ey: float = c.y + h * 0.06
		_add_part(root, to_bone, _sphere(0.017, 0.017, eye_white), Vector3(ex, ey, front - 0.008))
		_add_part(root, to_bone, _sphere(0.008, 0.005, pupil), Vector3(ex, ey, front + 0.006))
		var brow := _box(Vector3(w * 0.24, 0.009, 0.012), brow_mat)
		_add_part(root, to_bone, brow, Vector3(ex, ey + 0.034, front - 0.004), Basis(Vector3.FORWARD, side * 0.12))
	_add_part(root, to_bone, _box(Vector3(0.022, 0.04, 0.02), nose_mat), Vector3(c.x, c.y - h * 0.04, front + 0.006))
	_add_part(root, to_bone, _box(Vector3(w * 0.3, 0.007, 0.012), mouth_mat), Vector3(c.x, c.y - h * 0.22, front - 0.003))
	if style != "bald":
		var hair := _sphere(1.0, 1.0, hair_mat)
		var scale := Vector3(w * 0.56, h * (0.36 if style == "buzz" else 0.5), hb.size.z * 0.58)
		var pos := Vector3(c.x, c.y + h * (0.24 if style == "buzz" else 0.16), c.z - hb.size.z * 0.1)
		_add_part(root, to_bone, hair, pos, Basis().scaled(scale))
		if style == "long":
			var tail := _box(Vector3(w * 0.9, h * 1.1, hb.size.z * 0.35), hair_mat)
			_add_part(root, to_bone, tail, Vector3(c.x, c.y - h * 0.35, hb.position.z + hb.size.z * 0.12))
	return root

static func _sphere(r: float, ry: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r; sm.height = ry * 2.0
	sm.radial_segments = 12; sm.rings = 6
	mi.mesh = sm
	mi.material_override = mat
	return mi

static func _box(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	return mi

static func _add_part(root: Node3D, to_bone: Transform3D, part: MeshInstance3D, pos: Vector3, basis := Basis()) -> void:
	part.transform = to_bone * Transform3D(basis, pos)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(part)

## Builds hat / mask / backpack meshes. Returns {"hat": Node3D, "mask": Node3D, "back": Node3D} (any may be null).
static func build_attachments(loadout: Dictionary) -> Dictionary:
	var out := {"hat": null, "mask": null, "back": null}
	var hat := item(String(loadout.get("head", "")))
	if not hat.is_empty():
		out["hat"] = _hat_mesh(hat["recipe"])
	var mask := item(String(loadout.get("face", "")))
	if not mask.is_empty():
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.18, 0.12, 0.06)
		mi.mesh = bm
		mi.material_override = recipe_material(mask["recipe"], 0.6, 6.0)
		mi.position = Vector3(0, 0.02, 0.12)
		out["mask"] = mi
	var back := item(String(loadout.get("back", "")))
	if not back.is_empty():
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(0.32, 0.4, 0.18)
		mi.mesh = bm
		mi.material_override = recipe_material(back["recipe"], 0.9, 3.0)
		mi.position = Vector3(0, 0.1, -0.2)
		out["back"] = mi
	return out

static func _hat_mesh(recipe: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mat := recipe_material(recipe, 0.9, 6.0)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(String(recipe.get("accent", "#222222")))
	match String(recipe.get("shape", "cap")):
		"boonie":
			var crown := MeshInstance3D.new()
			var cm := CylinderMesh.new(); cm.top_radius = 0.11; cm.bottom_radius = 0.13; cm.height = 0.12
			crown.mesh = cm; crown.material_override = mat; crown.position.y = 0.12
			var brim := MeshInstance3D.new()
			var bmesh := CylinderMesh.new(); bmesh.top_radius = 0.2; bmesh.bottom_radius = 0.21; bmesh.height = 0.015
			brim.mesh = bmesh; brim.material_override = mat; brim.position.y = 0.065
			root.add_child(crown); root.add_child(brim)
		"beanie":
			var mi := MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = 0.15; sm.height = 0.2; sm.is_hemisphere = true
			mi.mesh = sm; mi.material_override = mat; mi.position.y = 0.04
			var band := MeshInstance3D.new()
			var cm := CylinderMesh.new(); cm.top_radius = 0.152; cm.bottom_radius = 0.152; cm.height = 0.04
			band.mesh = cm; band.material_override = accent; band.position.y = 0.05
			root.add_child(mi); root.add_child(band)
		_:
			var crown := MeshInstance3D.new()
			var sm := SphereMesh.new(); sm.radius = 0.15; sm.height = 0.16; sm.is_hemisphere = true
			crown.mesh = sm; crown.material_override = mat; crown.position.y = 0.06
			var peak := MeshInstance3D.new()
			var bm := BoxMesh.new(); bm.size = Vector3(0.16, 0.012, 0.12)
			peak.mesh = bm; peak.material_override = accent; peak.position = Vector3(0, 0.07, 0.15)
			root.add_child(crown); root.add_child(peak)
	return root

static func parachute_color(loadout: Dictionary) -> Color:
	var it := item(String(loadout.get("parachute", "")))
	return Color(String(it["recipe"].get("color", "#c8102e"))) if not it.is_empty() else Color("c8102e")

# ---------- weapons ----------
const BASE_SURFACES := ["grey", "greyDark", "Metal", "BulletYellow", "BulletTip"]
const ACCENT_SURFACES := ["dark", "Black", "Wood", "_defaultMat"]

static func apply_to_weapon(model: Node3D, skin: Dictionary) -> void:
	if skin.is_empty():
		return
	var recipe: Dictionary = skin["recipe"]
	var base := make_material(String(recipe.get("base", "#888888")), String(recipe.get("pattern", "solid")), String(recipe.get("accent", "#222222")), 0.55, 12.0)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(String(recipe.get("accent", "#222222")))
	accent.roughness = 0.7
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			var mname := mat.resource_name if mat else ""
			if mname == "glass":
				continue
			mi.set_surface_override_material(i, accent if ACCENT_SURFACES.has(mname) else base)
