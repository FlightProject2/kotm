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
## Recolours the mannequin: chest item -> 'Azul' (body suit), legs item -> 'Blanco' (accents).
static func apply_to_character(vis: Node3D, loadout: Dictionary) -> void:
	var chest := item(String(loadout.get("chest", "")))
	var legs := item(String(loadout.get("legs", "")))
	for m in vis.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.get_parent_node_3d() == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(i)
			var mname := mat.resource_name if mat else ""
			if mname == "Azul" and not chest.is_empty():
				mi.set_surface_override_material(i, recipe_material(chest["recipe"], 0.9, 2.5))
			elif mname == "Blanco" and not legs.is_empty():
				mi.set_surface_override_material(i, recipe_material(legs["recipe"], 0.9, 2.5))

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
