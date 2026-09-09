# KOTM snow valley — first playable map pass

This is the historical first-pass record. See [layout 02](v2/layout-v2.md) for the current playable map, bridge structures, additional destinations and review controls. The shared `captures/` folder shows the current version.

This pass turns the existing 2.048 × 2.048 km test slice into a winter basin inspired by the supplied landscape and settlement references. The playable terrain is in `kotm-live`; the 8 km world remains a longer-term design target.

## Open the map

Run `RUN_SNOW_MAP.cmd` from the parent KOTM assets folder to open the map review scene.

- **1–5:** basin overview, Ashford church, Cranmoor street, frozen west lake, summit.
- **WASD:** fly; **Q/E:** down/up; **Shift:** faster.
- **Hold right mouse:** look; **Esc:** release the mouse.

The normal game's Play action also loads the revised terrain. The tour provides a camera for inspection and does not run a match. The overhead view extends foliage visibility and disables distance fog so the whole forest distribution can be reviewed.

## Implemented

- Broad low valleys framed by an irregular mountain perimeter; the central summit objective remains at `(0, 0)`.
- A winding road loop, settlement connections and an uphill route, with snow shoulders and exposed asphalt.
- A winding frozen river between two lakes. Ice is part of the same heightfield as the ground, so rendering, height queries and collision agree.
- Clustered pine forests with snowy upper branches and dark evergreen undersides; clearings around buildings and routes.
- Existing farms, industrial buildings, homes and loot interiors. Pitched snowy roofs distinguish homes and cabins, and a bell tower makes Ashford's church easier to identify.
- A winter map preview and explicit surface masks: red = roads, green = rail bed, blue = frozen water.
- A separate tour scene and script that captures actual Godot views.

The final bake contains **84 buildings, 15 roads, 8,200 pine trees and 37 building pads**. The summit remains at 160 m; perimeter peaks reach 255 m. Frozen water covers about 90,538 m². Road grades were checked against the baked heightfield: maximum 23.7% on the valley loop, 23.8% on the summit approach and 9.6% on the rail bed. Grades are rise/run percentages, not degrees. Roads and vehicle handling still need human playtesting; these measurements are not a vehicle traversal test.

Trees are capped below the physics body's capacity, and the slice spawns at most 16 vehicles. Existing terrain triangle winding was corrected so upward snow surfaces receive light from above. Roof triangle winding and added roof collision were also verified. Winter lighting uses a cool sky and lower exposure to retain snow detail.

## Validation

Godot 4.6.3: **24 focused tests passed** across world construction/grounding, heightfield, snow/ice collision, surface exclusions, spawning and summit behavior. The maximum baked building-base error after 2 m terrain averaging is 0.126 m. A 10-second headless match startup with seed 7 and three bots completed with `ok: true`; it validates loading and match startup, not a completed match or player traversal.

Five real Compatibility-renderer captures are saved in `captures/`. Final rendering completed with no shader or physics-capacity errors. These views show the current simple art assets. A full browser export, multiplayer load test and final-circle driving/walking playtest were not part of this first map pass.

## Art direction and remaining work

`snow-map-concept-v1.png` is generated concept art showing the intended finish; it is **not** an in-game screenshot. It was made with the built-in image generation tool using the supplied images as visual references. The full final prompt is saved in `concept-prompt-v1.txt`.

The current playable pass uses the project's existing simple asset kit. Detailed brick houses, a bespoke timber church, realistic conifers, power lines, bridge structures, richer rocks and ground textures are still future art work. The river is solid ice throughout; there is no swimming, breakable ice, or new traction mechanic. Road crossings currently cross on frozen ground; they are not finished bridges.

## Rebuild

From this project, run Python with NumPy installed:

```text
python tools/bake_map.py
godot --headless --path . --script res://tools/godot/bake_terrain.gd
godot --headless --path . --editor --import --quit
```

The generator uses seed `20160218` and accepts `--project /path/to/project`. It writes the heightfield, preview, colour map, surface mask, tree placements, building pads, road layout and `world/terrain/winter_map_stats.json`.

To capture the actual scene with a graphics driver:

```text
godot --path . --rendering-method gl_compatibility --fixed-fps 60 --resolution 1600x900 --script res://tools/godot/capture_snow_map.gd
```

Before this rebake, the original map generator, layout and terrain files were copied to the parent workspace's `output/map-v1/original` folder.
