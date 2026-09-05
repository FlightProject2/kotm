# 08 – Vehicles

Vehicles are loud, fast, drifty and central to the 2016 feel: they get you to the zone from a bad
spawn, they are mobile cover, and they are a 100-damage bomb when they explode.

## Roster

| Vehicle | Seats | Top speed | Accel 0–60 km/h | Handling | HP | Fuel | Notes |
|---|---|---|---|---|---|---|---|
| **Off-Roader** (Jeep) | 4 | 110 km/h | 6 s | Best off-road, tallest ride | 1200 | 100 L | Open top: passengers can shoot, driver cannot |
| **Police Car** | 4 | 145 km/h | 4.5 s | Fastest on tarmac, slides on dirt | 900 | 80 L | Sirens toggle (audible 300 m); the meme car |
| **Pickup Truck** | 4 (2 cab + 2 bed) | 120 km/h | 5.5 s | Heavy, stable, big trunk | 1500 | 120 L | Bed passengers stand and shoot 360° |
| **ATV** (quad) | 2 | 95 km/h | 4 s | Nimble, goes anywhere, no protection | 500 | 40 L | Passenger can shoot; rider cannot. Screenshot 5 shows it in the menu diorama |

All numbers **(tune)**. ~40 vehicles per match spread over garages, roadside, farms and POIs, with
50% spawning with 20–60% fuel and 10% spawning empty (needs a gas can). Vehicles never spawn in
the lobby or the airfield.

## Physics feel

- Arcade vehicle model: 4 raycast wheels, high lateral grip on tarmac, low on dirt/grass so the car
  slides through corners with the handbrake (Space). Drifting is intended.
- Jumps and rolls happen; the car self-rights if upside down after 3 s (2016 did this).
- Collisions with trees and poles: small trees snap, big trees stop you and deal impact damage to
  the vehicle and occupants.
- Running over a player deals damage by speed and is lethal above 35 km/h.

## Damage and explosion

- Vehicle HP as in the table. Bullet damage to the body = weapon body damage ×0.5. Explosive arrow,
  grenade, molotov deal full damage and set the vehicle burning.
- Tires: each of 4 tires has 50 HP; a popped tire pulls the car and caps speed at 60%.
- At 25% HP the engine smokes; at 0 the vehicle **catches fire for 5 s then explodes** (100 damage
  within 5 m, 0 at 12 m). Occupants get an audio warning; jumping out is the only survival.
- Occupants can be shot through windows (glass does not stop bullets). The car body does.
- Fall damage to occupants when landing hard from jumps.

## Fuel

- Consumption ~1 L/km at full throttle. A full Off-Roader crosses the map once.
- Refuel with a Gas Can (found item, 40 weight) by holding F at the fuel cap (5 s), or drive over a
  gas station pump (hold F, 10 s for a full tank). Gas stations are loud, exposed, and remembered.
- Out of fuel = coast to a stop; the vehicle becomes cover only.

## Repair

- Vehicle Repair Kit (rare, industrial loot): hold F on the hood for 8 s, restores 50% HP and fixes tires.
- No passive regen.

## Entering and exiting

- F at any door enters the nearest seat; driver seat priority for the first player.
- Enter/exit is 0.8 s. Exiting at speed throws the player with ragdoll fall damage; exiting at
  >40 km/h is lethal-ish (2016 had this and it was funny; keep).
- Seat swap with number keys 1–4 while inside (no exit needed).

## Sound

Engines are audible at 400 m, tire squeal at 150 m, horn (H) at 300 m. Vehicles are the loudest thing
on the map; the sound design leans into it. Sirens on the police car are purely for chaos.

## Vehicle inventory

Trunk (600 capacity) and interior glove box (100) as described in 07, with the panel layout of
screenshot 4 (VEHICLE / INTERIOR).
