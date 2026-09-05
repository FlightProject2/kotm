class_name World
extends Node3D
## Owns the terrain (Terrain3D or the mesh fallback), lighting and the content containers.
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

## mode: "auto" | "terrain3d" | "mesh". Loads the layout + heightmap and builds the terrain.
func setup(mode: String = "auto", map_layout: MapLayout = null, build_content: bool = false) -> void:
	layout = map_layout if map_layout != null else MapLayout.load_default()
	height_field = HeightField.load_from(layout.heightmap_path, layout.vertex_spacing)
	assert(height_field != null, "World: heightmap missing")
	if layout.colormap_path != "":
		var tex: Texture2D = load(layout.colormap_path)
		if tex:
			colormap = tex.get_image()
	var want_t3d := mode == "terrain3d" or (mode == "auto" and ClassDB.class_exists("Terrain3D") and DisplayServer.get_name() != "headless")
	if want_t3d and ClassDB.class_exists("Terrain3D"):
		terrain = Terrain3DBackend.build(self)
		backend_name = "terrain3d"
	else:
		terrain = MeshTerrainBackend.build(self)
		backend_name = "mesh"
	add_child(terrain)
	move_child(terrain, 0)
	vehicles = Node3D.new()
	vehicles.name = "Vehicles"
	add_child(vehicles)
	# Exponential fog saturates on the Compatibility (WebGL) renderer: use explicit depth fog there.
	if OS.has_feature("web") or "--env=depthfog" in OS.get_cmdline_user_args():
		var wenv: Environment = $Env.environment
		wenv.fog_mode = Environment.FOG_MODE_DEPTH
		wenv.fog_depth_begin = 220.0
		wenv.fog_depth_end = 1900.0
		wenv.fog_depth_curve = 1.0
		wenv.fog_density = 1.0
		wenv.fog_sky_affect = 0.25
		print("World: depth fog")
	if "--env=plain" in OS.get_cmdline_user_args():
		# render debugging: no fog, flat ambient, linear tonemap
		var env: Environment = $Env.environment
		env.fog_enabled = false
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.6, 0.6, 0.65)
		print("World: plain environment")
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
