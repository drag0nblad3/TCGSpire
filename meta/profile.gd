class_name Profile
extends RefCounted
## Everything that persists between runs. Saved as versioned JSON in user://.
## When the format changes: bump SAVE_VERSION and add a step to _migrate().
##
## Long-term progression:
##   xp/level  -> each level grants packs and unlocks (balance.levels)
##   mastery   -> playing a card N times grants dust, then a foil copy
##   max_heat  -> beating the boss at heat N unlocks heat N+1

const SAVE_VERSION := 2
const DEFAULT_PATH := "user://profile.json"

var collection := Collection.new()
var unlocks: Dictionary = {}
var stats: Dictionary = {"runs": 0, "wins": 0, "packs_opened": 0, "best_floor": 0}
var packs_unopened := 0
var xp := 0
var mastery: Dictionary = {}  # card id -> total plays
var max_heat := 0
## Last deck picks, so the picker remembers them.
var last_picks: Array = []
## UI preferences, e.g. {"theme": "archive"}. Optional field, no migration needed.
var settings: Dictionary = {}


static func new_player(db: CardDB) -> Profile:
	var p := Profile.new()
	var start: Dictionary = db.balance.get("starter_collection", {})
	for id in start:
		p.collection.add(id, int(start[id]))
	return p


# --- progression ------------------------------------------------------------

## Level from total XP. Level n needs xp_per_level * n * (n - 1) / 2 total XP.
func level() -> int:
	return level_for_xp(xp)


static func level_for_xp(total: int) -> int:
	var per := 100
	var lvl := 1
	while total >= per * lvl * (lvl + 1) / 2:
		lvl += 1
	return lvl


static func xp_for_level(lvl: int) -> int:
	return 100 * lvl * (lvl - 1) / 2


func starter_picks(db: CardDB) -> int:
	return int(db.balance.get("starter_picks", 4)) + int(unlocks.get("extra_picks", 0))


## Applies the end of a run. Returns lines describing everything gained.
func finish_run(db: CardDB, run: RunState) -> Array:
	var lines: Array = []
	stats["runs"] = int(stats.get("runs", 0)) + 1
	stats["best_floor"] = maxi(int(stats.get("best_floor", 0)), run.floor_num)
	if run.boss_won:
		stats["wins"] = int(stats.get("wins", 0)) + 1
		if run.heat >= max_heat:
			max_heat = run.heat + 1
			lines.append("Heat %d unlocked" % max_heat)
	var cfg: Dictionary = db.balance.get("run_rewards", {})
	var gained_xp := run.floor_num * int(cfg.get("xp_per_floor", 5)) + run.elites_won * int(cfg.get("xp_per_elite", 15)) \
		+ run.acts_cleared * int(cfg.get("xp_per_act", 40))
	if run.boss_won:
		gained_xp += int(cfg.get("xp_boss", 60))
	gained_xp = int(gained_xp * (1.0 + 0.1 * run.heat))
	var packs := run.combats_won / maxi(int(cfg.get("combats_per_pack", 3)), 1) + (int(cfg.get("boss_packs", 2)) if run.boss_won else 0)
	packs_unopened += packs
	lines.append("+%d XP, +%d pack%s" % [gained_xp, packs, "" if packs == 1 else "s"])
	lines.append_array(add_xp(db, gained_xp))
	lines.append_array(add_mastery(db, run.card_plays))
	return lines


func add_xp(db: CardDB, amount: int) -> Array:
	var lines: Array = []
	var before := level()
	xp += amount
	var rewards: Dictionary = db.balance.get("levels", {})
	for lvl in range(before + 1, level() + 1):
		lines.append("Level %d!" % lvl)
		var r: Dictionary = rewards.get(str(lvl), rewards.get("default", {}))
		if r.has("packs"):
			packs_unopened += int(r["packs"])
			lines.append("  +%d pack%s" % [int(r["packs"]), "" if int(r["packs"]) == 1 else "s"])
		if r.has("dust"):
			collection.dust += int(r["dust"])
			lines.append("  +%d dust" % int(r["dust"]))
		if r.has("extra_picks"):
			unlocks["extra_picks"] = int(unlocks.get("extra_picks", 0)) + int(r["extra_picks"])
			lines.append("  +1 starting pick")
		if r.has("note"):
			lines.append("  " + str(r["note"]))
	return lines


## Mastery tiers from balance.mastery: [{"plays": 10, "dust": 20}, ..., {"plays": 60, "foil": true}]
func add_mastery(db: CardDB, plays: Dictionary) -> Array:
	var lines: Array = []
	var tiers: Array = db.balance.get("mastery", [])
	for id in plays:
		var card := db.card(id)
		if card == null or card.rarity in ["starter", "curse"]:
			continue
		var before := int(mastery.get(id, 0))
		var after := before + int(plays[id])
		mastery[id] = after
		for t in tiers:
			if before < int(t["plays"]) and after >= int(t["plays"]):
				if t.has("dust"):
					collection.dust += int(t["dust"])
				if t.get("foil", false):
					collection.add(id, 1, true)
				lines.append("Mastery: %s reached %d plays%s" % [card.name, int(t["plays"]), " (foil copy!)" if t.get("foil", false) else ""])
	return lines


func mastery_tier(db: CardDB, id: String) -> int:
	var n := int(mastery.get(id, 0))
	var tier := 0
	for t in db.balance.get("mastery", []):
		if n >= int(t["plays"]):
			tier += 1
	return tier


func open_pack(db: CardDB, rng: GameRng) -> Array:
	if packs_unopened <= 0:
		return []
	packs_unopened -= 1
	stats["packs_opened"] = int(stats.get("packs_opened", 0)) + 1
	var cards := Packs.open(db, rng)
	for c in cards:
		collection.add(c["id"], 1, c["foil"])
	return cards


# --- persistence --------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"collection": collection.to_dict(),
		"unlocks": unlocks,
		"stats": stats,
		"packs_unopened": packs_unopened,
		"xp": xp,
		"mastery": mastery,
		"max_heat": max_heat,
		"last_picks": last_picks,
		"settings": settings,
	}


static func from_dict(d: Dictionary) -> Profile:
	d = _migrate(d)
	var p := Profile.new()
	p.collection = Collection.from_dict(d.get("collection", {}))
	p.unlocks = d.get("unlocks", {})
	for k in d.get("stats", {}):
		p.stats[k] = int(d["stats"][k])
	p.packs_unopened = int(d.get("packs_unopened", 0))
	p.xp = int(d.get("xp", 0))
	for k in d.get("mastery", {}):
		p.mastery[k] = int(d["mastery"][k])
	p.max_heat = int(d.get("max_heat", 0))
	p.last_picks = d.get("last_picks", [])
	p.settings = d.get("settings", {})
	return p


static func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	if v < 2:
		# v2 added progression. Credit old players some XP for runs already played.
		d["xp"] = int(d.get("stats", {}).get("runs", 0)) * 20
		d["mastery"] = {}
		d["max_heat"] = 0
		v = 2
	d["version"] = v
	return d


func save(path: String = DEFAULT_PATH) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	# Write-then-rename so a crash mid-save never corrupts the profile.
	return DirAccess.rename_absolute(tmp, path)


static func load_or_new(db: CardDB, path: String = DEFAULT_PATH) -> Profile:
	if not FileAccess.file_exists(path):
		return new_player(db)
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if v is Dictionary:
		return from_dict(v)
	push_error("Corrupt profile at %s, starting fresh" % path)
	return new_player(db)
