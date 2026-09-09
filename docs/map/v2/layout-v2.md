# Winter valley — layout 02

The main `kotm-live` map now has a connected valley road network, distinct summit approaches and four additional destinations. This is the next layout pass on the 2.048 × 2.048 km playable slice.

## Explore

Run `RUN_SNOW_MAP.cmd` in the parent KOTM assets folder. The normal game's Play action uses the same terrain and layout.

- **M:** show or close the numbered layout plan.
- **1–5:** basin overview, Ashford church, Cranmoor street, frozen west lake, summit.
- **6–9:** Frostmere Lodge, Riverside Mill, North Radar, west river bridge.
- **WASD:** fly; **Q/E:** down/up; **Shift:** faster; hold the right mouse button to look.

The tour provides a free camera without starting a match. Its plan reads the actual terrain preview, roads, bridges and location data. Captures in `../captures/` are rendered in Godot, including `00-layout-plan.png`.

## Layout changes

- Replaced the spiral climb with northern hairpins and a separate, narrower southern summit trail. Both reach the existing summit objective.
- Added connections across the north valley and along the riverbank, reducing reliance on the perimeter loop.
- Added **Frostmere Lodge** beside the west lake, **Riverside Mill** in the southern valley, **North Radar** on a raised northern knoll, and **East Ranger Camp** below the eastern ridge.
- Expanded Ashford's streets and Cranmoor's motel court, with building footprints placed clear of travel lanes.
- Added two road bridges over the frozen river, with concrete piers, snow verges and open timber railings. Their decks and railings have matching collision; the frozen surface beneath remains part of the terrain.
- Broadened lake banks and gave dirt tracks a lighter, warmer surface than asphalt.

The slice contains **12 named locations, 111 buildings, 27 routes and 2 bridges**. The forest retains the 8,200-tree cap. The summit stays at 160 m and frozen water at 18 m. The southern summit trail is steeper than the northern road and is intended as an alternative approach on foot.

## Validation

**28 focused Godot tests passed** across world construction, terrain, winter surfaces, spawning, summit behavior, bridges and route clearance. The full world was checked at **1,032 road positions** with a 1.8 m diameter capsule: no fixed scenery blocked a sampled lane center. Bridge checks cover deck and approach joins, rail openings, frozen ground and underpass clearance. Scenery placement now leaves road edges clear, including farm entrances, and parked vehicles avoid bridge spans.

The planar footprint audit found one connected network of 26 non-rail routes, no building-to-road or building-to-building overlaps, and access within 62.3 m of every named location. [The audit report](layout-audit.json) records its method and limits: footprint metadata approximates building bounds; it does not include roof overhangs. The separate Godot lane checks use actual collision shapes.

Maximum grades are **20.4%** on the valley loop, **23.3%** on the northern summit ascent, **29.2%** on the southern trail, and **9.6%** on the rail bed. These are rise/run percentages. Building bases match the runtime terrain within **0.005 m**. A ten-second headless startup with seed 7 and three bots returned `ok: true`; this checks loading and startup, not a completed match or vehicle traversal.

## Rebuild

Run Python with NumPy, followed by Godot 4.6.3:

```text
python tools/bake_map.py
godot --headless --path . --script res://tools/godot/bake_terrain.gd
godot --headless --path . --editor --import --quit
python tools/audit_map_layout.py
```

The deterministic generator writes `world/terrain/winter_map_stats.json` with elevation, road-grade and building-grounding measurements. Bridges are authored in `design/map/slice_2km.json` and built by `game/world/map_landmarks.gd`.

For actual scene captures:

```text
godot --path . --rendering-method gl_compatibility --fixed-fps 60 --resolution 1600x900 --script res://tools/godot/capture_snow_map.gd
```

Add `-- --view=9` to capture only the west bridge. This layout pass uses the existing simple asset kit. Detailed environment art and human driving/combat playtests remain further work; no web deployment is included.

The previous generator, terrain, layout and screenshots are preserved in the parent workspace under `output/map-v2/original`.
