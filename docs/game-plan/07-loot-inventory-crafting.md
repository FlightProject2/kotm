# 07 – Loot, Inventory & Crafting

## Inventory model

Weight-based, matching the `339/1200` bar in screenshot 4. There is no grid tetris. Every item has a
weight; the total must stay under the carry capacity.

| Capacity source | Capacity |
|---|---|
| Base (pockets) | 400 |
| School Backpack | +300 (700) |
| Framed Backpack | +500 (900) |
| Military Backpack | +800 (1200) |

Being over capacity (e.g. after picking up a bag's worth by mistake) blocks sprinting until you drop
weight. The bar turns red.

Representative weights: rifle 50, pistol 20, shotgun 45, hunting rifle 60, ammo stack 5–10, helmet
15–20, laminated armor 40, first aid kit 15, bandage 3, grenade 10, gas can 40, vehicle repair kit 30.

## Equipment slots

| Slot | Items |
|---|---|
| Head | Helmet (functional) + Hat (cosmetic) share the head; hat hides under helmet |
| Face | Mask / glasses (cosmetic) |
| Chest | Body armor (functional) over Shirt (cosmetic) |
| Legs | Pants (cosmetic) |
| Feet | Shoes (minor functional, cosmetic) |
| Hands | Gloves (cosmetic) |
| Back | Backpack (capacity) |
| Loadout 1–6 | 1 melee, 2 primary, 3 primary, 4 sidearm, 5 sidearm/bow, 6 throwable |

Loadout is the 6-slot hotbar in the EQUIPPED panel (screenshot 4 shows numbered slots on the right
column). Any weapon can go in any slot except slot 1 (melee only). Hotkeys 1–6.

## Picking up

- Tap F on the nearest item picks it up. Hold F opens a proximity loot list (everything within 2 m).
- Ammo auto-stacks. Picking up a weapon with no free loadout slot swaps it with the currently held one.
- Picking up armor/helmet when a slot is filled swaps if the new one is strictly better, otherwise it
  goes to the bag.
- Death bag: a player who dies drops a **body bag** containing everything they had. Open with F for a
  two-panel transfer UI. Bags despawn after 5 minutes.

## Medical

| Item | Effect | Use time | Notes |
|---|---|---|---|
| Bandage | +15 HP over 10 s, stops bleeding | 2 s | Can be crafted from cloth |
| Field Bandage | +30 HP over 10 s, stops bleeding | 2.5 s | Crafted: 2 bandages + 1 alcohol |
| First Aid Kit | +100 HP over 20 s, stops bleeding | 4 s | Interrupted by taking damage |

Healing is over-time and interrupted by damage (2016 medkit behaviour). You can walk (not sprint)
while a bandage is applying; first aid kit requires standing still.

## Crafting

The CRAFTING column (screenshot 4) is always open beside the inventory. Any recipe whose
ingredients you are carrying lights up; click to craft (2 s). No workbench.

| Recipe | Ingredients | Output |
|---|---|---|
| Shred Cloth | any shirt/pants/hat item ×1 | Cloth ×2 |
| Bandage | Cloth ×2 | Bandage ×1 |
| Field Bandage | Bandage ×2, Rubbing Alcohol ×1 | Field Bandage ×1 |
| Makeshift Helmet | Metal Scrap ×3, Duct Tape ×1 | Makeshift Helmet |
| Makeshift Plated Armor | Metal Sheet ×2, Duct Tape ×2 | Makeshift Plated Armor |
| Flaming Arrow | Arrow ×1, Cloth ×1, Ethanol ×1 | Flaming Arrow ×1 |
| Explosive Arrow | Arrow ×1, Gunpowder ×1, Duct Tape ×1 | Explosive Arrow ×1 |
| Molotov Cocktail | Ethanol ×1, Cloth ×1, Empty Bottle ×1 | Molotov |
| Gas Can (refuel) | Empty Gas Can ×1 at a gas pump | Gas Can (full) |
| Arrow | Wood Stick ×1, Metal Scrap ×1 | Arrow ×2 |

Crafting materials (cloth, scrap, sheet, duct tape, ethanol, gunpowder, bottle, alcohol) spawn in
garages, sheds, and industrial POIs. Makeshift gear is deliberately worse than found gear: it is the
answer to "I landed in the forest."

## Loot tables

See `design/data/loot-tables.json`. Structure:

- **Node classes**: `residential`, `commercial`, `industrial`, `police`, `military`, `hunting`,
  `vehicle_trunk`, `airdrop`.
- Each node rolls `0–2` items with a per-class chance table. Military and police roll higher tiers.
- Guarantees per POI: each police station has ≥1 AR-15 or AK; each military tent cluster ≥1 hunting
  rifle; each city block ≥2 helmets.
- The match seed drives all rolls; loot is identical for all players in that match (no per-client
  differences).

## Vehicle inventory

Vehicles have a trunk (capacity 600) shown as the VEHICLE panel, and a small INTERIOR/glove-box
panel (capacity 100) (screenshot 4). Passengers can access both while inside. Trunks are looted from
outside with F at the rear.

## Item icons

Icons are 2D painted sprites on dark tiles with a small quantity badge and a rarity outline. Hotbar
numbers are rendered in the tile's top-right corner in red (matching the reference).
