# 12 – Technical Architecture (Godot 4.6)

## Engine

**Godot 4.6.3, GDScript.** Chosen with the user for its open licence, a working headless toolchain
(every check in this repo runs without a GPU), Terrain3D as a GDExtension, built-in high-level
multiplayer over ENet, and Jolt physics. The project file sits at the repository root so
`res://design/data/*.json` is the single source of tuning truth for the game and for `tools/ttk.py`.

| Concern | Choice |
|---|---|
| Renderer | Forward+ on desktop; the web export uses the Compatibility (GLES3) renderer automatically |
| Physics | Jolt, 60 Hz; physics layers 1 world, 2 players, 3 hitboxes, 4 loot, 5 vehicles, 6 camera blockers |
| Terrain | Terrain3D 1.0.2 on desktop (built in code from the baked heightmap); `MeshTerrainBackend` (HeightMapShape3D + textured mesh) headless and on the web |
| Gameplay truth for height | `HeightField` (the baked `world/terrain/heightmap_2km.res` Image): floor clamp, projectile terrain hits, spawn mask, camera clamp. Never Terrain3D |
| Data | JSON under `design/data`, loaded by the static `DataLib` (works in `--script` test runs) |

## Authority and networking model

Everything with a gameplay consequence runs only where `multiplayer.is_server()` is true. Offline
Godot uses `OfflineMultiplayerPeer`, so single player executes the identical server path: this peer
is id 1 and every RPC is declared `call_local`.

- **Input up**: `Character._rx_input(bytes)` (`any_peer`, unreliable ordered) carries a packed
  `CharacterInput` (tick, move, yaw, pitch, aim direction, buttons, slot, medical use). Players build
  it from the InputMap and camera (`PlayerInputSource`); bots build it in `BotBrain`. Both drive the
  same `Character` body, so a bot and a player are indistinguishable to the simulation.
- **Events down**: `Net.event_all / event_to / fx_all` fan out through `Events` signals (hit
  confirmed, damaged, kill feed, remain, zone state, loot added/removed, tracer, hit fx, gunshot).
  HUD, audio and effects only listen to `Events`.
- **State**: `MultiplayerSynchronizer` per character and `MultiplayerSpawner` slots are reserved for
  host/join; loot, spawns and the zone derive from the match seed on every peer, so only removals and
  additions replicate.
- **Reserved**: client prediction in `CharacterMotor`, a hitbox-transform ring buffer in
  `HitboxRig` for lag compensation, interest management by 500 m cells.

## Simulation pieces

| Piece | File | Notes |
|---|---|---|
| Locomotion | `game/character/character_motor.gd` | walk/sprint/crouch, jump, fall damage, parachute; constants in `movement.json` |
| Weapons | `game/character/character_combat.gd` | per-weapon fire timers, semi/auto/bolt/pump, spread, reloads, melee, meds |
| Projectiles | `game/combat/projectile_system.gd` | 2.5 m sub-stepped rays against world, hitbox areas and the height field; per-gun gravity |
| Damage | `game/combat/damage_model.gd` | pure; tests reproduce `tools/ttk.py` |
| Hit regions | `game/character/hitbox_rig.gd` | bone-driven `Area3D`s updated from `skeleton_updated` |
| Loot | `game/inventory/*` | seeded tables, spatial-grid registry rendered by MultiMesh, prefab loot markers, death bags |
| Zone | `game/match/zone.gd` | reveal/warn/close phases from the preset, damage ticks, wall shader |
| Match | `game/match/match.gd` | seeded RNG streams, spawns, kill feed, win/lose, `SIM_SUMMARY` |
| World | `game/world/*` + `tools/bake_map.py` + `tools/godot/build_prefabs.gd` | baked heightmap and layout, kit-assembled prefabs, instanced trees with node-less trunk bodies |
| Cosmetics | `game/cosmetics/skin_system.gd` | procedural recolours and patterns, attachments, canopy |

## Headless verification

```
tools/ci/setup_godot.sh                      # pinned Godot 4.6.3 Linux binary
$GODOT --headless --path . --import
$GODOT --headless --path . --script res://tools/godot/run_tests.gd
$GODOT --headless --fixed-fps 60 --path . res://game/main/main.tscn -- --sim --seed=7 --bots=30 --sim-seconds=240 --no-player
$GODOT --headless --path . --export-release "Web" build/web/index.html
```

`--fixed-fps 60` makes simulations deterministic per seed. The web build is published to the
`gh-pages` branch and served by GitHub Pages.

## Scaling to 150 players (risk register)

GDScript CPU per character, per-character synchroniser bandwidth and ENet packet limits are the
known risks. Mitigations in order: 30 Hz network tick with 60 Hz physics, interest management by
500 m cells, low-rate parachute sync, typed GDScript in hot loops (bot perception, hitbox updates,
projectile sweeps), moving the projectile sweep and hitbox history into a small C++ GDExtension if
profiling demands it, a `--headless` dedicated-server export, and load tests with headless bot
clients from 60 to 150.
