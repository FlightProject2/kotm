extends Node
## Global signal bus. Server logic emits these (through Net) and HUD / FX listen.
## Every signal carries plain data (ids, vectors, strings), never node references,
## so the same payload can travel over the network later.

signal hit_confirmed(kind: String, killed: bool)           # to the shooter
signal damaged(amount: float, from_dir: Vector3, kind: String)  # to the victim
signal kill_feed(killer: String, victim: String, weapon: String, headshot: bool)
signal remain_changed(count: int)
signal toast(text: String)
signal banner(text: String)
signal popup(title: String, subtitle: String)
signal zone_state(phase: int, state: String, seconds_left: float)
signal loot_removed(loot_id: int)
signal loot_added(loot_id: int)
signal inventory_changed(character_id: int)
signal match_started(seed: int)
signal match_ended(won: bool, placement: int, killer: String, weapon: String, headshot: bool)
signal tracer(shooter_id: int, origin: Vector3, velocity: Vector3, weapon_id: String)
signal hit_fx(position: Vector3, normal: Vector3, kind: String)
signal helmet_pop(position: Vector3, helmet_id: String)
signal gunshot(position: Vector3, weapon_id: String, shooter_id: int)
signal local_character_changed(character: Node)
