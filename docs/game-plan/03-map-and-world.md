# 03 – Map & World

## Size and shape

- **8 km × 8 km** playable square (64 km²), matching the original Z1/Pleasant Valley map.
- Beyond the border: toxic gas wall from the start (same visual as ring gas).
- Terrain: rolling rural valley, a central mountain massif, one large lake with a dam, a river that
  splits the map north/south with 4 bridges, coastline on the east edge, and mountains on the west/north
  edges (like the airfield lobby backdrop).

## Biomes

| Biome | Coverage | Purpose |
|---|---|---|
| Rural fields & farms | 40% | Long sightlines, hedgerows, barns, silos; vehicle-friendly |
| Deciduous forest | 25% | Cover, fewer buildings, good for sneaking; the lampposts-and-trees road look of screenshot 1 |
| Towns & suburbs | 15% | Dense loot, house-to-house fights, wooden fences |
| Industrial / city core | 8% | Multi-storey buildings, warehouse loot, brick apartments (screenshot 1 background) |
| Mountain & alpine | 8% | Rock, snow, radio tower, dam; verticality for late circles |
| Water & shoreline | 4% | Lake, river, coast; swimming, boats not in scope |

## Points of interest (POIs)

The layout deliberately mirrors the original's rhythm: one large city, a handful of towns, farms
everywhere, industrial pockets, and a memorable centre.

| POI | Type | Loot tier | Notes |
|---|---|---|---|
| **Pleasant Ridge** (city) | City core, 6×6 blocks | High | Brick apartments, police station, hospital, gas station, water tower. The screenshot 1 skyline |
| **The Mountain** | Alpine | Medium | Central peak, radio tower on top, single switchback road, dam on its south face |
| **Millbrook Dam** | Industrial | High | Powerhouse building, catwalks, control room |
| **Ashford** | Town | Medium-High | Grid-street suburb with a school and church |
| **Cranmoor** | Town | Medium | Small town with a diner and motel |
| **Ranchito** | Village | Medium | Mexican-restaurant-and-market strip, trailer park |
| **Bumjick Farm** | Farm | Low-Medium | Large barn cluster; the archetype farm |
| **Airfield Base** | Military | High | Hangars, control tower, helicopter pads; also the pre-match lobby location |
| **Hilltop Cabins** | Cabins | Low | Log cabins scattered in the forest |
| **Riverside Mill** | Industrial | Medium | Sawmill on the river |
| **Bayview** | Coastal town | Medium | Fishing town on the east coast, piers |
| **Quarry** | Industrial | Medium | Open pit, ramps, great for vehicle jumps |
| **Rail Yard** | Industrial | Medium | Railway line runs the map north–south; freight cars as cover |
| **Woodland Church**, gas stations, barns, hunting stands | Minor | Low | ~250 minor structures scattered on roads |

Total building count target: **~1,800 enterable structures**. Every structure is enterable; no
locked doors. Doors open/close (used for sound cues) and can be shot through (wood).

## Roads and vehicle flow

- One paved highway loop, two paved cross-roads, and a dense dirt-road network. Every POI is
  reachable by road.
- Roads have lampposts, benches, road signs, guard rails, and wrecked cars as cover (screenshot 1).
- Bridges are choke points; each has a small hut and a vehicle wreck.

## Loot density

- Loot spawns in fixed **loot nodes** inside and around buildings (floors, tables, shelves, vehicle
  trunks). Each node rolls from a loot table (see `design/data/loot-tables.json`) at match start.
- Target on-map counts at match start **(tune)**: ~2,200 weapons, ~650 helmets, ~350 laminated
  armor, ~600 backpacks, ~4,500 ammo stacks, ~1,600 medical items, ~40 vehicles.
- Loot is visible from a distance as a small glow-less physical item on the ground (no beams). Pick up
  with F, or hold F on a pile for the loot list.

## Environment and lighting

- Fixed time of day at match start, chosen from a small set: **noon** (default 70%), late afternoon
  (20%), overcast (10%). No night, no fog-outs. Clear readability first.
- Weather: cloud shadows only. No rain at launch.
- Foliage: grass renders out to 100 m for everyone (server-enforced setting; no "low grass" advantage).
  Trees cast shadows; bushes provide visual cover only, no collision with bullets.
- Destructibility: wooden fences, windows (glass), and wooden doors can be shot/punched through.
  Buildings are static.

## Streaming & performance

- World partitioned into 500 m cells with HLOD for distant buildings and terrain LODs.
- Target 60 FPS at 1080p medium on GTX 1060 with 150 players in the lobby.
