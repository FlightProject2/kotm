# 14 – Audio & VFX

Sound is the primary information channel in this game; it must be loud, distinct and directional.

## Gunshots

- Each weapon has a **near** layer (< 50 m, full punch), a **mid** layer (50–300 m, echo tail) and
  a **distant** layer (300–1200 m, low thump with the biome reverb: open field vs forest vs city).
- Audible ranges: pistols 500 m, SMG 600 m, shotgun 700 m, AR/AK 1000 m, hunting rifle 1200 m.
  Bow is 20 m.
- Gunshot events are replicated as lightweight one-shot RPCs (weapon id, position) independent of
  actor relevancy, so distant shots are always heard.
- Supersonic **bullet crack** plays when a bullet passes within 3 m of the listener.

## Hit sounds (the "hit meaning" set)

| Event | Shooter hears | Victim hears | Nearby hear |
|---|---|---|---|
| Flesh hit | soft thud + hitmarker tick | wet impact, grunt | grunt |
| Armor hit | metallic clank | clank + ringing | clank |
| Armor break | double clank + tear | tear + gasp | tear |
| Helmet hit / pop | sharp crack + "ping" | crack + tinnitus 0.5 s | crack, helmet clatter on ground |
| Headshot kill | crack + kill sting | – | – |
| Kill | short skull sting | death vocal | death vocal |

## Footsteps and movement

- Surface-aware footsteps (grass, dirt, wood floor, concrete, metal, water). Sprint audible 40 m,
  walk 20 m, crouch 8 m, prone 3 m. Shoes modify (see 06).
- Landing thud on jump (25 m). Prone transition rustle.
- Doors: open/close 60 m. Window break 40 m. Loot pickup rustle 6 m.

## Vehicles

Engine layers by RPM, tire surface squeal, handbrake, suspension bottom-out, horn, siren, explosion
(800 m), burning loop.

## Zone

Gas wall hum (audible 150 m from the wall), inside-gas coughing and muffled EQ, warning klaxon
on "gas closing" toasts. Airdrop plane fly-over map-wide.

## VFX

- **Tracers**: emissive ribbon from muzzle along the projectile path, 0.15 s fade, pale yellow;
  hunting rifle tracer is brighter and longer. Visible from any distance in render range.
- **Muzzle flash**: per weapon, visible at night-free noon lighting through a strong emissive.
- **Impacts**: blood puff (flesh), sparks (armor/metal), splinters (wood), dust (dirt), glass shards.
- **Helmet pop**: helmet mesh detaches with impulse, bounces with physics, despawns 30 s.
- **Gas wall**: vertical translucent green plane with scrolling noise + particles; inside: green
  post-process, film grain, chromatic aberration.
- **Fire**: molotov pool and burning vehicles with heat distortion.
- **Parachute**: cloth-sim-free canvas mesh with a flutter animation, detach puff on landing.
- **Airdrop**: red smoke column 100 m tall, 1 km visible.

## Music

Menu theme (distorted guitar, sparse drums) and a short winner sting. No in-match music.
