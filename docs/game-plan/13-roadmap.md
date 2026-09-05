# 13 – Roadmap & Milestones

Durations assume a core team of ~14 (see below). Adjust proportionally.

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
