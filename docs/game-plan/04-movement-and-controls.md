# 04 – Movement & Controls

## Camera

- **Third person** by default, camera 2.2 m behind and 0.4 m right of the character (over the right
  shoulder). Camera collision pulls in against walls.
- **Aim (RMB, hold)**: camera zooms in to 1.3 m over-the-shoulder with a reticle. Pistols, SMG, AR,
  AK, shotgun, bow all aim this way in third person. Hunting rifle (and any weapon with a scope
  attached) goes into a **first-person scope view** with a scope overlay.
- **First-person toggle (T)**: full first-person camera for all weapons, persists until toggled back.
  Competitive players use it for peeking honesty; third-person peeking around corners is allowed
  and expected (2016 behaviour).
- **Free-look (Alt, hold)**: rotate the camera without turning the character.

## Locomotion

| State | Speed **(tune)** | Notes |
|---|---|---|
| Walk (default) | 3.5 m/s | |
| Sprint (Shift) | 6.5 m/s | **Unlimited** sprint, no stamina bar. Cannot sprint while aiming |
| Crouch walk (C toggle) | 2.0 m/s | Reduces hitbox height, quiet |
| Prone crawl (Z toggle) | 1.0 m/s | Cannot fire while transitioning (0.5 s) |
| Swim | 2.5 m/s | Cannot use weapons; items not lost |
| Jump | 1.1 m vertical | Can jump over fences and low walls. **Can fire while airborne** (jump-shooting is legal and accurate, 2016 style) |
| Parachute | see 02 | |

- No vaulting or climbing animation. Crouch-jump onto ledges up to 1.4 m.
- Strafing while shooting: no accuracy penalty in hip fire beyond base spread; ADS spread is fixed.
- Turning: instant. Character orientation follows camera yaw when aiming, otherwise follows movement.
- No stance transition cost except prone.
- **Fall damage**: none up to 4 m, linear from 4 m to lethal at 15 m **(tune)**. Landing in water is safe.

## Actions

| Action | Key | Detail |
|---|---|---|
| Interact / pick up | F | Tap to pick up nearest item, hold for loot list, opens doors, enters vehicles |
| Reload | R | Cancellable by swapping weapons or sprinting |
| Hotbar | 1–6 | Six loadout slots (see 07). Pressing the current slot key holsters |
| Melee / fists | 1 (default slot) | Fists always occupy slot 1 unless a melee weapon replaces it |
| Throwables | G (cycle) / slot 6 | Hold to cook? **No**: grenades have a fixed 4 s fuse from release (2016) |
| Map | M | Full-screen map with player marker, team markers, safe zone circle, placed markers |
| Inventory | Tab | Inventory screen (see 10). Player keeps moving in the world while open |
| Voice PTT | V | Proximity voice (40 m radius, falloff). Team voice always on with a separate channel key (B) |
| Mute proximity | Alt+M | As in screenshot 2 |
| Mute targeted player | Ctrl+T | Mutes whoever your crosshair is on |
| Emote / gesture | X | Wheel: wave, point, dance |
| Scoreboard / players remaining | Tab (lobby) | |
| Push-to-scope hold vs toggle | option | |

Full default binding list in `design/data/keybinds.json`.

## Doors and windows

- Doors open toward the player pushing them and are a loud, distinctive audio cue (60 m).
- Windows break when shot or punched; glass sound cue at 40 m.

## Character collision

- Capsule 1.8 m tall standing, 1.2 m crouched, 0.6 m prone. Players collide with each other (can body
  block a door, 2016 style). No player-on-player push.

## Anti-exploit rules

- Server validates max speed per state with 10% tolerance and rewinds on violation.
- No leaning. No slide. No bunny-hop speed gain (jump preserves current speed, cannot exceed sprint).
- Prone in a bush is legal; grass render distance is server-enforced so the bush hides you for everyone.
