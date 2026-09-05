# 05 – Weapons & Ballistics

The full numeric table is in `design/data/weapons.json`. This document explains the model and the
intent behind each gun.

## Ballistic model

Every firearm shoots a **server-simulated projectile**, not a hitscan ray.

- Each projectile has a **muzzle velocity** and a **gravity multiplier** per weapon. Drop = ½ · g ·
  mult · t². A tuned gravity multiplier is how we reproduce the exaggerated drop of the original
  (the hunting rifle drops visibly at 200 m; the AR at 150 m).
- Simulation step: server sub-steps projectiles at 120 Hz along their path, sweeping a thin capsule
  against hitboxes with lag compensation (see 12). Max range before despawn: 800 m.
- **Tracer / bullet trail**: every bullet from every gun renders a visible trail for everyone in
  render range, coloured pale yellow-white, 0.15 s lifetime (screenshot 1 shows them mid-air). This
  is deliberate: you can see where you're being shot from, and you can see your own drop to correct.
- No damage falloff by distance for rifles and pistols; the drop and travel time are the range
  penalty. Shotgun pellets and the SMG have falloff (see table).
- No penetration through walls. Wooden doors, fences and glass are penetrated at full damage.
  Vehicles block bullets except windows.

## Hip fire vs aim

- **Hip fire**: cone spread from the table; reticle bloom shows it. Moving adds +50% spread; jumping
  adds +100%.
- **Aim (RMB)**: over-the-shoulder aim; spread drops to the ADS value (near zero for rifles). No
  movement speed penalty while aiming beyond "cannot sprint" (2016 behaviour). Jump-aim allowed.
- **Recoil**: vertical kick per shot plus small random horizontal; recovers in 0.25 s. The AK kicks
  roughly 1.7× the AR. Recoil is applied to the camera, so it is fully controllable with mouse.

## Fire rates

The AR-15 and AK-47 are **semi-automatic only** (no full auto), fire-rate capped so spam clicking
cannot exceed the cap. The Hellfire 4-6 is the only full-auto weapon. The shotgun is pump. The hunting
rifle is bolt action with a 1.3 s cycle where the scope stays up.

## Arsenal

### Rifles

| Weapon | Ammo | Mag | Role |
|---|---|---|---|
| **AR-15** | .223 | 30 | The backbone. Accurate, mild recoil, 4 body / 1 head (no helmet). The gun to learn |
| **AK-47** | 7.62 | 30 | Harder-hitting, 3 body, more recoil and spread, slower fire cap. Rarer |
| **Hunting Rifle** | .308 | 5 (internal) | Bolt-action sniper with 4× scope. 2 body, 1 head **through any helmet**. Loud, rare |

### Close range

| Weapon | Ammo | Mag | Role |
|---|---|---|---|
| **12-Gauge Pump Shotgun** | shells | 6 | 8 pellets, devastating under 8 m, useless past 25 m. Two-shot at mid-close |
| **Hellfire 4-6** | .45 ACP | 30 | Full-auto SMG, low per-bullet damage, fast time-to-kill under 20 m if you land most shots |

### Pistols (found early, keep for last resort)

| Weapon | Ammo | Mag | Role |
|---|---|---|---|
| **M9** | 9mm | 15 | Standard pistol, common |
| **R380** | .380 | 7 | Weakest gun, very common |
| **M1911** | .45 ACP | 7 | Hits harder, slower |
| **.44 Magnum** | .44 | 6 | Revolver, one-shot headshot without helmet, 3 body. Rare |

### Bow

| Weapon | Ammo | Notes |
|---|---|---|
| **Recurve Bow** | Arrows | Silent, arcs heavily, 40 body / 100 head. Arrows can be recovered from bodies/walls |
| Crafted arrows | Flaming arrow, Explosive arrow | See 07. Explosive arrow = 70 splash, sets vehicles alight |

### Melee

| Weapon | Damage | Speed | Notes |
|---|---|---|---|
| Fists | 10 | fast | Always available |
| Combat Knife | 25 | fast | |
| Wrench | 30 | med | |
| Hatchet | 35 | med | |
| Machete | 40 | med | The iconic one; 3 hits |
| Crowbar | 35 | slow | Also opens locked car trunks instantly |

Melee has a 2 m reach, 180° arc in front, and a light lunge. Can be used while sprinting (H1Z1
"machete rush").

### Throwables

| Item | Fuse | Effect |
|---|---|---|
| Frag Grenade | 4 s from throw | 100 dmg at 0–3 m, linear to 0 at 8 m; blocked by walls |
| Molotov Cocktail | impact | 4 m fire pool for 8 s, 12 dmg/s, ignites vehicles |
| Gas Grenade | impact | 6 m cloud for 12 s, same damage as ring gas phase 3; blocks vision |
| Smoke Grenade | impact | 8 m opaque cloud for 15 s |

Throw arc is shown as a dotted line while holding the throw key; release to throw. Underhand throw
with the secondary key.

## Scopes and attachments

2016 had almost no attachment system. We ship exactly:

- **Hunting rifle**: integrated 4× scope.
- **AR-15 / AK-47**: can attach a **Reflex sight** or **2× scope** found as loot **(tune: consider
  removing for purity)**. No grips, no suppressors, no extended mags.
- **Laser sight** for pistols: cosmetic dot, no stat change. Optional.

## Ammo

Ammo stacks: .223 ×20, 7.62 ×20, 9mm ×15, .380 ×15, .45 ×15, .308 ×5, shells ×6, arrows ×5.
Reserve ammo is only limited by inventory weight (see 07). The HUD shows `mag / reserve`
(`28/238` in screenshot 1).

## Reloads

Tactical reload keeps the round in the chamber (30+1 for AR/AK). Reload times in the data table.
Reloading while sprinting is allowed at 1.3× duration. Shotgun reloads shell-by-shell and can be
interrupted to fire.

## Weapon swap

Swap time 0.6 s between primary slots, 0.4 s to a pistol, 0.3 s to melee. No quick-swap cancels
of the bolt cycle on the hunting rifle.

## Weapon rarity / loot tiers

| Tier | Weapons | Where |
|---|---|---|
| Common | R380, M9, Combat Knife, Wrench | Any house |
| Uncommon | M1911, Shotgun, Hellfire, Machete, Hatchet, Bow | Houses, sheds, shops |
| Rare | AR-15, AK-47 | Police station, military, city, farm barns (AR is "rare" but there are ~450 on the map) |
| Very rare | Hunting Rifle, .44 Magnum | Military, hunting stands, airdrops |
| Airdrop only | Guaranteed AR/AK + Hunting rifle + Tactical helmet + Laminated armor + medkits | Airdrop crate |
