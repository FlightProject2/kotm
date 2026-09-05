#!/usr/bin/env python3
"""Bakes the 2 x 2 km test slice: heightmap, colour map, map preview, tree positions and the
building layout. Deterministic from the seed in this file. Run from the repo root:

    python3 tools/bake_map.py

Outputs (world/terrain/*): heightmap_2km.f32 (raw float32, converted to .res/.exr by
tools/godot/bake_terrain.gd), colormap_2km.png, preview_2km.png, trees_2km.json, pads_2km.json,
and design/map/slice_2km.json (the layout consumed by the game).
"""
import json, math, os, struct, zlib
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "world", "terrain")
os.makedirs(OUT, exist_ok=True)
SEED = 20160218
N = 2048            # pixels per side, 1 m per pixel
HALF = N // 2       # world x = px - HALF, world z = py - HALF
rng = np.random.default_rng(SEED)

# ---------------------------------------------------------------- noise
def perlin(shape, res, rng):
    """2D Perlin noise in [-1, 1] over `shape` pixels with `res` gradient cells per axis."""
    ys, xs = np.meshgrid(np.arange(shape[1]) * res[1] / shape[1], np.arange(shape[0]) * res[0] / shape[0], indexing="ij")
    x0 = np.floor(xs).astype(int); y0 = np.floor(ys).astype(int)
    fx = xs - x0; fy = ys - y0
    angles = rng.uniform(0, 2 * np.pi, (res[1] + 2, res[0] + 2))
    gx = np.cos(angles); gy = np.sin(angles)
    def dot(ix, iy, dx, dy):
        return gx[iy, ix] * dx + gy[iy, ix] * dy
    n00 = dot(x0, y0, fx, fy); n10 = dot(x0 + 1, y0, fx - 1, fy)
    n01 = dot(x0, y0 + 1, fx, fy - 1); n11 = dot(x0 + 1, y0 + 1, fx - 1, fy - 1)
    u = fx * fx * fx * (fx * (fx * 6 - 15) + 10); v = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
    nx0 = n00 * (1 - u) + n10 * u; nx1 = n01 * (1 - u) + n11 * u
    return (nx0 * (1 - v) + nx1 * v) * math.sqrt(2)

def fbm(res0, octaves, rng, gain=0.5):
    out = np.zeros((N, N)); amp = 1.0; res = res0; total = 0.0
    for _ in range(octaves):
        out += amp * perlin((N, N), (res, res), rng); total += amp
        amp *= gain; res *= 2
    return out / total

# ---------------------------------------------------------------- base terrain
xs = np.arange(N) - HALF; zs = np.arange(N) - HALF
X, Z = np.meshgrid(xs, zs)            # X[py, px], Z[py, px]
R = np.sqrt(X ** 2 + Z ** 2)
h = 22.0 + 18.0 * fbm(4, 4, rng) + 6.0 * fbm(16, 3, rng) + 1.2 * fbm(64, 2, rng)
mountain = 140.0 * np.exp(-(R ** 2) / (2 * 260.0 ** 2))
mountain *= 1.0 + 0.18 * fbm(16, 3, rng)      # ridges
h += mountain
cheb = np.maximum(np.abs(X), np.abs(Z))
h += np.clip(cheb - 940, 0, None) * 0.3        # rim hills at the map edge
h = np.clip(h, 4.0, None)

# ---------------------------------------------------------------- layout
def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)

def sample(arr, x, z):
    px = np.clip(x + HALF, 0, N - 1); py = np.clip(z + HALF, 0, N - 1)
    x0 = np.floor(px).astype(int); y0 = np.floor(py).astype(int)
    x1 = np.clip(x0 + 1, 0, N - 1); y1 = np.clip(y0 + 1, 0, N - 1)
    fx = px - x0; fy = py - y0
    return (arr[y0, x0] * (1 - fx) * (1 - fy) + arr[y0, x1] * fx * (1 - fy) + arr[y1, x0] * (1 - fx) * fy + arr[y1, x1] * fx * fy)

pois = [
    {"id": "the_mountain", "name": "The Mountain", "type": "mountain", "x": 0, "z": 0, "padRadius": 22},
    {"id": "ashford", "name": "Ashford", "type": "town", "x": 520, "z": 430, "padRadius": 150},
    {"id": "cranmoor", "name": "Cranmoor", "type": "village", "x": -560, "z": -300, "padRadius": 95},
    {"id": "bumjick_farm", "name": "Bumjick Farm", "type": "farm", "x": -540, "z": 520, "padRadius": 95},
    {"id": "hollis_farm", "name": "Hollis Farm", "type": "farm", "x": 500, "z": -560, "padRadius": 85},
    {"id": "rail_yard", "name": "Rail Yard", "type": "industrial", "x": -600, "z": -720, "padRadius": 120},
    {"id": "gas_station", "name": "Gas Station", "type": "commercial", "x": 300, "z": -210, "padRadius": 45},
    {"id": "hilltop_cabins", "name": "Hilltop Cabins", "type": "cabins", "x": 700, "z": -760, "padRadius": 0},
]
buildings = []
def add(prefab, x, z, yaw=0.0, node_class="residential", poi="", pad=0):
    buildings.append({"prefab": prefab, "x": round(float(x), 1), "z": round(float(z), 1), "yaw": round(float(yaw), 3),
                      "nodeClass": node_class, "poi": poi, "padRadius": pad})

# Ashford: 5 x 4 grid, 26 m lots, streets between rows
town = pois[1]; cols, rows, sp = 5, 4, 26
kinds = ["house_small", "house_two_storey", "house_small", "shop", "house_two_storey", "house_small", "diner",
         "house_small", "house_two_storey", "shop", "house_small", "house_small", "church", "house_two_storey",
         "house_small", "police_station", "house_small", "house_two_storey", "shop", "house_small"]
classes = {"shop": "commercial", "diner": "commercial", "police_station": "police", "church": "residential"}
i = 0
for r in range(rows):
    for c in range(cols):
        k = kinds[i % len(kinds)]; i += 1
        x = town["x"] + (c - (cols - 1) / 2) * sp; z = town["z"] + (r - (rows - 1) / 2) * (sp + 8)
        add(k, x, z, math.pi if r % 2 else 0.0, classes.get(k, "residential"), "ashford")
# Cranmoor: two rows along a main street
v = pois[2]
for j, k in enumerate(["house_small", "diner", "shop", "house_small", "house_two_storey", "motel", "house_small", "house_small", "shop", "house_small"]):
    side = -1 if j % 2 else 1
    add(k, v["x"] + (j // 2 - 2) * 30, v["z"] + side * 16, 0.0 if side > 0 else math.pi, classes.get(k, "residential"), "cranmoor")
# Farms (Quaternius barns) + a house each
for f in (pois[3], pois[4]):
    add("quat_bigbarn", f["x"], f["z"], 0.3, "industrial", f["id"])
    add("quat_barn", f["x"] + 42, f["z"] - 10, 1.2, "residential", f["id"])
    add("quat_silo", f["x"] + 30, f["z"] + 28, 0.0, "industrial", f["id"])
    add("quat_watertower", f["x"] - 40, f["z"] + 30, 0.0, "industrial", f["id"])
    add("house_small", f["x"] - 45, f["z"] - 35, 0.6, "residential", f["id"])
    add("quat_windmill", f["x"] + 5, f["z"] - 55, 0.0, "hunting", f["id"])
# Rail yard: two warehouses beside the rail line at x = -600
ry = pois[5]
add("warehouse", ry["x"] + 45, ry["z"] - 30, 0.0, "industrial", "rail_yard")
add("warehouse", ry["x"] + 45, ry["z"] + 40, 0.0, "industrial", "rail_yard")
add("shed", ry["x"] - 40, ry["z"] + 10, 1.57, "industrial", "rail_yard")
for k in range(6):
    add("railcar", ry["x"], ry["z"] - 60 + k * 22, 0.0, "industrial", "rail_yard")
add("gas_station", pois[6]["x"], pois[6]["z"], 0.0, "commercial", "gas_station")
add("radio_hut", 0, 0, 0.0, "military", "the_mountain")
add("radio_tower", 8, -6, 0.0, "military", "the_mountain")
# Hilltop cabins
cab = pois[7]
for k in range(6):
    a = k * 1.05; add("cabin", cab["x"] + math.cos(a) * 70, cab["z"] + math.sin(a) * 55, a, "residential", "hilltop_cabins", 14)
# Hunting stands
for (x, z) in [(-300, 800), (820, 120), (-850, 100), (200, 850)]:
    add("hunting_stand", x, z, rng.uniform(0, 6.28), "hunting", "", 8)
# Scattered barns/sheds (avoid POIs and the mountain)
def clear_of_pois(x, z, margin):
    if math.hypot(x, z) < 420: return False
    for p in pois:
        if p["padRadius"] and math.hypot(x - p["x"], z - p["z"]) < p["padRadius"] + margin: return False
    for b in buildings:
        if math.hypot(x - b["x"], z - b["z"]) < 60: return False
    return True
placed = 0
while placed < 20:
    x, z = rng.uniform(-900, 900, 2)
    if clear_of_pois(x, z, 40):
        add(["barn_small", "shed", "barn_small", "cabin"][placed % 4], x, z, rng.uniform(0, 6.28),
            "residential" if placed % 4 == 3 else "industrial", "", 18); placed += 1

# Roads
roads = []
ring = [[round(450 * math.cos(a), 1), round(450 * math.sin(a), 1)] for a in np.linspace(0, 2 * math.pi, 65)]
roads.append({"id": "ring", "type": "dirt", "width": 6, "points": ring})
def spoke(poi, width=6):
    a = math.atan2(poi["z"], poi["x"]); start = [450 * math.cos(a), 450 * math.sin(a)]
    return {"id": "spoke_" + poi["id"], "type": "dirt", "width": width, "points": [[round(start[0], 1), round(start[1], 1)], [poi["x"], poi["z"]]]}
for p in pois[1:8]:
    roads.append(spoke(p))
switch = []
for t in np.linspace(0, 1, 140):
    r = 450 - 420 * t; a = 0.8 + t * 2.6 * math.pi
    switch.append([round(r * math.cos(a), 1), round(r * math.sin(a), 1)])
roads.append({"id": "mountain_switchback", "type": "dirt", "width": 5, "points": switch})
roads.append({"id": "rail_line", "type": "rail", "width": 4, "points": [[-600, -1000], [-600, 1000]]})
roads.append({"id": "ashford_main", "type": "dirt", "width": 6, "points": [[town["x"] - 80, town["z"] + 17], [town["x"] + 80, town["z"] + 17]]})
roads.append({"id": "ashford_cross", "type": "dirt", "width": 6, "points": [[town["x"] - 80, town["z"] - 17], [town["x"] + 80, town["z"] - 17]]})
roads.append({"id": "cranmoor_main", "type": "dirt", "width": 6, "points": [[v["x"] - 80, v["z"]], [v["x"] + 80, v["z"]]]})

# ---------------------------------------------------------------- pads (flatten POIs and buildings)
pads = []
for p in pois:
    if p["padRadius"]:
        pads.append({"x": p["x"], "z": p["z"], "r": p["padRadius"], "id": p["id"]})
for b in buildings:
    if b["padRadius"] and b["poi"] not in ("ashford", "cranmoor", "bumjick_farm", "hollis_farm", "rail_yard", "gas_station"):
        pads.append({"x": b["x"], "z": b["z"], "r": b["padRadius"], "id": b["prefab"]})
for pad in pads:
    d = np.sqrt((X - pad["x"]) ** 2 + (Z - pad["z"]) ** 2)
    target = float(sample(h, np.array([pad["x"]]), np.array([pad["z"]]))[0])
    w = 1.0 - smoothstep(pad["r"], pad["r"] * 1.5, d)
    h = h * (1 - w) + target * w
    pad["height"] = round(target, 2)

# ---------------------------------------------------------------- roads: level across the width, tint the colour map
road_mask = np.zeros((N, N), dtype=np.float32)
rail_mask = np.zeros((N, N), dtype=np.float32)
def paint_segment(p, q, width, mask):
    global h
    x0, z0 = p; x1, z1 = q
    hw = width / 2 + 2.5
    minx = int(max(min(x0, x1) - hw - 1 + HALF, 0)); maxx = int(min(max(x0, x1) + hw + 1 + HALF, N - 1))
    minz = int(max(min(z0, z1) - hw - 1 + HALF, 0)); maxz = int(min(max(z0, z1) + hw + 1 + HALF, N - 1))
    if maxx <= minx or maxz <= minz: return
    sx = X[minz:maxz + 1, minx:maxx + 1]; sz = Z[minz:maxz + 1, minx:maxx + 1]
    dx, dz = x1 - x0, z1 - z0; L2 = max(dx * dx + dz * dz, 1e-6)
    t = np.clip(((sx - x0) * dx + (sz - z0) * dz) / L2, 0, 1)
    nx = x0 + t * dx; nz = z0 + t * dz
    d = np.sqrt((sx - nx) ** 2 + (sz - nz) ** 2)
    w = 1.0 - smoothstep(width / 2, hw, d)
    target = sample(h, nx, nz)
    sub = h[minz:maxz + 1, minx:maxx + 1]
    h[minz:maxz + 1, minx:maxx + 1] = sub * (1 - w) + target * w
    mask[minz:maxz + 1, minx:maxx + 1] = np.maximum(mask[minz:maxz + 1, minx:maxx + 1], 1.0 - smoothstep(width / 2 - 0.5, width / 2 + 1.0, d))
for road in roads:
    pts = road["points"]
    for a, b in zip(pts[:-1], pts[1:]):
        paint_segment(a, b, road["width"], rail_mask if road["type"] == "rail" else road_mask)

# ---------------------------------------------------------------- colour map and preview
grass = np.array([0.66, 0.74, 0.50]); dry = np.array([0.78, 0.74, 0.50]); rock = np.array([0.62, 0.60, 0.58]); snow = np.array([0.96, 0.96, 0.98])
dirt = np.array([0.52, 0.42, 0.30]); gravel = np.array([0.55, 0.53, 0.50])
var = 0.5 + 0.5 * fbm(32, 3, rng)
col = grass[None, None, :] * (1 - var[..., None] * 0.35) + dry[None, None, :] * (var[..., None] * 0.35)
hi = smoothstep(95, 115, h)[..., None]; col = col * (1 - hi) + rock[None, None, :] * hi
sn = smoothstep(120, 135, h)[..., None]; col = col * (1 - sn) + snow[None, None, :] * sn
col = col * (1 - road_mask[..., None]) + dirt[None, None, :] * road_mask[..., None]
col = col * (1 - rail_mask[..., None]) + gravel[None, None, :] * rail_mask[..., None]
col = np.clip(col, 0, 1)

def write_png(path, rgb8):
    hgt, wid, _ = rgb8.shape
    raw = b"".join(b"\x00" + rgb8[y].tobytes() for y in range(hgt))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", wid, hgt, 8, 2, 0, 0, 0)) +
                chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
write_png(os.path.join(OUT, "colormap_2km.png"), (col * 255).astype(np.uint8))

# preview: hillshade over colour, 1024 px
gy, gx = np.gradient(h)
shade = np.clip(0.65 + 0.35 * (-gx * 0.6 + gy * 0.8) / (1 + np.sqrt(gx ** 2 + gy ** 2)), 0.35, 1.0)
prev = np.clip(col * shade[..., None], 0, 1)[::2, ::2]
write_png(os.path.join(OUT, "preview_2km.png"), (prev * 255).astype(np.uint8))

# ---------------------------------------------------------------- trees
forest = fbm(6, 3, np.random.default_rng(SEED + 7))
trees = []
slope = np.sqrt(gx ** 2 + gy ** 2)
def blocked(x, z):
    px = int(x + HALF); pz = int(z + HALF)
    if road_mask[pz, px] > 0.05 or rail_mask[pz, px] > 0.05: return True
    if h[pz, px] > 112 or slope[pz, px] > 0.7: return True
    for p in pads:
        if math.hypot(x - p["x"], z - p["z"]) < p["r"] + 6: return True
    return False
b_xz = np.array([[b["x"], b["z"]] for b in buildings])
cand = rng.uniform(-1010, 1010, (60000, 2))
for x, z in cand:
    px = int(x + HALF); pz = int(z + HALF)
    f = forest[pz, px]
    dense = f > 0.12
    keep = rng.random() < (0.55 if dense else 0.04)
    if not keep: continue
    if blocked(x, z): continue
    if np.min(np.hypot(b_xz[:, 0] - x, b_xz[:, 1] - z)) < 18: continue
    hh = float(h[pz, px])
    species = ["tree_pineTallA", "tree_pineDefaultA", "tree_pineRoundA"][int(rng.integers(3))] if hh > 62 else \
              ["tree_oak", "tree_default", "tree_detailed", "tree_tall", "tree_thin"][int(rng.integers(5))]
    trees.append([round(float(x), 1), round(float(z), 1), species, round(float(rng.uniform(0.85, 1.3)), 2), round(float(rng.uniform(0, 6.283)), 2)])
# thin out too-close trees (min 3.5 m) using a grid
cell = {}; kept = []
for t in trees:
    k = (int(t[0] // 4), int(t[1] // 4)); ok = True
    for dx in (-1, 0, 1):
        for dz in (-1, 0, 1):
            for o in cell.get((k[0] + dx, k[1] + dz), []):
                if math.hypot(o[0] - t[0], o[1] - t[1]) < 3.5: ok = False; break
            if not ok: break
        if not ok: break
    if ok:
        kept.append(t); cell.setdefault(k, []).append(t)
trees = kept

# ---------------------------------------------------------------- write outputs
h32 = h.astype(np.float32)
h32.tofile(os.path.join(OUT, "heightmap_2km.f32"))
json.dump({"pads": pads, "min": float(h.min()), "max": float(h.max())}, open(os.path.join(OUT, "pads_2km.json"), "w"))
json.dump({"count": len(trees), "trees": trees}, open(os.path.join(OUT, "trees_2km.json"), "w"), separators=(",", ":"))
layout = {
    "id": "slice_2km", "seed": SEED, "halfSizeM": HALF, "vertexSpacing": 1.0, "regionSize": 512,
    "heightmap": "res://world/terrain/heightmap_2km.res", "heightmapExr": "res://world/terrain/heightmap_2km.exr",
    "colormap": "res://world/terrain/colormap_2km.png", "preview": "res://world/terrain/preview_2km.png",
    "trees": "res://world/terrain/trees_2km.json", "pads": "res://world/terrain/pads_2km.json",
    "north": "-z", "pois": pois, "buildings": buildings, "roads": roads,
    "spawnMaxHeightM": 110,
}
os.makedirs(os.path.join(ROOT, "design", "map"), exist_ok=True)
json.dump(layout, open(os.path.join(ROOT, "design", "map", "slice_2km.json"), "w"), indent=1)
print(f"heights: min {h.min():.1f} max {h.max():.1f} mean {h.mean():.1f}")
print(f"buildings: {len(buildings)}  roads: {len(roads)}  trees: {len(trees)}  pads: {len(pads)}")
for p in pads[:8]:
    print(f"  pad {p['id']:<16} h={p['height']}")
