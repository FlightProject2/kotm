# 12 – Technical Architecture

## Engine

**Unreal Engine 5 (5.4+), C++ core with Blueprints for content.** Rationale:
- Proven 100+ player BR networking (replication graph / Iris, network prediction, server-side
  rewind) and mature dedicated-server tooling on Linux.
- Chaos Vehicles for the arcade car model; Gameplay Ability System (GAS) for attributes (HP, bleed,
  armor durability) and effects (gas, fire, heal-over-time).
- World Partition + HLOD for an 8×8 km streamed map.
- Large hiring pool.

Alternatives considered: Unity + Netcode for Entities (weaker at 150-player open world out of the
box), Godot (no proven large-scale netcode), custom (too slow). Decision: UE5.

## Networking model

- **Dedicated authoritative servers**, Linux, headless. One match per server process. Target
  **30 Hz server tick** with 60 Hz client simulation and interpolation.
- Client-side prediction for movement and weapon firing (muzzle flash, tracer, recoil instantly);
  server confirms hits. Projectiles are spawned on the client for visuals and on the server for truth;
  mismatch shows as a tracer that didn't cause a hitmarker.
- **Lag compensation**: the server keeps 1 s of hitbox history per player and rewinds to the
  shooter's estimated view time (clamped to 250 ms) when spawning their projectile and on each
  sub-step. Beyond 250 ms ping you must lead more, which is the honest trade-off.
- **Relevancy / interest management**: replication graph with spatial grid cells of 500 m. Players
  in the parachute phase use a low-rate "distant" update. Nearby players (<150 m) update at full
  rate; 150–600 m at 10 Hz; beyond 600 m only for the kill feed and sound events (gunshot events are
  replicated map-wide as lightweight RPC for audio at up to 1.2 km for rifles).
- Bandwidth budget: ≤ 60 kB/s down, 10 kB/s up per client in the worst case (final circle).
- Voice: proximity + team voice through a separate low-latency voice service (Vivox or EOS Voice)
  with server-driven positional metadata.

## Anti-cheat

- Server authority on everything with a gameplay consequence: movement validation (speed, teleport,
  fly), fire-rate caps, projectile origin checks (bullet must originate within 30 cm of the weapon
  muzzle), inventory authority, loot pickup range.
- Kernel-level anti-cheat on the client: **Easy Anti-Cheat (EOS)** at launch, BattlEye as fallback.
- Server-side stats anomaly detection (headshot ratio, reaction time distribution) feeding a review
  queue and shadow-ban list.
- Replay recording on the server (input + state snapshots, ~10 MB/match) kept 14 days for reports.

## Backend services

```
 Client ──► Auth (Steam ticket → JWT)
        ──► Matchmaker (mode, region, party) ──► Fleet manager (Agones on Kubernetes)
        ──► Session (server IP/port + join token)
        ──► Game server ──► Match results ──► Stats/Leaderboards/Progression
        ──► Inventory/Cosmetics, Marketplace, Missions, Dailies, Friends/Party, Telemetry
```

| Service | Tech |
|---|---|
| Auth | Steam auth ticket exchange, EOS as secondary; JWT with 1 h TTL |
| Matchmaker | Go service, Redis queues per mode/region; fills lobbies to 150 or times out (see 01) |
| Fleet | Agones + Kubernetes on cloud VMs (c6i / n2 class, 1 match per 4 vCPU / 8 GB), autoscaled per region |
| Player data | PostgreSQL (accounts, inventory, progression), Redis (sessions, leaderboards via sorted sets) |
| Telemetry | Match events streamed to Kafka → ClickHouse for balance dashboards (weapon TTK, spawn heatmaps, gas deaths) |
| Content | Loot tables, weapon tuning, gas schedule loaded from the `design/data/*.json` files at server start; hot-reloadable in dev |

## Client performance targets

| Setting | Target |
|---|---|
| 1080p Medium, GTX 1060 / RX 580 | 60 FPS avg, 45 FPS 1% low in the lobby |
| 1440p High, RTX 3070 | 120 FPS |
| Load into lobby | < 20 s from queue pop on SSD |
| Memory | < 8 GB RAM, < 4 GB VRAM at medium |

## Server performance targets

- 150 players, 40 vehicles, ~10k loot actors: ≤ 25 ms frame at 30 Hz on 4 vCPU.
- Loot actors are not replicated individually; the client receives a match seed + loot table and
  spawns identical loot locally, with the server only replicating **removals** (pickups) and
  additions (death bags, airdrops). This is what makes 10k items cheap.

## Repository layout (proposed)

```
/docs/game-plan/         design documents (this plan)
/design/data/            tuning JSON consumed by the game
/Game/                   UE5 project
  /Source/KOTM/          C++ modules: Core, Movement, Weapons, Ballistics, Gear, Inventory,
                          Vehicles, Zone, Spawn, UI, Net
  /Content/              assets (Git LFS)
/Server/                 Dockerfile, Agones config, server launch scripts
/Services/               matchmaker, auth, stats, marketplace (Go)
/Tools/                  balance sim (Python: TTK calculator from weapons.json), spawn visualiser
```

## Testing

- Headless bot clients (UE5 `-nullrhi`) to fill 150-player lobbies in CI load tests.
- Deterministic ballistics unit tests against `weapons.json` (drop at 100/200/300 m, TTK matrix).
- Nightly soak: 8 h of continuous matches on one region with bots; crash-free requirement.
