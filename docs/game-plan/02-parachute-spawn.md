# 02 – Parachute Spawn (random point per player)

This is the defining difference from "traditional BR". There is no plane, bus, or drop line. When the
match starts each player (or team) is placed at a random point in the sky with the parachute already
open, and floats down onto whatever is below.

## Spawn selection

1. The map has a **spawn mask**: everything inside the playable bounds minus water, cliffs steeper
   than 45°, and the 200 m map border.
2. For each solo player / team, the server picks a candidate point uniformly in the mask, then rejects
   it if it is within **250 m (tune)** of an already-chosen point. Up to 20 retries, then the distance
   requirement relaxes by 25 m per retry. With 150 solos on 64 km² the average spacing is ~650 m.
3. The point is placed at a **spawn altitude of 400 m (tune)** above terrain.
4. Teams (Duos/Fives) spawn on a ring of radius 15–30 m around their team point, same altitude, so
   they land together.
5. The safe zone is **not** known at spawn time and spawn points are not biased toward it. Spawning
   is fair by expectation: no one knows anything yet.

Optional fairness tweak **(tune)**: bias the spawn distribution to be **loot-density-aware** so
players are not systematically dropped into empty forest. Start uniform; evaluate in playtests.

## Parachute physics

The 2016 parachute is simple and forgiving. Model it as a kinematic controller, not a cloth sim.

| Parameter | Value **(tune)** |
|---|---|
| Vertical descent speed (neutral) | 6 m/s |
| Vertical descent speed (pitched forward, W) | 9 m/s |
| Vertical descent speed (flared, S) | 4 m/s |
| Horizontal speed (max) | 12 m/s |
| Horizontal acceleration | 6 m/s² |
| Turn rate | 60°/s (A/D or mouse) |
| Time to ground from 400 m at neutral | ~65 s |
| Max horizontal travel | ~800 m at full forward |

- Camera: third person, pulled back 1.5× normal, free-look allowed (Alt).
- No cut-away. You cannot detach early. You cannot deploy late. Everyone's chute is open from frame 1.
- Landing: when the capsule is within 1.5 m of the ground the chute detaches with a small animation
  (0.6 s) during which the player cannot fire. Landing on a roof is fine.
- Landing in water is allowed (the mask avoids it for the spawn point but the player can steer there);
  player swims.
- Collision with buildings/trees during descent: the player slides along the surface; no damage.

## What players can do while descending

- Look around, steer, open the map (M) to plan, and see the compass.
- Proximity voice chat works, so you may hear a neighbour coming down.
- **No shooting, no inventory.** Fists are the only "weapon" on landing.

## Why this matters for balance

- Removes the hot-drop, spreads combat across the whole map early, and makes the free-loot phase
  about local scavenging rather than fighting for one crate.
- Because everyone lands within about a minute, the first 3 minutes are near-silent, then the safe
  zone reveal starts the funnel.
- Vehicles matter more: a bad spawn far from the zone is fixed by finding a car, not by spawn luck alone.
  Vehicle density is tuned so ~1 vehicle per 4 players exists on the map (see 08).

## Server implementation notes

- Spawn selection runs once at match start on the server and is deterministic from the match seed
  (logged for replay/debug).
- Parachute movement is server-authoritative with client prediction, the same movement component as
  on foot but in `Falling_Parachute` mode. Cheating by "fast-falling" is caught by the movement validator
  (max vertical speed check).
- The parachute uses a simplified network update (position, yaw, pitch) at 10 Hz for distant players
  since nobody can interact in the air.
