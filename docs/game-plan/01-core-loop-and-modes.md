# 01 – Core Loop & Game Modes

## Match flow

```
Main menu ─► Queue (Solo/Duos/Fives, region)
          ─► Lobby / staging area (up to 150 players, 2–3 min fill window)
          ─► "Match starts in 20 seconds" countdown
          ─► Parachute spawn: every player placed at a random sky point, chute open
          ─► Loot phase (free roam, whole map, ~3 min before safe zone reveal)
          ─► "Revealing safe zone in N" ─► Ring phases 1..7 with toxic gas
          ─► Last player / team alive = King of the Mountain
          ─► Results screen (placement, kills, XP, Skulls) ─► back to menu / requeue
```

## Lobby / staging area

Recreates screenshot 2: an airfield base at the foot of the Mountain with hangars, a fence line,
parked helicopters, and snow-capped peaks behind.

- Players spawn on the tarmac as they join, fists only, can run, jump, punch (no damage), and use
  proximity voice chat.
- Top-left `N REMAIN` shows connected player count; top-right `Match starting in N` with the
  countdown; centre banner `Match starts in 20 seconds` at T-20.
- Match starts when the lobby reaches 150 players **or** 180 s after the first player joins with at
  least 40 players **(tune)**. Below 40 the lobby waits up to 5 min then launches anyway.
- At T-0 the screen fades to black for 2 s and every player is teleported to their parachute spawn.

## Game modes

| Mode | Team size | Players | Friendly fire | Team voice | Notes |
|---|---|---|---|---|---|
| Solo | 1 | 150 | n/a | none | Baseline mode; leaderboard flagship |
| Duos | 2 | 150 (75 teams) | On | Team + proximity | Teams spawn **together** (see 02) |
| Fives | 5 | 150 (30 teams) | On | Team + proximity | Teams spawn together, team name tags + outline |

2016 had **no knocked / revive state**. When your HP hits 0 you die and drop a loot bag. Duos/Fives
survivors carry on. We ship that way for authenticity; a knock state is a post-launch experiment
behind a mode flag.

### Team rules
- Team mates are shown with a name tag, coloured marker, distance, and a health bar in the top-left
  team panel. Teammates are visible through walls as an outline within 200 m.
- Friendly fire is on (2016 behaviour). Team-killing is tracked and repeat offenders get queue
  cooldowns.
- Team spectate: after dying in Duos/Fives you spectate living team mates until the team is
  eliminated, then see the results screen.

## Win condition

- Solo: last player alive. Duos/Fives: last team with at least one living member.
- If the gas kills the final two simultaneously, the player who took the killing damage later wins
  (server timestamp). Never a draw.
- Winner sees the **KING OF THE MOUNTAIN** banner with a crown, kill count, and match time; everyone
  else sees "You placed #N".

## Match timeline (target 25–30 min)

| Time | Event |
|---|---|
| 0:00 | Parachute spawn |
| 0:00–3:00 | Free loot phase, whole map is safe |
| 3:00 | "Revealing safe zone in 30" banner |
| 3:30 | Safe zone 1 shown on map & compass. Gas wall begins closing at 5:00 |
| 5:00–25:00 | Ring phases 1–7 (see 09) |
| ~25:00 | Final circle (~50 m), gas at max damage |
| ≤ 30:00 | Match ends |

## Scoring per match

- +1 kill per elimination. Assist = 30% of damage on the target within 10 s **(tune)**.
- Placement points and **Skulls** (see 11) for Top 10.
- XP: kills, placement, damage dealt, survival minutes, first win of the day bonus.

## Spectating & death

- Solo: on death you see the death screen (killer name, weapon, distance, headshot flag) then
  can spectate your killer or leave. Spectating shows the killer's view in third person with a delay
  of 5 s to limit stream-sniping/ghosting.
- Proximity chat stays on for 5 s after death so last words are heard (H1Z1 hallmark).
