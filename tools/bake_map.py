#!/usr/bin/env python3
"""Bake KOTM's deterministic 2 km winter valley, terrain and authored location layout.

Run: python tools/bake_map.py [--project /path/to/project]
The standalone output/map-v1 copy defaults to the workspace's kotm-live project.
The integrated tools/bake_map.py defaults to its own project root.

surface_mask_2km.png is linear data: R = road, G = rail bed, B = frozen water.
Frozen water is carved directly into the heightfield; no offset water plane or separate
collision is needed. The same ground surface is drawn and collidable at all times.
"""
import argparse, json, math, os, struct, zlib
from pathlib import Path
import numpy as np

_script = Path(__file__).resolve()
_default_project = _script.parents[1] if _script.parent.name == "tools" else _script.parents[2] / "kotm-live"
_args = argparse.ArgumentParser(description=__doc__)
_args.add_argument("--project", type=Path, default=_default_project)
ROOT = str(_args.parse_args().project.resolve())
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

# ---------------------------------------------------------------- base terrain: a broad valley framed by an irregular mountain rim
def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t)

xs = np.arange(N) - HALF; zs = np.arange(N) - HALF
X, Z = np.meshgrid(xs, zs)            # X[py, px], Z[py, px]
R = np.sqrt(X ** 2 + Z ** 2)
h = 29.0 + 19.0 * fbm(4, 4, rng) + 5.5 * fbm(16, 3, rng) + 0.55 * fbm(64, 2, rng)
# Keep the existing summit finish playable, but leave much more low rolling ground
# around it. The landmark is subordinate to the surrounding mountain skyline.
summit = 131.0 * np.exp(-(R ** 2) / (2 * 195.0 ** 2))
summit *= 1.0 + 0.14 * fbm(16, 3, rng)
h += summit
cheb = np.maximum(np.abs(X), np.abs(Z))
rim_noise = fbm(12, 3, rng)
h += smoothstep(735.0, 1060.0, cheb + rim_noise * 75.0) * (42.0 + 18.0 * rim_noise)
# Individual elongated peaks give the perimeter an authored, broken silhouette.
# Northern/eastern peaks are taller; the southern rim has low traverseable saddles.
peaks = [(-970,-855,147,130,150),(-770,-985,152,145,125),(-360,-960,184,135,130),
         (20,-1010,137,125,125),(310,-950,173,128,110),(720,-1005,169,140,105),
         (980,-800,180,105,140),(955,-360,184,100,135),(1000,45,153,100,120),
         (1010,405,113,95,115),(910,965,133,125,100),(530,1020,126,135,105),
         (50,970,125,120,115),(-365,1025,136,135,105),(-850,970,137,125,115),
         (-995,635,161,100,140),(-1030,290,112,85,125),(-980,-110,176,100,130),
         (-1010,-470,162,100,130)]
for cx, cz, height, rx, rz in peaks:
    d2 = ((X-cx)/rx)**2 + ((Z-cz)/rz)**2
    shoulder = np.exp(-0.5*d2)
    h += height * shoulder * (1.0 + 0.16 * rim_noise)
# Incised, branching gullies break up the broad mountain forms into narrow snowy
# ridgelines. Fade by elevation AND edge distance so the valley stays drivable.
gully_noise=fbm(28,4,np.random.default_rng(SEED+29))
ridge_weight=smoothstep(690.0,880.0,cheb)*smoothstep(75.0,145.0,h)
h += (7.0-35.0*np.abs(gully_noise))*ridge_weight
# A differentiable soft cap, never a clipped flat mountain top.
h = np.where(h>228.0,260.0-32.0*np.exp(-(h-228.0)/32.0),h)
h = np.maximum(h,7.0)
# A low, elongated radio ridge interrupts the northern plain without creating
# another circular mountain. Its southwest shoulder carries the service lane.
h += 39.0*np.exp(-0.5*(((X-100.0)/150.0)**2+((Z+705.0)/82.0)**2))*(1.0+0.08*rim_noise)

def smooth_path(anchors, step=3.0, closed=False):
    """Catmull-Rom samples, retaining every authored junction exactly."""
    pts = [np.array(p, dtype=float) for p in anchors]
    if closed and np.allclose(pts[0], pts[-1]): pts.pop()
    result = []
    count = len(pts) if closed else len(pts)-1
    for i in range(count):
        p1 = pts[i]; p2 = pts[(i+1)%len(pts)]
        p0 = pts[(i-1)%len(pts)] if closed or i else p1
        p3 = pts[(i+2)%len(pts)] if closed or i+2 < len(pts) else p2
        n = max(2, int(np.linalg.norm(p2-p1)/step))
        for t in np.linspace(0,1,n,endpoint=False):
            p = 0.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t*t*t)
            result.append([round(float(p[0]),1), round(float(p[1]),1)])
    result.append(result[0] if closed else [float(v) for v in pts[-1]])
    return result

# ---------------------------------------------------------------- frozen river and lakes
ice_mask = np.zeros((N,N), dtype=np.float32)
water_influence = np.zeros((N,N), dtype=np.float32)
ice_height = 18.0
river_points = smooth_path([[-805,155],[-665,190],[-520,255],[-390,260],[-235,340],
                           [-110,420],[5,440],[130,570],[280,630],[420,645],[575,710],
                           [705,655],[815,625]], step=8.0)
def channel_segment(p, q, width):
    x0,z0=p; x1,z1=q; hw=width/2.0; bank=52.0
    minx=max(0,int(min(x0,x1)-hw-bank+HALF)); maxx=min(N-1,int(max(x0,x1)+hw+bank+HALF))
    minz=max(0,int(min(z0,z1)-hw-bank+HALF)); maxz=min(N-1,int(max(z0,z1)+hw+bank+HALF))
    sx=X[minz:maxz+1,minx:maxx+1]; sz=Z[minz:maxz+1,minx:maxx+1]
    dx=x1-x0; dz=z1-z0
    t=np.clip(((sx-x0)*dx+(sz-z0)*dz)/max(dx*dx+dz*dz,1e-6),0,1)
    d=np.hypot(sx-(x0+t*dx),sz-(z0+t*dz))
    target=ice_mask[minz:maxz+1,minx:maxx+1]
    np.maximum(target,1.0-smoothstep(hw-2.0,hw+1.0,d),out=target)
    target=water_influence[minz:maxz+1,minx:maxx+1]
    np.maximum(target,1.0-smoothstep(hw+2.0,hw+bank,d),out=target)
for i,(a,b) in enumerate(zip(river_points[:-1],river_points[1:])):
    channel_segment(a,b,27.0+5.0*math.sin(i*0.17))
lakes = [{"id":"west_frozen_lake","name":"Frostmere","x":-805,"z":155,"rx":95,"rz":66},
         {"id":"east_frozen_lake","name":"Stillwater","x":815,"z":625,"rx":88,"rz":105}]
for lake in lakes:
    angle=np.arctan2((Z-lake["z"])/lake["rz"],(X-lake["x"])/lake["rx"])
    outline=1.0+0.065*np.sin(angle*3.0)+0.035*np.cos(angle*5.0)
    d=np.hypot((X-lake["x"])/lake["rx"],(Z-lake["z"])/lake["rz"])/outline
    ice_mask=np.maximum(ice_mask,1.0-smoothstep(0.97,1.025,d))
    # Broad, graduated shore slopes keep the lakes seated in a valley instead
    # of carving vertical quarry bowls into the mountain rim.
    water_influence=np.maximum(water_influence,1.0-smoothstep(1.03,2.85,d))
h=h*(1.0-water_influence)+ice_height*water_influence

# ---------------------------------------------------------------- layout
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
    {"id": "frostmere_lodge", "name": "Frostmere Lodge", "type": "lodge", "x": -770, "z": -25, "padRadius": 32},
    {"id": "riverside_mill", "name": "Riverside Mill", "type": "industrial", "x": -340, "z": 525, "padRadius": 45},
    {"id": "north_radar", "name": "North Radar", "type": "military", "x": 85, "z": -690, "padRadius": 32},
    {"id": "east_ranger_camp", "name": "East Ranger Camp", "type": "cabins", "x": 725, "z": 80, "padRadius": 30},
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
        if r==1: z-=14.0
        elif r==2: z+=15.0
        # Face the two inner rows toward their streets, with all footprints
        # between the street centre lines instead of occupying the carriageway.
        add(k, x, z, 0.0 if r % 2 else math.pi, classes.get(k, "residential"), "ashford")
# Cranmoor: two rows along a main street
v = pois[2]
for j, k in enumerate(["house_small", "diner", "shop", "house_small", "house_two_storey", "motel", "house_small", "house_small", "shop", "house_small"]):
    side = -1 if j % 2 else 1
    bx=v["x"]+(j//2-2)*30
    if k=="diner": bx+=12.0
    add(k, bx, v["z"] + side * 16, 0.0 if side > 0 else math.pi, classes.get(k, "residential"), "cranmoor")
# Farms (Quaternius barns) + a house each
for f in (pois[3], pois[4]):
    add("quat_bigbarn", f["x"], f["z"]+25 if f["id"]=="hollis_farm" else f["z"], 0.3, "industrial", f["id"])
    add("quat_barn", f["x"] + 42, f["z"] - 10, 1.2, "residential", f["id"])
    add("quat_silo", f["x"] + 30, f["z"] + (15 if f["id"]=="bumjick_farm" else 28), 0.0, "industrial", f["id"])
    add("quat_watertower", f["x"] - 40, f["z"] + 30, 0.0, "industrial", f["id"])
    add("house_small", f["x"] - 45, f["z"] - 35, 0.6, "residential", f["id"])
    add("quat_windmill", f["x"] + 5, f["z"] - 55, 0.0, "hunting", f["id"])
# Rail yard: two warehouses beside the rail line at x = -600
ry = pois[5]
add("warehouse", ry["x"] + 45, ry["z"] - 30, 0.0, "industrial", "rail_yard")
add("warehouse", ry["x"] + 45, ry["z"] + 40, 0.0, "industrial", "rail_yard")
add("shed", ry["x"] - 40, ry["z"] + 10, 1.57, "industrial", "rail_yard")
for k in range(6):
    add("railcar", ry["x"], ry["z"] - 60 + k * 22 + (20 if k==5 else 0), 0.0, "industrial", "rail_yard")
add("gas_station", pois[6]["x"], pois[6]["z"], 0.0, "commercial", "gas_station")
add("radio_hut", 0, 0, 0.0, "military", "the_mountain")
add("radio_tower", 8, -6, 0.0, "military", "the_mountain")
# Hilltop cabins
cab = pois[7]
for k in range(6):
    a = k * 1.05; add("cabin", cab["x"] + math.cos(a) * 70, cab["z"] + math.sin(a) * 55, a, "residential", "hilltop_cabins", 14)
# Civic edges and a second neighbourhood make Ashford feel inhabited at ground
# level. The original 150 m district pad remains the shared flat settlement.
for prefab,x,z,yaw in [("house_small",475,343,0),("house_two_storey",500,343,0),
                       ("house_small",545,343,0),("house_two_storey",570,343,0),
                       ("house_small",474,518,math.pi),("house_small",570,518,math.pi)]:
    add(prefab,x,z,yaw,"residential","ashford")
add("shop",520,518,math.pi,"commercial","ashford")
add("shed",591,475,math.pi/2,"industrial","ashford")
for x,z in [(-612,-359),(-550,-356),(-498,-358)]:
    add("shed",x,z,math.pi,"industrial","cranmoor")
add("motel",-558,-240,math.pi,"residential","cranmoor")
# Small destinations with distinct silhouettes and useful road connections.
for prefab,x,z,yaw,kind in [("motel",-784,-32,math.pi/2,"residential"),
                          ("cabin",-754,-43,0,"residential"),("shed",-757,-6,0,"industrial")]:
    add(prefab,x,z,yaw,kind,"frostmere_lodge")
for prefab,x,z,yaw in [("warehouse",-352,515,0),("shed",-320,505,1.57),
                       ("barn_small",-319,543,math.pi),("shed",-367,547,0)]:
    add(prefab,x,z,yaw,"industrial","riverside_mill")
for prefab,x,z,yaw in [("radio_tower",82,-691,0),("radio_hut",100,-691,0),
                       ("shed",68,-677,1.57),("shed",104,-674,0)]:
    add(prefab,x,z,yaw,"military","north_radar")
for prefab,x,z,yaw,kind in [("cabin",711,84,math.pi,"residential"),
                           ("cabin",739,94,math.pi,"residential"),
                           ("shed",741,62,0,"industrial"),("hunting_stand",710,68,0,"hunting")]:
    add(prefab,x,z,yaw,kind,"east_ranger_camp")
# Hunting stands
for (x, z) in [(-300, 800), (820, 120), (-895, -20), (200, 850)]:
    add("hunting_stand", x, z, rng.uniform(0, 6.28), "hunting", "", 8)
# Scattered barns/sheds (avoid POIs and the mountain)
def clear_of_pois(x, z, margin):
    if math.hypot(x, z) < 420: return False
    px=int(x+HALF); pz=int(z+HALF)
    if water_influence[pz,px] > 0.01 or h[pz,px] > 105.0: return False
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

# Roads: authored junctions form an irregular valley highway, with curved local approaches.
roads = []
ring_anchors = [[450,0],[495,150],[595,280],[598,447],[680,530],
                [655,585],[655,640],[655,737],[655,790],[470,805],[170,770],
                [-130,735],[-560,630],[-720,440],[-705,345],[-700,260],
                [-700,224],[-700,142],[-700,105],[-700,-40],[-640,-300],
                [-420,-460],[-165,-545],[175,-600],[420,-580],[600,-480],[605,-230]]
ring = smooth_path(ring_anchors, closed=True)
roads.append({"id":"ring","type":"asphalt","width":8,"points":ring})
def road(id, anchors, width=6, kind="asphalt"):
    roads.append({"id":id,"type":kind,"width":width,"points":smooth_path(anchors)})
road("spoke_ashford",[[598,447],[550,447],[490,447],[440,447]])
road("spoke_cranmoor",[[-640,-300],[-600,-300],[-545,-300],[-480,-300]])
road("spoke_bumjick_farm",[[-560,630],[-580,593],[-590,556],[-568,522]],kind="dirt")
road("spoke_hollis_farm",[[420,-580],[448,-587],[470,-580],[480,-555]],kind="dirt")
road("spoke_rail_yard",[[-420,-460],[-475,-540],[-515,-628],[-575,-665],[-625,-680]])
road("spoke_gas_station",[[450,0],[425,-74],[373,-130],[340,-184],[315,-200]])
road("spoke_hilltop_cabins",[[600,-480],[641,-560],[630,-652],[650,-680],[675,-698],[715,-690],[746,-710]],5,"dirt")
# Interior distributors offer useful decisions instead of making every trip
# follow the full outside ring. The southern lane stays north of the river.
road("north_distributor",[[-480,-300],[-400,-370],[-175,-415],[85,-440],
                          [265,-395],[450,-300],[605,-230]],7)
road("riverbank_distributor",[[-700,105],[-560,85],[-460,100],[-365,180],
                              [-230,240],[-80,290],[70,330],[230,380],[390,410],[440,447]],7)
road("frostmere_lodge_access",[[-700,-40],[-730,-57],[-773,-60],[-806,-45],[-806,-7]],5)
road("riverside_mill_loop",[[-568,522],[-485,560],[-405,582],[-341,575],
                           [-285,568],[-200,600],[-130,735]],5,"dirt")
road("riverside_mill_access",[[-341,575],[-341,553],[-341,538]],5,"dirt")
road("north_radar_access",[[175,-600],[92,-605],[10,-650],[20,-715],[85,-719]],5,"dirt")
road("east_ranger_loop",[[495,150],[620,100],[690,70],[720,48],[767,70],
                        [795,150],[770,260],[595,280]],5,"dirt")
# Broad traverses and actual reversing hairpins climb the north face; the old
# concentric 1.75-turn spiral is deliberately replaced with an authored lane.
road("mountain_switchback",[[-400,-370],[-330,-325],[-250,-315],[-120,-355],
     [25,-350],[155,-310],[200,-270],[170,-235],[75,-255],[-50,-265],[-155,-245],
     [-220,-185],[-235,-130],[-200,-100],[-165,-155],[-65,-200],[45,-200],
     [115,-165],[140,-120],[110,-95],[45,-135],[-45,-140],[-100,-105],[-115,-60],
     [-75,-40],[-35,-75],[30,-85],[65,-40],[45,-10],[15,-18]],5,"dirt")
# A shorter, steeper southern path reconnects with the upper service road. This
# second approach keeps the summit tactically accessible from both river towns.
road("summit_south_trail",[[230,380],[315,290],[360,175],[350,90],[295,45],
     [220,105],[180,185],[95,240],[-5,240],[-85,190],[-95,120],[-110,60],[-75,-40]],3.5,"dirt")
# Follow the west side through the yard; turn south of town toward the valley edge.
road("rail_line",[[-600,-840],[-600,-780],[-600,-720],[-600,-640],[-600,-580],[-605,-510],[-690,-420],[-740,-260],[-705,-50],[-655,95],[-575,180],[-480,380],[-410,595],[-500,715],[-575,750],[-665,760]],4,"rail")
road("ashford_main",[[440,447],[520,447],[598,447]])
road("ashford_cross",[[440,413],[520,413],[598,413]])
road("ashford_west",[[440,413],[440,447]])
road("ashford_east",[[598,413],[598,447]])
road("ashford_north",[[440,413],[447,363],[500,363],[548,363],[598,363],[598,413]])
road("ashford_market_lane",[[440,447],[440,497],[474,497],[520,497],[570,497],[598,497],[598,447]])
road("ashford_square_east",[[598,413],[619,413],[619,447],[598,447]],5)
road("cranmoor_main",[[-640,-300],[-560,-300],[-480,-300]])
road("cranmoor_motel_court",[[-610,-300],[-610,-274],[-594,-261],[-560,-261],[-517,-261],[-510,-280],[-510,-300]],5)
bridges = [
    {"id":"frostmere_bridge","name":"Frostmere Crossing","ax":-700.0,"az":142.0,
     "bx":-700.0,"bz":224.0,"width":9.0,"deckY":22.0,"thickness":0.7},
    {"id":"stillwater_bridge","name":"Stillwater Crossing","ax":655.0,"az":640.0,
     "bx":655.0,"bz":737.0,"width":9.0,"deckY":22.0,"thickness":0.7},
]

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
dirt_mask = np.zeros((N, N), dtype=np.float32)
rail_mask = np.zeros((N, N), dtype=np.float32)
bed_distance=np.full((N,N),np.inf,dtype=np.float32)
bed_height=np.zeros((N,N),dtype=np.float32)
pad_core=np.zeros((N,N),dtype=np.float32)
district_ids={p["id"] for p in pois}
for pad in pads:
    distance=np.hypot(X-pad["x"],Z-pad["z"])
    # Individual 18 m clearings include substantial verge beyond each small
    # footprint. Keep that verge available for nearby road grading.
    protected=pad["r"] if pad["id"] in district_ids else max(6.0,pad["r"]-4.0)
    # End the protection INSIDE the road profile's fixed pad-control boundary
    # (r-1); extending it beyond that boundary introduces a step on exiting lanes.
    np.maximum(pad_core,1.0-smoothstep(protected-3.0,protected-1.0,distance),out=pad_core)

def bridge_footprint(x,z,bridge,margin=0.0):
    dx=bridge["bx"]-bridge["ax"]; dz=bridge["bz"]-bridge["az"]
    length=math.hypot(dx,dz)
    t=((x-bridge["ax"])*dx+(z-bridge["az"])*dz)/(length*length)
    side=np.abs((x-bridge["ax"])*dz-(z-bridge["az"])*dx)/length
    return (t>=-margin/length)&(t<=1.0+margin/length)&(side<=bridge["width"]/2.0+margin)

def traversable_heights(x,z):
    heights=sample(h,x,z)
    for bridge in bridges:
        on_bridge=bridge_footprint(x,z,bridge)
        heights=np.where(on_bridge,np.maximum(heights,bridge["deckY"]),heights)
    return heights
def paint_segment(p, q, width, mask, height0, height1, is_dirt=False):
    x0, z0 = p; x1, z1 = q
    hw = width / 2 + 24.0
    minx = int(max(min(x0, x1) - hw - 1 + HALF, 0)); maxx = int(min(max(x0, x1) + hw + 1 + HALF, N - 1))
    minz = int(max(min(z0, z1) - hw - 1 + HALF, 0)); maxz = int(min(max(z0, z1) + hw + 1 + HALF, N - 1))
    if maxx <= minx or maxz <= minz: return
    sx = X[minz:maxz + 1, minx:maxx + 1]; sz = Z[minz:maxz + 1, minx:maxx + 1]
    dx, dz = x1 - x0, z1 - z0; L2 = max(dx * dx + dz * dz, 1e-6)
    t = np.clip(((sx - x0) * dx + (sz - z0) * dz) / L2, 0, 1)
    nx = x0 + t * dx; nz = z0 + t * dz
    d = np.sqrt((sx - nx) ** 2 + (sz - nz) ** 2)
    target = height0*(1.0-t)+height1*t
    # Choose the nearest segment, then apply this road once. Repeatedly blending
    # every segment's rounded end cap would pull a flat ice crossing uphill from
    # the following bank, even with a correctly limited longitudinal profile.
    dist_sub=bed_distance[minz:maxz+1,minx:maxx+1]
    target_sub=bed_height[minz:maxz+1,minx:maxx+1]
    nearer=d<dist_sub
    target_sub[nearer]=target[nearer]
    dist_sub[nearer]=d[nearer]
    mask[minz:maxz + 1, minx:maxx + 1] = np.maximum(mask[minz:maxz + 1, minx:maxx + 1], 1.0 - smoothstep(width / 2 - 0.5, width / 2 + 1.0, d))
    strip=1.0-smoothstep(width/2-0.5,width/2+1.0,d)
    ds=dirt_mask[minz:maxz+1,minx:maxx+1]
    if is_dirt: np.maximum(ds,strip,out=ds)
    else: ds*=1.0-strip
def graded_profile(road):
    """Lipschitz-constrained road bed, preserving authored pads, frozen water and junctions."""
    ps=np.asarray(road["points"],dtype=float)
    raw=traversable_heights(ps[:,0],ps[:,1])
    lengths=np.linalg.norm(np.diff(ps,axis=0),axis=1)
    # Leave a small interpolation allowance so the final one-metre height field
    # stays below 10% rail / 22% valley road / 25% summit-road grades as well.
    grade=0.095 if road["type"]=="rail" else (0.29 if road["id"]=="summit_south_trail" else (0.23 if road["id"]=="mountain_switchback" else 0.20))
    fixed=np.zeros(len(ps),dtype=bool)
    for pad in pads:
        fixed |= np.hypot(ps[:,0]-pad["x"],ps[:,1]-pad["z"]) < pad["r"]-1.0
    fixed |= sample(ice_mask,ps[:,0],ps[:,1])>.97
    fixed |= sample(road_mask,ps[:,0],ps[:,1])>.3
    for bridge in bridges:
        fixed |= bridge_footprint(ps[:,0],ps[:,1],bridge)
    fixed[0]=True; fixed[-1]=True
    heights=np.convolve(np.pad(raw,4,mode="edge"),np.ones(9)/9.0,mode="valid")
    heights[fixed]=raw[fixed]
    # First obtain the feasible interval from ALL fixed controls. This prevents
    # clipping passes from leaving spikes immediately before a locked village pad.
    dist=np.concatenate([[0.0],np.cumsum(lengths)])
    low=np.full(len(ps),-np.inf); high=np.full(len(ps),np.inf)
    for j in np.flatnonzero(fixed):
        reach=np.abs(dist-dist[j])*grade
        low=np.maximum(low,raw[j]-reach); high=np.minimum(high,raw[j]+reach)
    if np.any(low>high+0.05):
        # Preserve ground anchors and expose infeasible designs in the validation
        # stats; do not silently lift an entire town or frozen lake to hide one.
        print("ROAD ANCHOR WARNING:",road["id"],"max infeasibility",round(float(np.max(low-high)),3))
        anchors=np.flatnonzero(fixed)
        for a,b in zip(anchors[:-1],anchors[1:]):
            g=abs(raw[b]-raw[a])/max(dist[b]-dist[a],0.01)
            if g>grade+0.02: print("  fixed conflict",ps[a].tolist(),round(float(raw[a]),2),ps[b].tolist(),round(float(raw[b]),2),"grade",round(float(g),3))
    heights=np.clip(heights,np.minimum(low,high),np.maximum(low,high))
    heights[fixed]=raw[fixed]
    for _ in range(18):
        for i in range(1,len(heights)):
            if not fixed[i]: heights[i]=np.clip(heights[i],heights[i-1]-grade*lengths[i-1],heights[i-1]+grade*lengths[i-1])
        for i in range(len(heights)-2,-1,-1):
            if not fixed[i]: heights[i]=np.clip(heights[i],heights[i+1]-grade*lengths[i],heights[i+1]+grade*lengths[i])
    return heights

for road in roads:
    pts=road["points"]; profile=graded_profile(road)
    road["profileHeightsM"]=[round(float(y),3) for y in profile]
    prior_beds=np.maximum(road_mask,rail_mask).copy()
    bed_distance.fill(np.inf); bed_height.fill(0.0)
    for i,(a,b) in enumerate(zip(pts[:-1],pts[1:])):
        paint_segment(a,b,road["width"],rail_mask if road["type"]=="rail" else road_mask,profile[i],profile[i+1],road["type"]=="dirt")
    blend=1.0-smoothstep(road["width"]/2.0,road["width"]/2.0+24.0,bed_distance)
    # A new road's wide embankment must not tilt previously graded lanes nearby.
    # Exact intersections already inherit the existing lane as fixed controls.
    blend*=1.0-smoothstep(0.25,0.75,prior_beds)
    # Runtime buildings inherit their district or individual pad's recorded Y.
    # Preserve its flat core even when an adjacent road's wide shoulder reaches
    # under a building from outside the pad; road centres already lock to pads.
    blend*=1.0-pad_core
    bed_height=np.where(ice_mask>.90,ice_height,bed_height)
    h=h*(1.0-blend)+bed_height*blend
# The last few centimetres of anti-aliased mask transitions still belong to the
# frozen heightfield itself, and must not acquire camber from a road crossing.
h=np.where(ice_mask>.99,ice_height,h)
for bridge in bridges:
    # The authored deck is a native collidable bridge in the game. Leave frozen
    # river terrain at 18 m under its 22 m deck, and suppress a duplicate road.
    deck=bridge_footprint(X,Z,bridge)
    h[deck]=np.minimum(h[deck],bridge["deckY"]-0.20)
    road_mask[deck]=0.0

# ---------------------------------------------------------------- winter colour map and independent surface semantics
snow = np.array([0.91,0.95,0.97]); drift = np.array([0.79,0.85,0.91])
rock = np.array([0.39,0.43,0.48]); asphalt=np.array([0.27,0.31,0.36])
gravel=np.array([0.49,0.51,0.54]); ice=np.array([0.49,0.69,0.79])
var = 0.5 + 0.5 * fbm(32, 3, rng)
gy,gx=np.gradient(h)
slope=np.hypot(gx,gy)
col=snow[None,None,:]*(1-var[...,None]*0.58)+drift[None,None,:]*(var[...,None]*0.58)
rockness=smoothstep(0.65,1.5,slope)*(0.75+var*0.25)
col=col*(1-rockness[...,None])+rock[None,None,:]*rockness[...,None]
col = col * (1 - road_mask[..., None]) + asphalt[None, None, :] * road_mask[..., None]
col = col * (1 - dirt_mask[..., None]) + np.array([0.48,0.43,0.36])[None,None,:] * dirt_mask[...,None]
col = col * (1 - rail_mask[..., None]) + gravel[None, None, :] * rail_mask[..., None]
# Packed crossing tracks remain on the same collidable ice, avoiding raised road dams.
ice_col=ice[None,None,:]*(0.95+var[...,None]*0.12)
ice_col=ice_col*(1.0-road_mask[...,None]*0.2)+snow[None,None,:]*road_mask[...,None]*0.2
col=col*(1.0-ice_mask[...,None])+ice_col*ice_mask[...,None]
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
surface_mask=np.stack([road_mask,rail_mask,ice_mask],axis=-1)
write_png(os.path.join(OUT,"surface_mask_2km.png"),(np.clip(surface_mask,0,1)*255).astype(np.uint8))

# preview: hillshade over colour, 1024 px
shade = np.clip(0.86 + 0.32 * (-gx * 0.6 + gy * 0.8) / (1 + np.sqrt(gx ** 2 + gy ** 2)), 0.45, 1.0)
prev = np.clip(col * shade[..., None], 0, 1)[::2, ::2]

# ---------------------------------------------------------------- trees
forest = fbm(6, 3, np.random.default_rng(SEED + 7))
trees = []
slope = np.sqrt(gx ** 2 + gy ** 2)
def blocked(x, z):
    px = int(x + HALF); pz = int(z + HALF)
    if road_mask[pz, px] > 0.025 or rail_mask[pz, px] > 0.025: return True
    if ice_mask[pz,px] > 0.01 or water_influence[pz,px] > 0.3: return True
    if h[pz, px] > 175 or slope[pz, px] > 0.7: return True
    for p in pads:
        if math.hypot(x - p["x"], z - p["z"]) < p["r"] + 6: return True
    return False
b_xz = np.array([[b["x"], b["z"]] for b in buildings])
cand = rng.uniform(-1010, 1010, (105000, 2))
for x, z in cand:
    px = int(x + HALF); pz = int(z + HALF)
    f = forest[pz, px]
    dense = f > 0.035
    chance = 0.62 if dense else 0.042
    if h[pz,px]>120: chance *= 0.22
    keep = rng.random() < chance
    if not keep: continue
    if blocked(x, z): continue
    if np.min(np.hypot(b_xz[:, 0] - x, b_xz[:, 1] - z)) < 18: continue
    hh = float(h[pz, px])
    species = ["tree_pineTallA", "tree_pineDefaultA", "tree_pineRoundA"][int(rng.integers(3))]
    trees.append([round(float(x), 1), round(float(z), 1), species, round(float(rng.uniform(0.78, 1.3)), 2), round(float(rng.uniform(0, 6.283)), 2)])
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
# Each tree owns a trunk body. Keep room under Jolt's 10,240-body configuration
# for buildings, props, players and vehicles, using a separate seeded sampler so
# thinning cannot perturb placement, roads, or the shape of forest clusters.
if len(trees)>8200:
    selected=np.random.default_rng(SEED+81).choice(len(trees),size=8200,replace=False)
    trees=[trees[i] for i in sorted(selected.tolist())]

# A readable terrain overview with forest masses and building footprints, without UI labels.
for x,z,species,scale,yaw in trees:
    px=int((x+HALF)/2); pz=int((z+HALF)/2)
    colour=np.array([0.29,0.40,0.42]) if species=="tree_pineTallA" else np.array([0.38,0.49,0.50])
    prev[max(0,pz-1):min(1024,pz+2),px]=colour
    prev[pz,max(0,px-1):min(1024,px+2)]=colour
    prev[max(0,pz-1),px]=[0.67,0.76,0.79]
for b in buildings:
    px=int((b["x"]+HALF)/2); pz=int((b["z"]+HALF)/2)
    wide=4 if b["prefab"] in ["warehouse","quat_bigbarn","church"] else 2
    prev[max(0,pz-3):min(1024,pz+4),max(0,px-wide):min(1024,px+wide+1)]=[0.34,0.34,0.36]
    prev[max(0,pz-2):min(1024,pz+2),max(0,px-wide+1):min(1024,px+wide)]=[0.87,0.90,0.91]
write_png(os.path.join(OUT,"preview_2km.png"),(prev*255).astype(np.uint8))

# ---------------------------------------------------------------- write outputs
h32 = h.astype(np.float32)
h32.tofile(os.path.join(OUT, "heightmap_2km.f32"))
json.dump({"pads": pads, "min": float(h.min()), "max": float(h.max())}, open(os.path.join(OUT, "pads_2km.json"), "w"))
json.dump({"count": len(trees), "trees": trees}, open(os.path.join(OUT, "trees_2km.json"), "w"), separators=(",", ":"))
layout = {
    "id": "slice_2km", "seed": SEED, "halfSizeM": HALF, "vertexSpacing": 1.0, "regionSize": 512,
    "heightmap": "res://world/terrain/heightmap_2km.res", "heightmapExr": "res://world/terrain/heightmap_2km.exr",
    "colormap": "res://world/terrain/colormap_2km.png", "preview": "res://world/terrain/preview_2km.png",
    "surfaceMask":"res://world/terrain/surface_mask_2km.png",
    "trees": "res://world/terrain/trees_2km.json", "pads": "res://world/terrain/pads_2km.json",
    "north": "-z", "pois": pois, "buildings": buildings, "roads": roads,
    "bridges":bridges,
    "spawnMaxHeightM": 110,
    "theme":"winter_valley_v2",
    "water":{"frozen":True,"heightM":ice_height,"surface":"heightfield","maskChannel":"blue",
             "river":{"id":"frost_river","name":"Frost River","points":river_points,"widthM":[22,32]},"lakes":lakes},
}
os.makedirs(os.path.join(ROOT, "design", "map"), exist_ok=True)
json.dump(layout, open(os.path.join(ROOT, "design", "map", "slice_2km.json"), "w"), indent=1)
road_grades={}
for r in roads:
    ps=np.array(r["points"]); ys=traversable_heights(ps[:,0],ps[:,1]); lengths=np.linalg.norm(np.diff(ps,axis=0),axis=1)
    grades=np.abs(np.diff(ys))/np.maximum(lengths,0.01)
    road_grades[r["id"]]={"max":round(float(np.max(grades)),3),"p95":round(float(np.percentile(grades,95)),3)}
stats={"seed":SEED,"resolution":N,"minHeightM":float(h.min()),"maxHeightM":float(h.max()),
       "meanHeightM":float(h.mean()),"summitHeightM":float(h[HALF,HALF]),"buildings":len(buildings),
       "roads":len(roads),"trees":len(trees),"pads":len(pads),"iceAreaM2":int(np.count_nonzero(ice_mask>.5)),
       "bridges":len(bridges),"pointsOfInterest":len(pois),
       "lowlandFraction":float(np.mean(h<80)),"snowFraction":float(np.mean((rockness<.25)&(road_mask<.2)&(rail_mask<.2)&(ice_mask<.2))),
       "roadGrades":road_grades,"surfaceMaskChannels":{"R":"road","G":"rail","B":"frozen water"},
       "iceHeightRangeM":[float(h[ice_mask>.99].min()),float(h[ice_mask>.99].max())]}
pad_errors=[abs(float(sample(h,np.array([p["x"]]),np.array([p["z"]]))[0])-p["height"]) for p in pads]
stats["maxPadCenterErrorM"]=float(max(pad_errors))
# Match MapLayout.building_base_height() and the runtime's block-averaged 2 m
# HeightField, which uses bilinear queries. Pad-centre checks alone miss buildings
# away from the centre whose terrain was displaced by a neighbouring shoulder.
runtime_h=h32.reshape(N//2,2,N//2,2).mean(axis=(1,3))
def runtime_height_at(x,z):
    px=np.clip((x+HALF)/2.0,0,N//2-1); pz=np.clip((z+HALF)/2.0,0,N//2-1)
    ix=int(math.floor(px)); iz=int(math.floor(pz))
    jx=min(ix+1,N//2-1); jz=min(iz+1,N//2-1); tx=px-ix; tz=pz-iz
    return float(runtime_h[iz,ix]*(1-tx)*(1-tz)+runtime_h[iz,jx]*tx*(1-tz)+
                 runtime_h[jz,ix]*(1-tx)*tz+runtime_h[jz,jx]*tx*tz)
building_errors=[]
for b in buildings:
    pad=next((p for p in pads if b["poi"] and p["id"]==b["poi"]),None)
    if pad is None:
        pad=next((p for p in pads if abs(p["x"]-b["x"])<1.5 and abs(p["z"]-b["z"])<1.5),None)
    base=pad["height"] if pad else runtime_height_at(b["x"],b["z"])
    error=abs(base-runtime_height_at(b["x"],b["z"]))
    building_errors.append({"prefab":b["prefab"],"x":b["x"],"z":b["z"],"errorM":round(error,4)})
stats["maxBuildingGroundErrorM"]=max(b["errorM"] for b in building_errors)
stats["worstBuildingGround"]=max(building_errors,key=lambda b:b["errorM"])
json.dump(stats,open(os.path.join(OUT,"winter_map_stats.json"),"w"),indent=2)
assert 5000<len(trees)<=8500, "forest density must respect both coverage and physics-body budget"
assert 150<h[HALF,HALF]<175, "central summit must preserve the existing finish"
assert np.isfinite(h).all(), "height field must be finite"
for r in roads:
    limit=0.115 if r["type"]=="rail" else (0.33 if r["id"]=="summit_south_trail" else (0.27 if r["id"]=="mountain_switchback" else 0.245))
    assert road_grades[r["id"]]["max"]<=limit, f"unsafe grade on {r['id']}: {road_grades[r['id']]}"
assert max(pad_errors)<0.4, "roads must not displace the building pad centres"
assert stats["maxBuildingGroundErrorM"]<0.6, f"runtime building ground mismatch: {stats['worstBuildingGround']}"
print(f"heights: min {h.min():.1f} max {h.max():.1f} mean {h.mean():.1f}")
print(f"buildings: {len(buildings)}  roads: {len(roads)}  trees: {len(trees)}  pads: {len(pads)}")
print(f"snow coverage {stats['snowFraction']:.1%}; lowland {stats['lowlandFraction']:.1%}; frozen water {stats['iceAreaM2']} m2")
print(f"ice height range {stats['iceHeightRangeM']}; summit road max grade {road_grades['mountain_switchback']['max']:.1%}")
for p in pads[:8]:
    print(f"  pad {p['id']:<16} h={p['height']}")
