# 13 – Roadmap & Milestones

Durations assume a core team of ~14 (see below). Adjust proportionally.

## Milestone 1 (Godot port) – status

Built on branch `claude/h1z1-style-game-plan-7kzer5`: project skeleton and headless test runner,
pure combat core with TTK parity tests, baked 2 x 2 km slice (heightmap, layout, trees), World with
a chunked mesh terrain (the Terrain3D add-on was tried and later removed), shared character body with motor/camera/input, random-point parachute
spawns and match flow, bone-driven hitboxes and visuals, weapons/projectiles/tracers/hit effects,
seeded loot with pickups and death bags, the gas zone, the HUD, the bot AI, kit-assembled building
prefabs with props and trees, the cosmetic skin system, placeholder audio, and a web export served
from `gh-pages`.

Second pass (feel and presentation): snappy movement (linear accel/decel, air momentum, jump
buffer + coyote time, same-tick input, physics interpolation), muzzle-accurate shooting (auto-fitted
gun models with a Muzzle marker, aim-tracking mount, flash), a two-hand IK armed pose with torso
twist, the body suit split into shirt/pants/shoes so clothes read, a procedural terrain material
(grass, dirt roads, gravel rail bed, rock, snow), warmer lighting with ACES, hotbar tiles that render
the gun model with mag/reserve, the full menu set (main with live character preview, Customize,
Settings, Pause, End), building prefabs merged to one mesh each (4284 -> 84 instances), and a
distance-based animation LOD for bots.

Third pass (playability on the web): terrain now draws on the WebGL renderer (depth fog instead of
exponential fog, chunked 128 m tiles, vertex colours baked into tree albedo), a procedural crouch
pose (leg IK, feet planted), a human character (head and hands split by skin bones, skin tones,
hair styles, procedural face), helmet ding and death grunt, shotgun re-tuned (tighter spread,
longer reach, distance falloff), loot laid out in rings with ammo beside each gun, drivable cars
parked along roads, and the Z1BR-style front end: side-panel main menu with wallet and dailies,
Customize item grid with rarity bars and locked items, Marketplace with crates and a reel-style
opening, local leaderboard. Web physics runs at 30 Hz with 20 bots.

Fourth pass (studio assets and the snow biome): the Terrain3D add-on is gone; the terrain is our
own chunked mesh with a snow-biome shader (wind-drift snow, packed-snow and mud roads, rock on
slopes, thaw patches in low ground) under a low winter sun and spruce-green trees. The studio's
Blender files are converted headless with Blender's Python module (`tools/blender/convert_blends.py`,
sockets exported to `assets/models/sockets.json`) and merged into single meshes by `ModelLib`: the
AR75 carbine is the AR-15 in hand, on the hotbar and on the ground; the motorcycle helmet and the
military backpack attach to the head and back and lie on the ground as loot; the snow truck and
the snowmobile replace the car-kit vehicles. Loot is laid out on a jittered grid across the whole
map (640 scatter groups plus the building nodes).

Fifth pass (movement feel and fair fights): terrain collision, the gameplay height query and the
drawn mesh all read the same 2 m grid, so the ground can no longer be invisible or swallow a
running player. An admin menu (F10) spawns and kills bots, hands out loadouts, toggles bullet
trails and god mode, spawns vehicles, teleports to POIs and scales time. Crouch became analytic:
the thighs swing forward, the calves fold back twice as far, the feet level out and the pelvis
drops by exactly the height the folded legs lose, so the legs can never flail. The armed pose was
re-tuned per weapon class and the IK now picks a deterministic axis for near-opposite rotations
and turns at most 150 degrees per step. The backpack hangs off the artist's socket against the
back. Parachuting hangs from the risers with the gun stowed, strafes with A/D and eases between
dive and flare instead of snapping. Recoil is roughly halved, the hit-assist sweep is gated behind
a proximity check so firing no longer stutters, every loot node rolls at least one item, and bots
fight for real: 190 m perception, per-class engagement ranges and 3-6 shot bursts with planted feet
took a 180 s 30-bot match from 0 kills to 15. Steep ground is climbable rather than a wall
(`floor_max_angle` 45.8 -> 55 degrees: at the old limit a character walking a 50 degree slope slid
80 m back down), military loot nodes guarantee a random rifle instead of the same hunting rifle
every time, and body armour is a fitted plate carrier instead of a box wider than the chest.
Three new tests measure these directly: a slope climb, the loot laid out on the real map (1674
items, 36 distinct, commonest 6.3%) and how worn gear sits on the body at rest and while armed
and crouched.

Backlog (M1.5): prone, navmesh bots that drive, doors, retargeted animations (walk/aim), host/join
multiplayer, Inventory screen with crafting, 3D item renders in the Customize grid, snow footprints
and drifts, the remaining weapons and clothing as studio models.

## Phase 0 – Pre-production (4 weeks)

- Lock this plan; art bible from the reference screenshots; block-out list of POIs.
- UE5 project skeleton, CI, dedicated server build, Git LFS, coding standards.
- Ballistics simulator (Python) producing TTK matrices from `weapons.json` to sanity-check tuning
  before any engine work.

**Exit**: repo builds a client and server; a bot can walk on a flat map.

## Phase 1 – Prototype "First Fight" (10 weeks)

- 2×2 km grey-box map with one town and a farm.
- Third-person movement with all stances, jump-shooting, first-person toggle.
- AR-15, M9, shotgun, fists with the projectile + tracer + drop model.
- Hitboxes, helmet pop, laminated armor durability, bleeding, bandage.
- Parachute spawn from random points (full rules of 02) for 20 players.
- Gas ring with 4 phases, `N REMAIN`, basic HUD, kill feed.
- Weight inventory with pickups and death bags.

**Exit**: 20 internal players complete a 12-minute match; hit feedback and gunplay feel is signed off.

## Phase 2 – Vertical Slice (12 weeks)

- Full arsenal, melee, throwables, bow + crafted arrows, crafting panel.
- Off-Roader and Police Car with Chaos vehicles, fuel, explosion.
- 4×4 km map section with final art quality for one town, one city block, the airfield lobby.
- Lobby/warmup flow, Solo/Duos with team panel and voice.
- Inventory, customize, main menu screens in final visual style.
- Airdrop tickets. Lag compensation. 60-player playtest.

**Exit**: a 60-player match that looks and feels like the reference screenshots.

## Phase 3 – Alpha (16 weeks)

- Full 8×8 km map, all POIs, ~1,800 buildings, the Mountain, the dam.
- Fives, pickup truck, ATV, all crafting, all medical items.
- Backend: auth, matchmaker, fleet, stats, leaderboards, missions, dailies.
- Easy Anti-Cheat integration; replay recording; report flow.
- 150-player load tests with bots; first external closed alpha (2 weekends).

**Exit**: 150-player matches at 30 Hz within the server budget; crash-free 8 h soak.

## Phase 4 – Beta (12 weeks)

- Balance passes from telemetry (TTK, spawn fairness, gas deaths, vehicle usage).
- Cosmetics pipeline, ~150 skins, crates, marketplace, seasons, rank tiers.
- Optimisation to the 1060/60 FPS target; settings menu; accessibility.
- Open beta weekends per region; anti-cheat tuning.

**Exit**: retention and stability targets met on open beta; Steam page live.

## Phase 5 – Early Access launch (4 weeks)

- Launch content: Solo/Duos/Fives, NA/EU regions, season 1.
- Live ops cadence: weekly hotfix, biweekly balance, 8-week seasons.

Post-launch candidates: knock/revive toggle for Fives, ranked queue, SA/AP regions, arcade
mode ("Shotties and Snipers"), replay viewer, spectator mode for tournaments, weather.

## Team shape

| Role | Count |
|---|---|
| Gameplay engineers (C++: movement, weapons, gear, inventory, vehicles) | 4 |
| Network / server engineer | 1 |
| Backend / DevOps | 1 |
| Technical artist | 1 |
| Environment artists | 2 |
| Character / weapon artist | 1 |
| Animator | 1 |
| UI/UX designer + implementer | 1 |
| Sound designer | 1 |
| Game designer / producer | 1 |

## Key risks and mitigations

| Risk | Mitigation |
|---|---|
| 150-player server CPU budget | Seeded client-side loot, aggressive relevancy, early load tests (Phase 3 start) |
| Gunplay doesn't "feel like 2016" | Phase 1 is entirely about feel; reference footage frame-by-frame for tracer, recoil, helmet pop |
| Random parachute spawn feels unfair | Telemetry heatmaps of spawn→death; loot-aware spawn bias as a tunable |
| Cheating | EAC from alpha, server authority everywhere, replays for reports |
| 8×8 km art scope | Modular building kits, procedural foliage/roads, HLOD; farms and forest are cheap, cities are the cost |
| Legal: likeness to the original | Original names, map, characters, and art; only mechanics and layout rhythm are replicated |
