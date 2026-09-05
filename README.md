# King of the Mountain (KOTM)

A PC battle-royale shooter built to recreate the feel of **H1Z1: King of the Kill, 2016 edition**
(pre-Combat-Update era): third-person, 150-player Solo / Duos / Fives, parachute-in from a random
point per player (no bus, no plane), projectile bullets with visible trails and per-gun drop,
helmets that crack, body armor that soaks, vehicles that drift, toxic gas that closes in, and the
last player standing crowned **King of the Mountain**.

This repository holds the **game plan** (design + technical blueprint), the **Godot 4.6 game** built from
it (`project.godot` at the root), and the original **browser prototype**.

## Play it

### In the browser (no install)

The Godot build is exported for the web and published on the `gh-pages` branch. Once GitHub Pages is
enabled for this repository (Settings > Pages > Deploy from a branch > `gh-pages` / root), it is served
at:

    https://flightproject2.github.io/kotm/

Click **PLAY**, then click once in the game to lock the mouse. Esc opens the pause menu.
**CUSTOMIZE** is an item grid (clothing, head, gear, weapon skins) with rarity bars; locked items
drop from crates. **MARKETPLACE** sells the Hot Shot Crate for coins earned in matches; winning a
match awards a free Victory Crate. Opening a crate runs a reel that lands on the drop. Dailies on
the main menu pay coins (and a crate) for kills, damage, pickups, top-10s, wins and driving.
Cars parked along the dirt roads are drivable: walk up, press F, WASD drives, Space brakes, F exits. The browser build uses the fallback mesh
terrain (Terrain3D has no web binary), runs single-threaded, and renders at 0.85 scale with smaller
shadows. Chrome or Edge on a desktop is recommended. After a new build is published, hard-refresh
(Ctrl+F5) so the browser drops the cached copy.

### In Godot (the real thing)

1. Install **Godot 4.6.x Standard** (not the .NET build) from https://godotengine.org/download.
2. Clone or download this branch.
3. In Godot's project manager choose **Import**, pick `project.godot` at the top of the folder, then
   **Import & Edit**. The first import takes a minute. If Godot asks to restart for the Terrain3D
   plugin, do so.
4. Press **F5**.

If the editor reports a Vulkan or Forward+ error on your GPU, run with `--rendering-driver opengl3`.

### Controls

WASD move, Shift sprint, Space jump, C crouch (knees bend, feet stay planted), right mouse aim
(hunting rifle scopes), left mouse fire, R reload, F pick up / loot bag / enter and exit a car, 1-6
hotbar, H bandage, J first aid kit, T first-person toggle, M map, Esc pause. Under the parachute: W
dives (faster descent), S flares, mouse steers. In a car: W/S throttle and reverse, A/D steer, Space
handbrake.

### Headless checks (contributors)

```
tools/ci/setup_godot.sh                 # downloads the pinned Godot 4.6.3 Linux binary
tools/ci/test.sh                        # import + 46 unit/scene tests + TTK parity with tools/ttk.py
scratch/godot/Godot_v4.6.3-stable_linux.x86_64 --headless --fixed-fps 60 --path . res://game/main/main.tscn -- --sim --seed=7 --bots=30 --sim-seconds=240 --no-player
scratch/godot/Godot_v4.6.3-stable_linux.x86_64 --headless --path . --export-release "Web" build/web/index.html
```

`python3 tools/bake_map.py` regenerates the terrain and layout; `tools/godot/bake_terrain.gd` converts
the heightmap; `tools/godot/build_prefabs.gd` rebuilds the building prefabs from `design/map/prefabs.json`.

### The original browser prototype

`prototype/index.html` is the single-file Three.js prototype the Godot build was ported from. Open it
in a browser (needs internet for the graphics library). It is kept as the gameplay reference.

## Document index

| # | Document | What it covers |
|---|----------|----------------|
| 00 | [Vision & pillars](docs/game-plan/00-vision.md) | What we are making, what we are *not* making, reference era, pillars |
| 01 | [Core loop & modes](docs/game-plan/01-core-loop-and-modes.md) | Lobby/warmup, match flow, Solo/Duos/Fives, win condition, match timeline |
| 02 | [Parachute spawn](docs/game-plan/02-parachute-spawn.md) | Random-position-per-player air spawn, parachute physics, steering, landing, anti-clump rules |
| 03 | [Map & world](docs/game-plan/03-map-and-world.md) | 8x8 km map layout, POIs, biomes, buildings, loot density, the Mountain |
| 04 | [Movement & controls](docs/game-plan/04-movement-and-controls.md) | Third/first person, sprint, crouch, prone, jump, swim, fall damage, keybinds |
| 05 | [Weapons & ballistics](docs/game-plan/05-weapons-and-ballistics.md) | Full arsenal, projectile model, bullet drop per gun, tracers, recoil, spread, reload |
| 06 | [Hit mechanics & gear](docs/game-plan/06-hit-mechanics-and-gear.md) | Hitboxes, damage model, helmets, body armor, shoes, bleeding, hit feedback |
| 07 | [Loot, inventory & crafting](docs/game-plan/07-loot-inventory-crafting.md) | Weight-based inventory, backpacks, loot tables, crafting recipes, death bags |
| 08 | [Vehicles](docs/game-plan/08-vehicles.md) | Off-roader, police car, pickup, ATV; fuel, damage, physics, vehicle inventory |
| 09 | [Gas, safe zone & airdrops](docs/game-plan/09-gas-and-airdrops.md) | Safe zone reveal, ring phases, gas damage, airdrop tickets |
| 10 | [UI / UX](docs/game-plan/10-ui-ux.md) | Main menu, lobby, HUD, inventory screen, customize screen, kill feed, death screen |
| 11 | [Progression & customization](docs/game-plan/11-progression-customization.md) | XP, Skulls, missions, dailies, fragments, leaderboards, seasons, skins, marketplace |
| 12 | [Technical architecture](docs/game-plan/12-tech-architecture.md) | Engine choice, netcode, server authority, lag compensation, backend services, anti-cheat |
| 13 | [Roadmap & milestones](docs/game-plan/13-roadmap.md) | Phases, deliverables, team shape, risks |
| 14 | [Audio & VFX](docs/game-plan/14-audio-vfx.md) | Gunshot audio model, footsteps, tracers, hit VFX, gas, parachute |

## Tuning data

Starting balance values live as data so they can be loaded straight into the engine and iterated:

- [`design/data/weapons.json`](design/data/weapons.json) – per-weapon damage, velocity, drop, RPM, recoil, spread
- [`design/data/armor.json`](design/data/armor.json) – helmets, body armor, shoes, backpacks
- [`design/data/gas-phases.json`](design/data/gas-phases.json) – safe zone reveal + ring shrink schedule
- [`design/data/loot-tables.json`](design/data/loot-tables.json) – spawn weights per loot tier
- [`design/data/vehicles.json`](design/data/vehicles.json) – vehicle stats
- [`design/data/keybinds.json`](design/data/keybinds.json) – default control scheme

`python3 tools/ttk.py` prints the shots-to-kill / time-to-kill matrix for every gun against bare,
laminated-armor, and helmeted targets straight from those files, so balance changes can be checked
before touching the engine.

## Reference screenshots

The plan was written against five reference captures of the original game:

1. Third-person over-the-shoulder combat on an open road, ammo `28/238` and health bottom-centre.
2. Pre-match lobby at the airfield base: "Match starts in 20 seconds", `14 REMAIN`, compass strip, proximity-chat hints.
3. Customize screen: slot / category / skin grid with rarity, "Only Show Owned" toggle.
4. Inventory screen: EQUIPPED grid with hotbar numbers, CARRYING weight bar `339/1200`, VEHICLE + INTERIOR panels, CRAFTING column, "Revealing safe zone in 31".
5. Main menu: PLAY / CUSTOMIZE / MARKETPLACE / LEADERBOARDS / SETTINGS, MISSIONS, FRAGMENTS, DAILIES, Message of the Day, character in a 3D diorama.

Where a number in these documents is a guess at the original's tuning it is marked **(tune)**; it is a
starting point for playtesting, not gospel.
