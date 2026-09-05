extends Node
## Player progression (autoload "Progress"): coins, crates, owned cosmetics, daily challenges and
## lifetime stats. Persisted to user://progress.cfg. Match results and local stat events feed it;
## the menus read it. Cosmetic-only: nothing here changes gameplay stats.

signal changed
signal crate_awarded(crate_id: String, reason: String)
signal challenge_completed(challenge: Dictionary)

const PATH := "user://progress.cfg"
const RARITY_WEIGHTS := {"common": 50.0, "uncommon": 28.0, "rare": 14.0, "ultra_rare": 6.0, "legendary": 2.0}
const RARITY_COINS := {"common": 40, "uncommon": 90, "rare": 220, "ultra_rare": 500, "legendary": 1200}
const RARITY_COLORS := {"common": Color("9aa0a6"), "uncommon": Color("4caf50"), "rare": Color("3f8cff"), "ultra_rare": Color("a349e8"), "legendary": Color("e6c25a")}
const CRATES := {
	"hot_shot_crate": {"name": "Hot Shot Crate", "cost": 500, "desc": "One random skin. Legendary flames if you're lucky."},
	"victory_crate": {"name": "Victory Crate", "cost": 0, "desc": "Awarded to the King. Better odds on rare and up."},
}
const CHALLENGE_POOL := [
	{"kind": "kills", "text": "Kill %d opponents", "targets": [1, 3, 5], "coins": [100, 250, 450]},
	{"kind": "matches", "text": "Complete %d matches", "targets": [1, 3], "coins": [80, 220]},
	{"kind": "damage", "text": "Deal %d damage", "targets": [200, 500, 1000], "coins": [120, 260, 500]},
	{"kind": "pickups", "text": "Pick up %d items", "targets": [10, 25], "coins": [60, 140]},
	{"kind": "top10", "text": "Finish top 10 %d times", "targets": [1, 2], "coins": [150, 320]},
	{"kind": "headshots", "text": "Land %d headshots", "targets": [2, 5], "coins": [160, 380]},
	{"kind": "win", "text": "Win %d match", "targets": [1], "coins": [600], "crate": "hot_shot_crate"},
	{"kind": "drive", "text": "Drive %d m in a vehicle", "targets": [500, 1500], "coins": [90, 200]},
]

var coins: int = 300
var crates: Dictionary = {}          # crate id -> count
var owned: Dictionary = {}           # item id -> true
var stats: Dictionary = {"matches": 0, "wins": 0, "kills": 0, "damage": 0.0, "headshots": 0, "top10": 0, "pickups": 0, "drive_m": 0.0, "best_placement": 0}
var dailies: Array = []
var dailies_day: String = ""
var player_name: String = "SUP3R"
var _match_pickups: int = 0

func _ready() -> void:
	_grant_defaults()
	load_progress()
	_ensure_dailies()
	Events.match_ended.connect(_on_match_ended)
	Events.local_stat.connect(_on_local_stat)

# ---------- ownership ----------
func _grant_defaults() -> void:
	var d: Dictionary = SkinSystem.data()
	for it in d["items"]:
		if it.get("rarity", "common") == "common":
			owned[it["id"]] = true
	for w in d["weaponSkins"]:
		if w.get("rarity", "common") == "common" or String(w["id"]).ends_with("_standard"):
			owned[w["id"]] = true
	for k in d["defaultLoadout"]:
		if k != "weapons" and String(d["defaultLoadout"][k]) != "":
			owned[d["defaultLoadout"][k]] = true

func owns(item_id: String) -> bool:
	return item_id == "" or owned.has(item_id)

func rarity_of(item_id: String) -> String:
	var it := SkinSystem.item(item_id)
	if it.is_empty():
		it = SkinSystem.weapon_skin(item_id)
	return String(it.get("rarity", "common"))

# ---------- crates ----------
func crate_count(crate_id: String) -> int:
	return int(crates.get(crate_id, 0))

func give_crate(crate_id: String, reason := "") -> void:
	crates[crate_id] = crate_count(crate_id) + 1
	crate_awarded.emit(crate_id, reason)
	save_progress()
	changed.emit()

func buy_crate(crate_id: String) -> bool:
	var cost := int(CRATES.get(crate_id, {}).get("cost", 999999))
	if coins < cost:
		return false
	coins -= cost
	give_crate(crate_id, "bought")
	return true

## All items a crate can drop (skins and clothing that are not common basics).
func crate_pool() -> Array:
	var pool: Array = []
	var d: Dictionary = SkinSystem.data()
	for it in d["items"]:
		if it.get("rarity", "common") != "common":
			pool.append({"id": it["id"], "name": it["name"], "rarity": it["rarity"], "kind": "item", "slot": it["slot"]})
	for w in d["weaponSkins"]:
		if w.get("rarity", "common") != "common" and not String(w["id"]).ends_with("_standard"):
			pool.append({"id": w["id"], "name": "%s %s" % [ItemCatalog.get_item(w["weapon"]).get("name", w["weapon"]), w["name"]], "rarity": w["rarity"], "kind": "weapon", "weapon": w["weapon"]})
	return pool

## Opens a crate: rolls a rarity by weight (victory crates skip uncommon-and-below half the
## time), then a random item of that rarity. Duplicates refund coins. Returns the drop.
func open_crate(crate_id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	if crate_count(crate_id) <= 0:
		return {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	crates[crate_id] = crate_count(crate_id) - 1
	var pool := crate_pool()
	var weights := RARITY_WEIGHTS.duplicate()
	if crate_id == "victory_crate":
		weights["uncommon"] = 12.0; weights["rare"] = 24.0; weights["ultra_rare"] = 12.0; weights["legendary"] = 5.0
	var total := 0.0
	var by_rarity := {}
	for e in pool:
		var r: String = e["rarity"]
		if not by_rarity.has(r):
			by_rarity[r] = []
		by_rarity[r].append(e)
	for r in weights:
		if by_rarity.has(r):
			total += float(weights[r])
	var pick := rng.randf() * total
	var rarity := "uncommon"
	for r in weights:
		if not by_rarity.has(r):
			continue
		pick -= float(weights[r])
		if pick <= 0.0:
			rarity = r
			break
	var options: Array = by_rarity.get(rarity, pool)
	var drop: Dictionary = options[rng.randi_range(0, options.size() - 1)].duplicate()
	drop["duplicate"] = owned.has(drop["id"])
	if drop["duplicate"]:
		drop["refund"] = int(RARITY_COINS.get(rarity, 40))
		coins += int(drop["refund"])
	else:
		owned[drop["id"]] = true
	save_progress()
	changed.emit()
	return drop

# ---------- dailies ----------
func _ensure_dailies() -> void:
	var today := Time.get_date_string_from_system(true)
	if dailies_day == today and dailies.size() == 4:
		return
	dailies_day = today
	dailies = []
	var rng := RandomNumberGenerator.new()
	rng.seed = today.hash()
	var pool := CHALLENGE_POOL.duplicate()
	for i in 4:
		var idx := rng.randi_range(0, pool.size() - 1)
		var c: Dictionary = pool[idx]
		pool.remove_at(idx)
		var ti := rng.randi_range(0, c["targets"].size() - 1)
		dailies.append({"id": "%s_%d" % [c["kind"], i], "kind": c["kind"], "text": c["text"] % int(c["targets"][ti]),
			"target": int(c["targets"][ti]), "progress": 0, "coins": int(c["coins"][ti]), "crate": String(c.get("crate", "")), "done": false})
	save_progress()

func _advance(kind: String, amount: float) -> void:
	for c in dailies:
		if c["done"] or c["kind"] != kind:
			continue
		c["progress"] = minf(float(c["target"]), float(c["progress"]) + amount)
		if float(c["progress"]) >= float(c["target"]):
			c["done"] = true
			coins += int(c["coins"])
			if String(c["crate"]) != "":
				give_crate(String(c["crate"]), "challenge")
			challenge_completed.emit(c)

# ---------- events ----------
func _on_local_stat(kind: String, amount: float) -> void:
	match kind:
		"kill": stats["kills"] = int(stats["kills"]) + 1; _advance("kills", 1)
		"headshot": stats["headshots"] = int(stats["headshots"]) + 1; _advance("headshots", 1)
		"damage": stats["damage"] = float(stats["damage"]) + amount; _advance("damage", amount)
		"pickup": stats["pickups"] = int(stats["pickups"]) + 1; _advance("pickups", 1)
		"drive": stats["drive_m"] = float(stats["drive_m"]) + amount; _advance("drive", amount)
	changed.emit()

func _on_match_ended(won: bool, placement: int, _killer: String, _weapon: String, _headshot: bool) -> void:
	stats["matches"] = int(stats["matches"]) + 1
	_advance("matches", 1)
	if placement <= 10:
		stats["top10"] = int(stats["top10"]) + 1
		_advance("top10", 1)
	if int(stats["best_placement"]) == 0 or placement < int(stats["best_placement"]):
		stats["best_placement"] = placement
	# match reward: placement pays, the King gets a free crate
	var reward := 50 + maxi(0, 31 - placement) * 6
	if won:
		stats["wins"] = int(stats["wins"]) + 1
		reward += 300
		give_crate("victory_crate", "win")
		_advance("win", 1)
	coins += reward
	save_progress()
	changed.emit()

# ---------- persistence ----------
func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	coins = int(cfg.get_value("wallet", "coins", coins))
	crates = cfg.get_value("wallet", "crates", crates)
	var saved_owned: Dictionary = cfg.get_value("wallet", "owned", {})
	for k in saved_owned:
		owned[k] = true
	stats = cfg.get_value("stats", "stats", stats)
	dailies = cfg.get_value("dailies", "list", dailies)
	dailies_day = String(cfg.get_value("dailies", "day", dailies_day))
	player_name = String(cfg.get_value("profile", "name", player_name))

func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("wallet", "coins", coins)
	cfg.set_value("wallet", "crates", crates)
	cfg.set_value("wallet", "owned", owned)
	cfg.set_value("stats", "stats", stats)
	cfg.set_value("dailies", "list", dailies)
	cfg.set_value("dailies", "day", dailies_day)
	cfg.set_value("profile", "name", player_name)
	cfg.save(PATH)

func reset_for_tests() -> void:
	coins = 300
	crates = {}
	owned = {}
	_grant_defaults()
	stats = {"matches": 0, "wins": 0, "kills": 0, "damage": 0.0, "headshots": 0, "top10": 0, "pickups": 0, "drive_m": 0.0, "best_placement": 0}
	dailies = []
	dailies_day = ""
	_ensure_dailies()
