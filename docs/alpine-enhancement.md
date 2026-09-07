# Alpine direction: first implementation pass

## What this change actually does

This is a gameplay and atmosphere pass on the existing Godot game, not a new HTML mock-up or a replacement for the terrain pipeline. The 2 km slice opts into `theme: whiteout`, `summitFinish: true`, and `endgameCenterM: [0, 0]`. The target matches the existing `the_mountain` POI in `design/map/slice_2km.json`.

- SummitZone inherits the existing zone timeline. Its early circles vary with the match seed, remain nested, keep the summit inside every circle, and end at the summit. Interpolated circles also remain nested. Other presets without the whiteout theme retain legacy gas behavior.
- The green gas curtain becomes an animated ice-coloured whiteout wall. Damage is labelled Whiteout in combat and the kill feed. Whole-second damage ticks catch up after a slow frame. Once the final radius reaches zero, the exact centre is no longer invulnerable.
- AlpineAtmosphere adds a red summit beacon, camera-local snow and exposure-driven depth fog. CPU snow is capped at 160 particles on Web and 320 otherwise. Presentation is skipped in headless runs. A short overhead ray at 5 Hz suppresses local snow under roofs; it does not make shelter immune to storm damage. This is a coarse shelter approximation, not per-flake collision.
- The combat HUD is extended rather than rebuilt: storm phase and mm:ss countdown, safe-zone distance, damage warning, icy screen edges, current POI, elevation and horizontal distance to the summit. The map receives a red summit marker. Existing green navigation cues remain in the inherited compass/map.
- The new scene nodes are owned by the current match world and are freed with it. The Environment is duplicated per match to avoid modifying the shared scene resource. Existing --env=nofog and --env=plain diagnostics suppress fog changes.

The original combat, loot, inventory, vehicles, character art, terrain collision grid, menu, and browser player cap are not replaced. This is not a 60-player networking implementation. Current spawn selection is still random parachute insertion; sector selection has not been added.

## Important gameplay distinction

This pass implements a shrinking horizontal circle directed toward the summit. It does **not** introduce a rising altitude damage plane. Players can remain safe at low elevation if they are inside the current circle; altitude by itself does not protect a player outside it. Do not advertise an elevation-only storm until an altitude model, its HUD and bot escape logic have been implemented and playtested together.

The configured summit must fit inside the first circle and the playable bounds. An out-of-bounds target falls back to legacy random circle selection. Changing the map requires updating this target. Endgame reachability, climb routes and bot navigation need a full playtest before release; mathematical containment alone cannot guarantee that a route over real terrain is walkable.

## Verification

The existing `tools/ci/test.sh` discovers the new tests automatically. They cover seeded repeatability, 1,000 circle chains, map containment, nested circles, monotonic centre movement, offset summits, equal-radius and boundary fallbacks, timeline completion, exposure, legacy gas behavior, wall configuration and damage catch-up.

Run:

```sh
tools/ci/test.sh
# Focused suite:
tools/ci/test.sh -- --filter=summit
# Deterministic no-player simulation:
scratch/godot/Godot_v4.6.3-stable_linux.x86_64 --headless --fixed-fps 60 --path . res://game/main/main.tscn -- --sim --seed=7 --bots=30 --sim-seconds=420 --no-player
```

Before merging/re-exporting, also play in the desktop Compatibility renderer and a real browser: watch clear-to-storm transitions, enter/exit buildings, open the map, scope a rifle, finish a match and restart. Verify snow/fog cost, HUD fit at 1280x720 and 1920x1080, the final ascent's walkable routes and legacy preset behavior. Headless tests do not validate shader appearance or browser frame rate.

## Next world-art pass, using the supplied screenshots

The target is a bright alpine combat world, not a uniformly grey snowfield: strong blue sky, cool shadowed snow, warm timber buildings, industrial metal, readable silhouettes and a red summit signal. Keep original KOTM assets and branding; use H1Z1 as a handling/UI reference, not as an asset source.

Prioritise a playable route with one polished location at a time:

1. Lake resort at the lower edge: waterfront cabins, a lodge, parking and a clear uphill escape route.
2. Ski resort above the villages: a substantial red/timber lodge, lift stations, ski runs and overlapping cover. Functional cable transport requires a separate mechanic and collision review.
3. Mines at several elevations: one main industrial entrance, lift towers and connected routes through the mountain. Tunnel geometry must be built deliberately; it is not achieved by renaming a farm POI.
4. Radar station high on a ridge, distinct from the summit: dishes, utility buildings and long-range sightlines with approach cover.
5. Plane crash in lower forest: broken fuselage, scattered supplies and multiple exits. Decorative wreckage does not mean adding a transport plane to the insertion flow.
6. The Summit: the beacon, a recognisable structure, at least two viable approach routes and enough final-ring cover to avoid a single unbeatable firing position.

Support those with small villages, caravan camps and a warehouse yard containing forklifts, shelves and lootable interiors. Add snowmobiles as a real vehicle definition with acceleration, braking, slope behavior, collision and animation work, not a renamed car. Preserve the current heightmap/mesh/collider agreement when rebaking terrain.

Large environmental changes should be staged separately from server-authoritative multiplayer, movement/combat feel, and the main-menu redesign. Each pass needs its own measurable acceptance test rather than a claim that concept-art fidelity has already been achieved.
