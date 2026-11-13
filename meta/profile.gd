class_name Profile
extends RefCounted
## Everything that persists between runs. Saved as versioned JSON in user://.
## When the format changes: bump SAVE_VERSION and add a step to _migrate().
##
## Long-term progression:
##   xp/level  -> each level grants packs and unlocks (balance.levels)
##   mastery   -> playing a card N times grants dust, then a foil copy
##   copies    -> extra copies (beyond the 2 a deck may hold) are used up to flash firmware levels
##   max_heat  -> beating the boss at heat N unlocks heat N+1
##   rep       -> each run is a faction job (Jobs) that pays that faction's rep
##   rig       -> rep buys ranks of that faction's rig upgrades (permanent perks)
##   firmware  -> enough copies + rep (dust for Street/starter cards) permanently upgrades a card

const SAVE_VERSION := 8
const DEFAULT_PATH := "user://profile.json"

var collection := Collection.new()
var unlocks: Dictionary = {}
var stats: Dictionary = {"runs": 0, "wins": 0, "packs_opened": 0, "best_floor": 0}
var packs_unopened := 0
## Pack shards from elites (balance.run_rewards.shards_per_pack make a pack).
var pack_shards := 0
## Cards added to the collection for the first time and not yet seen in the library: id -> true.
var unseen: Dictionary = {}
## Packs opened since the last rare+ / mythic pull (balance.pack.pity).
var pack_pity: Dictionary = {"rare": 0, "mythic": 0}
var xp := 0
var mastery: Dictionary = {}  # card id -> total plays
var max_heat := 0
## Last deck picks, so the picker remembers them.
var last_picks: Array = []
## UI preferences, e.g. {"theme": "archive"}. Optional field, no migration needed.
var settings: Dictionary = {}
## Faction rep (job currency): faction id -> amount.
var rep: Dictionary = {}
## Rig upgrades (permanent perks): perk id -> rank.
var rig: Dictionary = {}
## Subtracts the v5 price difference on the first respec, by faction.
var _rig_refund_adjustment: Dictionary = {}
## Firmware cards: card id -> true. Every copy starts runs upgraded.
var firmware: Dictionary = {}
## Firmware tier 2: card id -> mod id baked in (needs firmware + mastery tier 2).
var firmware_mods: Dictionary = {}
## Records (see Records): claimed binder pages ("ember:full" -> true), Exploit log ids,
## daily breach {"last": date, "best": score, "scores": {date: score}}.
var binders: Dictionary = {}
var exploits: Dictionary = {}
var daily: Dictionary = {}
## Saved starter-pick loadouts: client crew id -> [picks or [], ...] (Loadouts.SLOTS slots).
var loadouts: Dictionary = {}


static func new_player(db: CardDB) -> Profile:
	var p := Profile.new()
	var start: Dictionary = db.balance.get("starter_collection", {})
	for id in start:
		p.collection.add(id, int(start[id]))
	return p


# --- progression ------------------------------------------------------------

const LEVEL_CAP := 20


## Level from total XP. Level n needs 100 * n * (n - 1) / 2 total XP, up to LEVEL_CAP.
func level() -> int:
	return level_for_xp(xp)


static func level_for_xp(total: int) -> int:
	var per := 100
	var lvl := 1
	while lvl < LEVEL_CAP and total >= per * lvl * (lvl + 1) / 2:
		lvl += 1
	return lvl


static func xp_for_level(lvl: int) -> int:
	return 100 * lvl * (lvl - 1) / 2


func starter_picks(db: CardDB) -> int:
	return int(db.balance.get("starter_picks", 4)) + int(unlocks.get("extra_picks", 0)) + int(unlocks.get("swap_picks", 0))


## The run's basic cards: balance.base_deck minus one basic per swap pick,
## alternating between the basic kinds (Jab, Brace, Jab, ...).
func base_deck(db: CardDB) -> Array:
	var deck: Array = db.balance.get("base_deck", []).map(func(x: Variant) -> String: return str(x))
	var kinds: Array = []
	for id in deck:
		if id not in kinds:
			kinds.append(id)
	for k in int(unlocks.get("swap_picks", 0)):
		for j in kinds.size():
			var id: String = kinds[(k + j) % kinds.size()]
			var at := deck.rfind(id)
			if at >= 0:
				deck.remove_at(at)
				break
	return deck


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
	gained_xp = int(gained_xp * (1.0 + 0.1 * run.heat) * float(cfg.get("xp_mult", 1.0)))
	var packs := run.acts_cleared * int(cfg.get("packs_per_boss", 1))
	if run.boss_won:
		packs += int(cfg.get("packs_full_run", 0))
	packs_unopened += packs
	lines.append("+%d XP, +%d pack%s" % [gained_xp, packs, "" if packs == 1 else "s"])
	lines.append_array(add_shards(db, run.elites_won * int(cfg.get("shards_per_elite", 0))))
	var rep_gain := Jobs.rep_reward(db, run)
	if rep_gain > 0:
		rep[run.job] = rep_of(run.job) + rep_gain
		lines.append("+%d %s from %s" % [rep_gain, Jobs.rep_name(db, run.job), Jobs.info(db, run.job).get("client", run.job)])
	lines.append_array(add_xp(db, gained_xp))
	lines.append_array(add_mastery(db, run.card_plays))
	lines.append_array(Records.finish_run(db, self, run))
	lines.append_array(Records.check_exploits(db, self))
	return lines


func add_xp(db: CardDB, amount: int) -> Array:
	var lines: Array = []
	var before := level()
	xp += amount
	var rewards: Dictionary = db.balance.get("levels", {})
	for lvl in range(before + 1, level() + 1):
		lines.append("Level %d!" % lvl)
		var packs := int(rewards.get("packs", 1))
		if packs > 0:
			packs_unopened += packs
			lines.append("  +%d pack%s" % [packs, "" if packs == 1 else "s"])
		var dust := int(rewards.get("dust_per_level", 0)) * lvl
		if dust > 0:
			collection.dust += dust
			lines.append("  +%d dust" % dust)
		if rewards.get("extra_picks", []).any(func(x: Variant) -> bool: return int(x) == lvl):
			unlocks["extra_picks"] = int(unlocks.get("extra_picks", 0)) + 1
			lines.append("  +1 starting pick")
		if rewards.get("swap_picks", []).any(func(x: Variant) -> bool: return int(x) == lvl):
			unlocks["swap_picks"] = int(unlocks.get("swap_picks", 0)) + 1
			lines.append("  A basic program in your starting deck becomes a pick")
	return lines


## Elite kills drop pack shards; every shards_per_pack of them becomes a pack.
func add_shards(db: CardDB, n: int) -> Array:
	if n <= 0:
		return []
	var per := shards_per_pack(db)
	pack_shards += n
	var made := pack_shards / per
	pack_shards %= per
	packs_unopened += made
	var line := "+%d pack shard%s (%d/%d)" % [n, "" if n == 1 else "s", pack_shards, per]
	if made > 0:
		line += ", shards fused into %d pack%s" % [made, "" if made == 1 else "s"]
	return [line]


static func shards_per_pack(db: CardDB) -> int:
	return maxi(1, int(db.balance.get("run_rewards", {}).get("shards_per_pack", 3)))


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


# --- rig upgrades (permanent perks) ---------------------------------------------

func rep_of(faction: String) -> int:
	return int(rep.get(faction, 0))


## Rep price of the next rank.
func rig_cost(db: CardDB, id: String) -> int:
	return rank_cost(db, id, int(rig.get(id, 0)) + 1)


## Price of rank k (1-based): base cost x balance.rig_rank_cost[k-1].
static func rank_cost(db: CardDB, id: String, k: int) -> int:
	var mults: Array = db.balance.get("rig_rank_cost", [1, 2, 3])
	return int(db.perks.get(id, {}).get("cost", 0)) * int(mults[clampi(k - 1, 0, mults.size() - 1)])


func can_buy_rig(db: CardDB, id: String) -> bool:
	var p: Dictionary = db.perks.get(id, {})
	return p.get("scope", "") == "rig" and int(rig.get(id, 0)) < int(p.get("max_rank", 0)) \
		and rep_of(str(p.get("faction", ""))) >= rig_cost(db, id) and capstone_ready(db, id)


## Capstones unlock once every other rig upgrade of their crew is maxed.
func capstone_ready(db: CardDB, id: String) -> bool:
	var p: Dictionary = db.perks.get(id, {})
	if not p.get("capstone", false):
		return true
	for other in db.perks:
		var o: Dictionary = db.perks[other]
		if other != id and o.get("scope", "") == "rig" and o.get("faction", "") == p.get("faction", "") \
				and int(rig.get(other, 0)) < int(o.get("max_rank", 0)):
			return false
	return true


func buy_rig(db: CardDB, id: String) -> bool:
	if not can_buy_rig(db, id):
		return false
	var f := str(db.perks[id]["faction"])
	rep[f] = rep_of(f) - rig_cost(db, id)
	rig[id] = int(rig.get(id, 0)) + 1
	return true


## Refunds every rank's rep (free respec).
func reset_rig(db: CardDB) -> void:
	for id in rig:
		var p: Dictionary = db.perks.get(id, {})
		var f := str(p.get("faction", ""))
		for k in range(1, int(rig[id]) + 1):
			rep[f] = rep_of(f) + rank_cost(db, id, k)
	for f in _rig_refund_adjustment:
		rep[f] = rep_of(f) - int(_rig_refund_adjustment[f])
	_rig_refund_adjustment.clear()
	rig = {}


# --- firmware (permanent card upgrades) ------------------------------------------

## {"amount": n, "faction": id}; faction "" means it costs dust (Street and starter cards).
func firmware_price(db: CardDB, id: String) -> Dictionary:
	var c := db.card(id)
	if c == null:
		return {"amount": 0, "faction": ""}
	var cfg: Dictionary = db.balance.get("firmware", {})
	var mults: Array = cfg.get("level_cost_mult", [1, 2])
	var mult := float(mults[mini(firmware_level(id), mults.size() - 1)])
	if c.rarity != "starter" and db.factions.has(c.faction):
		return {"amount": int(int(cfg.get("rep_cost", {}).get(c.rarity, 0)) * mult), "faction": c.faction}
	return {"amount": int(int(cfg.get("cost", {}).get(c.rarity, 0)) * mult), "faction": ""}


func firmware_level(id: String) -> int:
	return int(firmware.get(id, 0))


static func firmware_max(db: CardDB) -> int:
	return db.balance.get("firmware", {}).get("scale", [1.25, 1.5]).size()


## Extra copies each firmware level uses up ([] for base/starter cards, which only cost dust).
## Extras are copies beyond the deck limit: the copies you can load into a deck never count.
static func copy_ladder(db: CardDB, id: String) -> Array:
	var c := db.card(id)
	if c == null or c.rarity in ["starter", "curse"]:
		return []
	return db.balance.get("firmware", {}).get("copies", {}).get(c.rarity, [])


## Copies of one pack card a starting deck may hold (balance.deck_copy_limit).
static func deck_limit(db: CardDB) -> int:
	return int(db.balance.get("deck_copy_limit", 2))


## Copies of id you may load into a starting deck.
func deck_copies(db: CardDB, id: String) -> int:
	return mini(collection.count(id), deck_limit(db))


## Copies beyond the deck limit: what firmware levels use up.
func spare_copies(db: CardDB, id: String) -> int:
	return maxi(0, collection.count(id) - deck_limit(db))


## Extra copies the next firmware level of id uses up (0 once maxed or for starters).
func firmware_copies_needed(db: CardDB, id: String) -> int:
	var ladder := copy_ladder(db, id)
	var lvl := firmware_level(id)
	return int(ladder[lvl]) if lvl < ladder.size() else 0


## Has the next firmware level's extra copies (rep/dust may still be short).
func copies_ready(db: CardDB, id: String) -> bool:
	var need := firmware_copies_needed(db, id)
	return need > 0 and spare_copies(db, id) >= need


## Nothing left to collect: firmware maxed and a full deck's worth owned (packs reroll these).
func copies_complete(db: CardDB, id: String) -> bool:
	var ladder := copy_ladder(db, id)
	return not ladder.is_empty() and firmware_level(id) >= ladder.size() and collection.count(id) >= deck_limit(db)


func disenchant(db: CardDB, id: String) -> bool:
	return collection.disenchant(id, db)


func disenchant_foil(db: CardDB, id: String) -> bool:
	return collection.disenchant_foil(id, db)


## Non-starter cards whose next firmware level is ready to flash right now.
func ready_to_flash(db: CardDB) -> Array:
	return collection.owned_ids().filter(func(id: String) -> bool:
		return db.card(id) != null and db.card(id).rarity != "starter" and firmware_block(db, id) == "")


## Firmware status pill for a card: "v1 ready", "v2 max", "v1" or "" (copies show as pips).
func copy_badge(db: CardDB, id: String) -> String:
	var lvl := firmware_level(id)
	if collection.count(id) <= 0:
		return ""
	if firmware_copies_needed(db, id) <= 0:
		return "v%d max" % lvl if lvl > 0 else ""
	if firmware_block(db, id) == "":
		return "v%d ready" % (lvl + 1)
	return "v%d" % lvl if lvl > 0 else ""


## Pips for a card: Vector2i(extras collected toward the next level, extras it needs).
func copy_pips(db: CardDB, id: String) -> Vector2i:
	var need := firmware_copies_needed(db, id)
	if need <= 0 or collection.count(id) <= 0:
		return Vector2i.ZERO
	return Vector2i(mini(spare_copies(db, id), need), need)


## "" if it can be flashed, else the reason why not.
func firmware_block(db: CardDB, id: String) -> String:
	var c := db.card(id)
	if c == null or c.rarity == "curse":
		return "Malware can't be flashed."
	if firmware_level(id) >= firmware_max(db):
		return "Firmware maxed."
	if not collection.owns(id) and c.rarity != "starter":
		return "Own a copy first."
	var need := firmware_copies_needed(db, id)
	if c.rarity != "starter" and spare_copies(db, id) < need:
		return "Collect %d extra cop%s first (%d so far; your %d deck copies don't count)." % [need, "y" if need == 1 else "ies", spare_copies(db, id), deck_limit(db)]
	var price := firmware_price(db, id)
	var have := collection.dust if price["faction"] == "" else rep_of(price["faction"])
	if have < int(price["amount"]):
		return "Not enough %s." % ("dust" if price["faction"] == "" else Jobs.rep_name(db, price["faction"]))
	return ""


func flash_firmware(db: CardDB, id: String) -> bool:
	if firmware_block(db, id) != "":
		return false
	var price := firmware_price(db, id)
	if price["faction"] == "":
		collection.dust -= int(price["amount"])
	else:
		rep[price["faction"]] = rep_of(price["faction"]) - int(price["amount"])
	# The extra copies are used up (plain copies before foils).
	var used := firmware_copies_needed(db, id)
	collection.counts[id] = collection.count(id) - used
	if int(collection.foils.get(id, 0)) > collection.count(id):
		collection.foils[id] = collection.count(id)
	firmware[id] = firmware_level(id) + 1
	return true


## Price of baking a mod into a firmware card: the card's crew rep, or dust.
func firmware_mod_price(db: CardDB, id: String, mod_id: String) -> Dictionary:
	var cfg: Dictionary = db.balance.get("firmware", {})
	var c := db.card(id)
	var r := str(db.mod(mod_id).get("rarity", "common"))
	if c != null and c.rarity != "starter" and db.factions.has(c.faction):
		return {"amount": int(cfg.get("mod_rep_cost", {}).get(r, 60)), "faction": c.faction}
	return {"amount": int(cfg.get("mod_dust_cost", {}).get(r, 120)), "faction": ""}


## "" if the mod can be baked into this card's firmware, else why not.
func firmware_mod_block(db: CardDB, id: String, mod_id: String) -> String:
	var c := db.card(id)
	if c == null or not firmware.has(id):
		return "Flash it to firmware first."
	if not CardMods.can_apply(db.mod(mod_id), CardInstance.new(c, true)):
		return "That mod doesn't fit."
	var need := int(db.balance.get("firmware", {}).get("mod_mastery_tier", 2))
	if c.rarity != "starter" and mastery_tier(db, id) < need:
		var plays := int(db.balance.get("mastery", [])[need - 1].get("plays", 0))
		return "Run it %d times to bake in a mod (%d so far)." % [plays, int(mastery.get(id, 0))]
	var price := firmware_mod_price(db, id, mod_id)
	var have := collection.dust if price["faction"] == "" else rep_of(price["faction"])
	if have < int(price["amount"]):
		return "Not enough %s." % ("dust" if price["faction"] == "" else Jobs.rep_name(db, price["faction"]))
	return ""


## Bakes (or replaces) the mod every copy of this card starts runs with.
func bake_firmware_mod(db: CardDB, id: String, mod_id: String) -> bool:
	if firmware_mod_block(db, id, mod_id) != "" or firmware_mods.get(id, "") == mod_id:
		return false
	var price := firmware_mod_price(db, id, mod_id)
	if price["faction"] == "":
		collection.dust -= int(price["amount"])
	else:
		rep[price["faction"]] = rep_of(price["faction"]) - int(price["amount"])
	firmware_mods[id] = mod_id
	return true


func open_pack(db: CardDB, rng: GameRng) -> Array:
	if packs_unopened <= 0:
		return []
	packs_unopened -= 1
	stats["packs_opened"] = int(stats.get("packs_opened", 0)) + 1
	var cards := Packs.open(db, rng, self)
	for c in cards:
		c["new"] = not collection.owns(c["id"])
		if c["new"]:
			unseen[c["id"]] = true
		var before := copies_ready(db, c["id"])
		collection.add(c["id"], 1, c["foil"])
		c["count"] = collection.count(c["id"])
		# Extra copies just reached the next firmware level (rep/dust may still be needed).
		c["unlocked"] = not before and copies_ready(db, c["id"])
	return cards


# --- saved loadouts ---------------------------------------------------------------

const LOADOUT_SLOTS := 3


## Saved picks for a crew's slot ([] = empty).
func loadout(job: String, slot: int) -> Array:
	var slots: Array = loadouts.get(job, [])
	return slots[slot].duplicate() if slot < slots.size() else []


func save_loadout(job: String, slot: int, picks: Array) -> void:
	var slots: Array = loadouts.get(job, [])
	while slots.size() < LOADOUT_SLOTS:
		slots.append([])
	slots[clampi(slot, 0, LOADOUT_SLOTS - 1)] = picks.duplicate()
	loadouts[job] = slots


## A saved loadout trimmed to what you still own and may pick (cards can be disenchanted).
func usable_loadout(db: CardDB, job: String, slot: int, banned: Array) -> Array:
	var out: Array = []
	for id in loadout(job, slot):
		var c := db.card(str(id))
		if c != null and c.faction not in banned and out.count(id) < deck_copies(db, id) and out.size() < starter_picks(db):
			out.append(id)
	return out


# --- persistence --------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"collection": collection.to_dict(),
		"unlocks": unlocks,
		"stats": stats,
		"packs_unopened": packs_unopened,
		"pack_shards": pack_shards,
		"unseen": unseen,
		"pack_pity": pack_pity,
		"xp": xp,
		"mastery": mastery,
		"max_heat": max_heat,
		"last_picks": last_picks,
		"settings": settings,
		"rep": rep,
		"rig": rig,
		"rig_refund_adjustment": _rig_refund_adjustment,
		"firmware": firmware,
		"firmware_mods": firmware_mods,
		"binders": binders,
		"exploits": exploits,
		"daily": daily,
		"loadouts": loadouts,
	}


static func from_dict(d: Dictionary, db: CardDB = null) -> Profile:
	d = _migrate(d.duplicate(), db)
	var p := Profile.new()
	p.collection = Collection.from_dict(d.get("collection", {}))
	p.unlocks = d.get("unlocks", {})
	for k in d.get("stats", {}):
		p.stats[k] = int(d["stats"][k])
	p.packs_unopened = int(d.get("packs_unopened", 0))
	p.pack_shards = int(d.get("pack_shards", 0))
	p.unseen = d.get("unseen", {}).duplicate()
	var pity: Dictionary = d.get("pack_pity", {})
	p.pack_pity = {"rare": int(pity.get("rare", 0)), "mythic": int(pity.get("mythic", 0))}
	p.xp = int(d.get("xp", 0))
	for k in d.get("mastery", {}):
		p.mastery[k] = int(d["mastery"][k])
	p.max_heat = int(d.get("max_heat", 0))
	p.last_picks = d.get("last_picks", [])
	p.settings = d.get("settings", {})
	for k in d.get("rep", {}):
		p.rep[k] = int(d["rep"][k])
	for k in d.get("rig", {}):
		p.rig[k] = int(d["rig"][k])
	p._rig_refund_adjustment = d.get("rig_refund_adjustment", {}).duplicate()
	var fw: Variant = d.get("firmware", {})
	for id in fw:
		p.firmware[str(id)] = int(fw[id]) if fw is Dictionary else 1
	for id in d.get("firmware_mods", {}):
		p.firmware_mods[str(id)] = str(d["firmware_mods"][id])
	p.binders = d.get("binders", {}).duplicate()
	p.exploits = d.get("exploits", {}).duplicate()
	p.daily = d.get("daily", {}).duplicate(true)
	for f in d.get("loadouts", {}):
		p.loadouts[str(f)] = d["loadouts"][f].duplicate(true)
	return p


static func _migrate(d: Dictionary, db: CardDB) -> Dictionary:
	var v := int(d.get("version", 1))
	if v < 2:
		# v2 added progression. Credit old players some XP for runs already played.
		d["xp"] = int(d.get("stats", {}).get("runs", 0)) * 20
		d["mastery"] = {}
		d["max_heat"] = 0
		v = 2
	if v < 3:
		# v3 added faction rep, rig upgrades and firmware cards; all start empty.
		d["rep"] = {}
		d["rig"] = {}
		d["firmware"] = []
		v = 3
	if v < 4:
		# v4: firmware has levels (id -> 1 or 2). Old flashed cards become level 1.
		var fw := {}
		for id in d.get("firmware", []):
			fw[str(id)] = 1
		d["firmware"] = fw
	if v < 7:
		# Keep the rank and refund value in the faction that sold it.
		var prior: Dictionary = d.get("rig", {})
		var rig_names := {
			"contract_killer": "signal_override",
			"crowd_funding": "contract_killer",
			"dividend_plan": "reward_reroute",
		}
		var updated := {}
		for id in prior:
			updated[rig_names.get(id, id)] = prior[id]
		d["rig"] = updated
	if v == 5 and not d.get("rig", {}).is_empty():
		_adjust_v5_rig_refunds(d, db if db != null else CardDB.shared())
	if v < 7:
		v = 7
	if v < 8:
		# v8 added records (binders, Exploit log, daily breach) and loadouts; all start empty.
		for k in ["binders", "exploits", "daily", "loadouts"]:
			d[k] = d.get(k, {})
		v = 8
	d["version"] = v
	return d


## Existing v5 ranks carry their discounted refund value. New ranks use v6 prices.
static func _adjust_v5_rig_refunds(d: Dictionary, db: CardDB) -> void:
	var adjustment := {}
	var v5_multipliers := [1, 4, 8]
	var v5_capstones := {
		"thermal_runaway": 300, "liquidity_engine": 225, "regrowth_protocol": 275,
		"absolute_zero": 275, "hive_link": 225, "dead_air_protocol": 225,
	}
	for id in d["rig"]:
		var perk: Dictionary = db.perks.get(id, {})
		if perk.get("scope", "") != "rig":
			continue
		var faction: String = perk["faction"]
		var old_base := int(v5_capstones.get(id, perk["cost"]))
		var ranks := clampi(int(d["rig"][id]), 0, mini(int(perk["max_rank"]), v5_multipliers.size()))
		for rank in range(1, ranks + 1):
			var old_price := old_base * int(v5_multipliers[rank - 1])
			adjustment[faction] = int(adjustment.get(faction, 0)) + rank_cost(db, id, rank) - old_price
	d["rig_refund_adjustment"] = adjustment


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
		return from_dict(v, db)
	push_error("Corrupt profile at %s, starting fresh" % path)
	return new_player(db)
