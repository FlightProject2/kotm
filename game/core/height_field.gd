class_name HeightField
extends RefCounted
## The gameplay truth for terrain height: the baked heightmap Image. Characters, projectiles,
## spawn selection and the camera clamp query this, so gameplay never depends on Terrain3D.
## Pixel (px, py) <-> world (x = px * spacing - half, z = py * spacing - half).

var image: Image
var size: int = 0
var half: float = 0.0
var spacing: float = 1.0

static func load_from(path: String, vertex_spacing := 1.0) -> HeightField:
	var hf := HeightField.new()
	var img: Image = ResourceLoader.load(path, "Image")
	if img == null:
		push_error("HeightField: cannot load " + path)
		return null
	hf.set_image(img, vertex_spacing)
	return hf

func set_image(img: Image, vertex_spacing := 1.0) -> void:
	image = img
	size = img.get_width()
	spacing = vertex_spacing
	half = size * spacing * 0.5

func raw(px: int, py: int) -> float:
	return image.get_pixel(clampi(px, 0, size - 1), clampi(py, 0, size - 1)).r

## Bilinear height at world x/z. Edge-clamped outside the map.
func height_at(x: float, z: float) -> float:
	var fx := (x + half) / spacing
	var fz := (z + half) / spacing
	var x0 := floori(fx)
	var z0 := floori(fz)
	var tx := fx - x0
	var tz := fz - z0
	var h00 := raw(x0, z0)
	var h10 := raw(x0 + 1, z0)
	var h01 := raw(x0, z0 + 1)
	var h11 := raw(x0 + 1, z0 + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

func height_at_v(p: Vector3) -> float:
	return height_at(p.x, p.z)

func normal_at(x: float, z: float) -> Vector3:
	var d := spacing
	var dx := height_at(x + d, z) - height_at(x - d, z)
	var dz := height_at(x, z + d) - height_at(x, z - d)
	return Vector3(-dx, 2.0 * d, -dz).normalized()

func slope_deg_at(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(normal_at(x, z).y, -1.0, 1.0)))

func inside(x: float, z: float, margin := 0.0) -> bool:
	return absf(x) < half - margin and absf(z) < half - margin

## First point along a segment that is below the terrain, as t in [0,1], or -1.0 if none.
func segment_hit(from: Vector3, to: Vector3, step := 1.5) -> float:
	var n := ceili(from.distance_to(to) / step) + 1
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := from.lerp(to, t)
		if p.y < height_at(p.x, p.z):
			return t
	return -1.0
