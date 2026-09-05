# 10 – UI / UX

Art direction: **grungy red-and-white on dark**, distressed textures, all-caps condensed headings
(Bebas / Oswald style), red accent bars, thin white outlines. Menus are 3D dioramas with the player's
character in them. The HUD is minimal and sits at the edges; the centre of the screen is clean.

## Main menu (screenshot 5)

Layout:
- **Left column** on a cracked red concrete panel: logo top-left; large red triangle-bullet items
  **PLAY**, **CUSTOMIZE**, **MARKETPLACE**; smaller **LEADERBOARDS**, **SETTINGS**; a **MESSAGE OF
  THE DAY** card with a carousel; **EXIT** button bottom.
- **Top bar**: currency counters (Crowns, Skulls, XP-coin, Fragments), player level and name,
  help `?`, four `+` shortcuts (add friends / party slots), a dropdown caret.
- **Centre-top**: three panels over the diorama: **MISSIONS** (Warmup / Easy / Medium / Hard tabs
  with progress bars and reward counts), **FRAGMENTS** (14/20, 1/5 progress toward crate fragments),
  **DAILIES** (four daily tasks with `0/1` style counters, tick circles).
- **Diorama**: the player's character with currently equipped skins standing at the helicopter,
  crates, ATV scene. Rotates slowly with mouse.
- **Party**: bottom-right party bar with up to 4 friend portraits, invite, ready toggle.

Play flow: PLAY opens a mode picker (Solo / Duos / Fives) with a region dropdown, estimated queue
time and current player counts. Clicking a mode queues; a queue timer replaces the PLAY button.

## Lobby HUD (screenshot 2)

- Top-left `14 REMAIN` in red.
- Top-centre compass strip.
- Top-right `Match starting in N` with green banner; ping and FPS below it (`16ms`).
- Centre banner `Match starts in 20 seconds.` at T-20, dark translucent pill.
- Bottom-left small key hints: `[Alt+M] Mute Proximity Chat`, `[Control+T] Mute Targeted Player`.
- Bottom-centre health bar (full, `100`).

## In-match HUD (screenshot 1)

- **Bottom-centre**: health bar (red fill on dark, white `+` at left, numeric HP right), ammo
  `28/238` above it with the weapon icon and fire-mode. Bleed icon appears at the left when bleeding.
- **Top-centre**: compass strip with N/E/S/W, degree ticks, green safe-zone marker, team markers.
- **Top-left**: `N REMAIN`, team panel (Duos/Fives) with names and health bars.
- **Top-right**: gas timer / safe zone message, ping & FPS, then kill feed below.
- **Bottom-left**: kill/XP popups (`Killer +100 XP` with the victim's name on an orange bar,
  screenshot 4), item pickup toasts.
- **Bottom-right**: hotbar strip of 6 small tiles (only the active one lit) with item counts.
- **Reticle**: small white dot + bloom ring when hip firing; changes to a thin cross when aiming.
  Hunting rifle: full scope overlay.
- **Voice**: small speaker icon with the speaking player's name near the top-left when someone talks.
- No minimap. No damage numbers. No compass-hidden enemies.

## Inventory screen (screenshot 4)

Opens with Tab as a translucent overlay; the world keeps rendering and you can still walk (WASD
works with the inventory open, a 2016 quirk we keep).

- Header tabs: **INVENTORY** (red) / OPTIONS.
- **EQUIPPED** panel top-centre: left column of cosmetic slots (face, head, hands, chest, legs,
  feet), a character silhouette in the middle, the right column of 6 numbered loadout slots with
  ammo counts.
- **CARRYING** panel below: weight bar `339/1200`, then item tiles.
- **VEHICLE** panel to the right when inside/next to a vehicle, with an **INTERIOR** sub-panel.
- **CRAFTING** column far right: recipe tiles; available ones lit.
- Bottom: `[Tab|ESC] Close`, `MORE INFO` toggle for a tooltip panel, the hotbar strip stays visible.
- Drag and drop between panels, right-click for use/equip/drop, mouse wheel for quantity split.
- Hovering shows the tooltip with name, rarity, weight, stats, "Field Bandage" style popup.

## Customize screen (screenshot 3)

- Left: the character on a dark backdrop, full body, slowly turnable.
- Right panel headed **CUSTOMIZE / GEAR**: **SLOT** row (Head, Face, Chest, Legs, Feet, Hands, Back,
  Weapon skins), **CATEGORY** row (e.g. Hat), then the **SKIN** grid with the selected skin's name and
  rarity in colour (`Snakeskin Boonie Hat – Common`). Owned items full colour, unowned dimmed.
- Bottom: `Only Show Owned` toggle, `[ESC] BACK`.
- Right edge: filter buttons (rarity, newest).

## Map screen (M)

Full-screen hand-painted style map with grid letters/numbers, POI labels, your marker, team
markers, the safe zone circle (white) and current gas edge (green), placed pings. Scroll to zoom.

## Death screen

Dark overlay: `YOU PLACED #N`, killer name and weapon, distance, headshot tag, your kills/damage,
XP breakdown, buttons **SPECTATE**, **LEAVE**. Winner variant: crown graphic, `KING OF THE
MOUNTAIN` in distressed red type, confetti-free.

## Settings

Video (resolution, display mode, FOV 70–100, quality presets, per-setting toggles), Audio
(master, effects, voice, music; voice input device; PTT vs open mic), Controls (full rebind, mouse
sensitivity separate for hip/ADS/scope), Gameplay (first-person default, aim toggle, crouch/prone
toggle vs hold, show kill feed, show XP popups), Account (region, name).

## Accessibility

Colour-blind palette for gas/zone/team markers, scalable HUD (80–130%), remappable everything,
subtitles for voice lines in tutorial.
