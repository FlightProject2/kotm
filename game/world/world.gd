class_name World
extends Node3D
## Owns the terrain (our chunked snow mesh), lighting and the content containers.
## Gameplay height queries go through height_at(), backed by the baked HeightField.

var layout: MapLayout
var height_field: HeightField
var terrain: Node3D
var backend_name: String = ""
var colormap: Image
var loot_registry: LootRegistry
var loot_nodes: Array = []
var tree_bodies: Array[RID] = []
var tree_shapes: Array[RID] = []
var build_stats: Dictionary = {}

@onready var buildings: Node3D = $Buildings
@onready var trees: Node3D = $Trees
@onready var props: Node3D = $Props
@onready var loot: Node3D = $Loot
var vehicles: Node3D
@onready var projectiles: Node = $Projectiles
@onready var zone_root: Node3D = $Zone
@onready var characters: Node3D = $Characters

## mode is kept for the CLI ("auto" | "mesh"); the layout + heightmap are loaded and the terrain built.
func setup(mode: String = "auto", map_layout: MapLayout = null, build_content: bool = false) -> void:
	layout = map_layout if map_layout != null else MapLayout.load_default()
	height_field = HeightField.load_from(layout.heightmap_path, layout.vertex_spacing)
	assert(height_field != null, "World: heightmap missing")
	if layout.colormap_path != "":
		var tex: Texture2D = load(layout.colormap_path)
		if tex:
			colormap = tex.get_image()
	# one terrain, ours: chunked mesh from the baked HeightField (see MeshTerrainBackend)
	terrain = MeshTerrainBackend.build(self)
	backend_name = "mesh"
	add_child(terrain)
	move_child(terrain, 0)
	vehicles = Node3D.new()
	vehicles.name = "Vehicles"
	add_child(vehicles)
	_configure_environment()
	var ps := ProjectileSystem.new()
	ps.name = "ProjectileSystem"
	ps.world = self
	projectiles.add_child(ps)
	var tr := TracerRenderer.new()
	tr.name = "Tracers"
	tr.world = self
	add_child(tr)
	var fx := HitFx.new()
	fx.name = "HitFx"
	add_child(fx)
	loot_registry = LootRegistry.new()
	loot_registry.name = "LootRegistry"
	loot.add_child(loot_registry)
	if build_content:
		var t0 := Time.get_ticks_msec()
		build_stats = WorldBuilder.build(self)
		build_stats.merge(TreePlacer.build(self, trees))
		build_stats["ms"] = Time.get_ticks_msec() - t0
		print("World: built %s" % [build_stats])

## Renderer-specific environment. Exponential fog saturates on the Compatibility (WebGL)
## renderer, so the web build uses depth fog. "--env=a,b,c" flags (debug): nofog, linear, filmic,
## aces, ambientcolor, plain (all of nofog+linear+ambientcolor), depthfog.
func _configure_environment() -> void:
	var env: Environment = $Env.environment
	var flags: PackedStringArray = PackedStringArray()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--env="):
			flags = a.substr(6).split(",")
	if "plain" in flags:
		flags.append_array(PackedStringArray(["nofog", "linear", "ambientcolor"]))
	var web := OS.has_feature("web")
	if web:
		# the WebGL renderer over-exposes sky ambient + ACES: calmer, deterministic lighting
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 1.0
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.62, 0.66, 0.74)
		env.ambient_light_energy = 0.45
		var sun := get_node_or_null("Sun") as DirectionalLight3D
		if sun:
			sun.light_energy = 1.1
	if web or "depthfog" in flags:
		env.fog_mode = Environment.FOG_MODE_DEPTH
		env.fog_depth_begin = 220.0
		env.fog_depth_end = 1900.0
		env.fog_depth_curve = 1.0
		env.fog_density = 1.0
		env.fog_sky_affect = 0.25
	if "nofog" in flags:
		env.fog_enabled = false
	if "linear" in flags:
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	elif "filmic" in flags:
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	elif "aces" in flags:
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
	if "ambientcolor" in flags:
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.6, 0.65)
	print("World: env web=%s flags=%s fog=%s mode=%d tonemap=%d ambient=%d" % [web, flags, env.fog_enabled, env.fog_mode, env.tonemap_mode, env.ambient_light_source])

func _exit_tree() -> void:
	for b in tree_bodies:
		PhysicsServer3D.free_rid(b)
	for s in tree_shapes:
		PhysicsServer3D.free_rid(s)
	tree_bodies.clear()
	tree_shapes.clear()

func height_at(x: float, z: float) -> float:
	return height_field.height_at(x, z)

func height_at_v(p: Vector3) -> float:
	return height_field.height_at(p.x, p.z)

func slope_deg_at(x: float, z: float) -> float:
	return height_field.slope_deg_at(x, z)

func half_size() -> float:
	return layout.half_size
