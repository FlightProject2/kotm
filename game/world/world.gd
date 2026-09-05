class_name World
extends Node3D
## Owns the terrain (Terrain3D or the mesh fallback), lighting and the content containers.
## Gameplay height queries go through height_at(), backed by the baked HeightField.

var layout: MapLayout
var height_field: HeightField
var terrain: Node3D
var backend_name: String = ""
var colormap: Image

@onready var buildings: Node3D = $Buildings
@onready var trees: Node3D = $Trees
@onready var props: Node3D = $Props
@onready var loot: Node3D = $Loot
@onready var projectiles: Node = $Projectiles
@onready var zone_root: Node3D = $Zone
@onready var characters: Node3D = $Characters

## mode: "auto" | "terrain3d" | "mesh". Loads the layout + heightmap and builds the terrain.
func setup(mode: String = "auto", map_layout: MapLayout = null) -> void:
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

func height_at(x: float, z: float) -> float:
	return height_field.height_at(x, z)

func height_at_v(p: Vector3) -> float:
	return height_field.height_at(p.x, p.z)

func slope_deg_at(x: float, z: float) -> float:
	return height_field.slope_deg_at(x, z)

func half_size() -> float:
	return layout.half_size
