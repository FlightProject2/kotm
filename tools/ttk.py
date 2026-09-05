#!/usr/bin/env python3
"""Shots-to-kill / time-to-kill matrix from design/data/weapons.json + armor.json.

Usage: python3 tools/ttk.py
Prints, for every firearm, shots and seconds to kill against: unarmored torso, laminated armor
torso, unhelmeted head, motorcycle helmet head, tactical helmet head. Uses the damage model in
docs/game-plan/06-hit-mechanics-and-gear.md.
"""
import json, os, math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W = json.load(open(os.path.join(ROOT, "design/data/weapons.json")))
A = json.load(open(os.path.join(ROOT, "design/data/armor.json")))
HP = W["playerHp"]
helmets = {h["id"]: h for h in A["helmets"]}
armors = {a["id"]: a for a in A["bodyArmor"]}


def shots_torso(w, armor=None):
    hp, dur, n = HP, (armor["durability"] if armor else 0), 0
    while hp > 0:
        n += 1
        dmg = w["bodyDamage"]
        if armor and dur > 0:
            absorbed = min(dur, dmg * armor["absorbFraction"])
            dur -= absorbed
            dmg -= absorbed
        hp -= dmg
        if n > 50:
            break
    return n


def shots_head(w, helmet=None):
    hp, n, has_helmet = HP, 0, helmet is not None
    while hp > 0:
        n += 1
        dmg = w["headDamage"]
        if has_helmet:
            has_helmet = False
            if not w.get("pierceHelmet"):
                dmg *= helmet["wearerTakesFraction"]
        hp -= dmg
    return n


def ttk(w, shots):
    if shots <= 1:
        return 0.0
    per = 60.0 / w["rpmCap"]
    return round((shots - 1) * per, 2)


cols = ["torso", "torso+lam", "head", "head+moto", "head+tac"]
print(f"{'weapon':<24}" + "".join(f"{c:>16}" for c in cols))
for w in W["weapons"]:
    row = [
        shots_torso(w),
        shots_torso(w, armors["laminated_armor"]),
        shots_head(w),
        shots_head(w, helmets["motorcycle_helmet"]),
        shots_head(w, helmets["tactical_helmet"]),
    ]
    cells = [f"{s} ({ttk(w, s)}s)" for s in row]
    print(f"{w['name']:<24}" + "".join(f"{c:>16}" for c in cells))
