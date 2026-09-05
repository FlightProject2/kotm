# 06 – Hit Mechanics & Protective Gear

"Every hit means something." This document defines exactly what happens when a projectile touches a
player.

## Hitboxes

The character has 7 hit regions attached to the skeleton:

| Region | Base multiplier | Notes |
|---|---|---|
| Head | ×3.5 (capped by weapon `headDamage`) | Helmet applies here |
| Upper torso (chest, back) | ×1.0 | Body armor applies here |
| Lower torso (stomach, pelvis) | ×1.0 | Body armor applies here |
| Upper arms + forearms + hands | ×0.7 | No gear |
| Upper legs | ×0.7 | No gear |
| Lower legs + feet | ×0.6 | Shoes apply here (minor) |
| Neck | ×1.5 | Small box between helmet and armor; an intentional "gap" |

Hit regions are authoritative on the server, rewound to the shooter's view time (see 12).
Hitbox sizes match the visible model; no oversized head box.

Player HP: **100**. No regen. Death at 0.

## Helmets

A helmet is a **single-hit item**. It absorbs the first headshot, is destroyed, and flies off the
character with a distinct "helmet pop" sound. The wearer takes a reduced share of the head damage.

| Helmet | Wearer takes | Rarity | Weight |
|---|---|---|---|
| Motorcycle Helmet | 45% of head damage | Common | 15 |
| Tactical Helmet | 25% of head damage | Rare | 20 |
| Makeshift Helmet (crafted) | 60% of head damage | Crafted | 12 |

Examples with the AR-15 (head damage 100): unhelmeted = dead. Motorcycle helmet = survive on 55 HP.
Tactical helmet = survive on 75 HP. In every case the helmet is gone and the next headshot kills.

Exception: the hunting rifle and the .44 Magnum are flagged `pierceHelmet: true`. A piercing weapon
destroys the helmet **and** applies full head damage, so a hunting rifle headshot (200) or a Magnum
headshot (135) is lethal through any helmet. This is the 2016 "sniper one-taps" feel and is the
reason those two guns are very rare.

Helmets do not protect the neck. Helmets have no durability bar; they are binary.

## Body armor

Body armor is a **durability pool** that soaks torso damage.

| Armor | Absorbs | Durability | Rarity | Weight |
|---|---|---|---|---|
| Laminated Tactical Body Armor | 80% of torso damage | 90 | Rare | 40 |
| Makeshift Plated Armor (crafted) | 60% of torso damage | 45 | Crafted | 35 |

Mechanics:
- On a torso hit, `absorbed = min(durability, damage × absorb%)`. Durability -= absorbed. The
  player takes `damage − absorbed`.
- When durability reaches 0 the armor is destroyed with an "armor break" clank and the vest model
  visibly changes to a torn state.
- Worked example: Laminated armor vs AR-15 chest hits (28): hit 1 → armor soaks 22.4, player takes
  5.6. Hit 2, 3, 4 → similar. After 4 hits armor at ~0.4, player at ~77 HP. Hit 5 breaks armor, player
  takes ~27. Hits 6 and 7 finish the job. So laminated armor turns a 4-shot AR kill into a 7-shot kill
  (run `python3 tools/ttk.py` for the full matrix). The AK (36) breaks it in
  3–4 hits. A shotgun blast up close (96) shreds it in one hit (absorbs 76.8, player takes 19.2) and
  the second blast is lethal.
- Armor does not protect arms, legs, neck, or head. Armor does not slow the player.

Balance intent: armor buys **one extra engagement's worth of mistakes**, not immortality. Headshots
bypass everything except the helmet.

## Shoes

Shoes are mostly cosmetic slot items but carry small real effects so the slot is worth caring about:

| Shoes | Footstep noise | Fall damage threshold | Other |
|---|---|---|---|
| Barefoot (none) | −40% | 3 m | Sprint −5% |
| Conveys (default sneakers) | 0% | 4 m | |
| Running Shoes | −15% | 4 m | |
| Work Boots | +20% | 6 m | Kick melee +5 dmg |
| Military Boots | +10% | 7 m | Lower-leg hits −10% dmg |

Shoes are visible on the model and skinnable. They are never a significant combat stat.

## Bleeding

Any bullet or arrow hit to flesh (unarmored region, or damage that got through armor) applies
**Bleeding**: −1 HP every 2 s until stopped, max stack 1. A bandage or first aid kit stops it. Blood
drops render on the ground behind a bleeding player (tracking cue). Melee and fire do not bleed.

## Damage sources summary

| Source | Damage |
|---|---|
| Firearms/arrows | Per table × region × gear |
| Melee | Flat per weapon, no region multiplier except head ×1.5 |
| Fall | Linear 4 m→15 m |
| Vehicle impact | 20–100 by speed, run-over is lethal above 35 km/h |
| Vehicle explosion | 100 within 5 m, linear to 0 at 12 m |
| Gas ring | Per phase, see 09 |
| Fire (molotov / burning vehicle) | 12/s while inside |
| Grenade | 100 → 0 across 3–8 m |
| Drowning | none; no breath meter, player just swims |

## Hit feedback ("hit meaning")

For the **shooter**:
- Reticle hitmarker: white × for flesh, yellow × with clank for armor, **red crack + helmet pop**
  sound for a helmet break, red skull flash for a kill.
- Damage-dealt is *not* shown as numbers (2016 style); the sound tells you what you hit.
- Kill popup bottom-left: victim name, `Killer`, `+100 XP` (screenshot 4).

For the **victim**:
- Screen edge red vignette pulse plus a directional damage indicator arc.
- Distinct incoming sounds for flesh hit, armor hit, helmet break; a "cracked" glass-style overlay for
  0.5 s on a helmet break.
- Camera shake proportional to damage.

For **everyone nearby**:
- Blood puff on flesh hits, sparks on armor, the helmet mesh physically flies off the head and lands as
  a non-lootable prop.
- Bullet impact decals on surfaces; dust puff on dirt; tracer trail from the muzzle to the impact.

## Kill feed

Top-right feed: `Killer  [weapon icon]  Victim` with a headshot icon when applicable and distance in
metres for hunting rifle kills. Feed persists 8 s. Solo shows all kills map-wide (2016 did).
