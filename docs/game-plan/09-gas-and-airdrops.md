# 09 – Gas, Safe Zone & Airdrops

## Safe zone reveal

- At **3:00** the top-right HUD shows `Revealing safe zone in 30` with a green gas-mask icon
  (screenshot 4). At 3:30 the first safe zone circle appears on the map and as a green tick on the
  compass.
- The circle is a random point in the map interior such that the entire circle lies within the
  playable bounds and not more than 40% water.
- Each subsequent circle is chosen uniformly inside the previous circle (fully contained), never
  the same centre.

## Ring phases

Full schedule in `design/data/gas-phases.json`. Summary **(tune)**:

| Phase | Circle radius | Warning | Close duration | Gas damage |
|---|---|---|---|---|
| 0 (map edge) | ~4500 m (whole map) | – | – | 5 HP/s outside bounds |
| 1 | 2000 m | 90 s | 150 s | 1 HP / 2 s |
| 2 | 1200 m | 60 s | 120 s | 1 HP/s |
| 3 | 700 m | 60 s | 90 s | 2 HP/s |
| 4 | 400 m | 45 s | 75 s | 3 HP/s |
| 5 | 220 m | 45 s | 60 s | 5 HP/s |
| 6 | 110 m | 30 s | 45 s | 7 HP/s |
| 7 (final) | 45 m | 30 s | 45 s | 10 HP/s |
| 8 (collapse) | 0 m | – | 60 s | 15 HP/s |

- The gas wall is a **translucent green vertical wall** with particulate motion, visible from any
  distance. Inside the gas the screen desaturates, goes green at the edges, and a coughing sound
  plays. The HUD health bar flashes.
- Gas damage ignores helmet and armor. Bandaging in gas works but is a losing race in phase 5+.
- Gas moves at a constant linear rate from the previous circle to the next during the close duration.
- Vehicles are not damaged by gas; occupants are.

## HUD elements for the zone

- Compass strip: green segment marking the direction of the safe zone, distance in metres to the
  edge when outside.
- Minimap: none (2016 had no minimap). Full map on M only.
- Top-right: gas timer `Next zone in N` / `Gas closing in N`, green icon.

## Airdrops

Airdrops are player-initiated (2016 KotK behaviour), not timed.

- **Airdrop Ticket**: a rare loot item (~12 per match). Using it (hold F on the item in inventory or
  hotkey) calls a plane that flies over the current safe zone and drops a **supply crate** on a
  parachute at a random point inside the safe zone, 60 s after the call.
- The plane is audible map-wide and visible; the crate lands with a **red smoke column** visible
  from 1 km. Everyone knows.
- Crate contents: 1 AR-15 or AK-47, 1 Hunting Rifle, 1 Tactical Helmet, 1 Laminated Armor,
  2 First Aid Kits, ammo for each weapon, 1 random rare item (Magnum, explosive arrows ×3, grenades
  ×3).
- Crates are lootable for the rest of the match. The crate is solid cover.

Airdrop tickets in Duos/Fives are the same; the reward set scales to 2/3 sets for Fives **(tune)**.

## Players remaining

Top-left counter `N REMAIN` (screenshot 2 style, red numeral). Updates live. A short "N players
remaining" toast at 50, 25, 10, 5, 2.
