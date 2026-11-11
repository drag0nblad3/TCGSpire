class_name RunState
extends RefCounted
## One roguelike run: deck, HP, gold, talismans, map position and heat level.
## Built from the base deck plus a few cards the player picks from their
## collection. All randomness forks from the run seed, so a run replays exactly.

var db: CardDB
var seed_value := 0
var rng: GameRng
var deck: Array = []
var hp := 0
var max_hp := 0
var gold := 0
var floor_num := 0
var heat := 0
var talismans: Array = []
var map: RunMap
var node_id := -1
var path: Array = []
var combats_won := 0
var elites_won := 0
var boss_won := false
var act := 1
var acts_cleared := 0
var over := false
var card_plays: Dictionary = {}
var remove_cost := 0
var outcome_counter := 0
## Talisman ids this player hasn't unlocked yet (excluded from rolls).
var locked_talismans: Array = []
## Subroutines (run perks) loaded this run, in order.
var perks: Array = []
## Permanent progress copied from the profile at start: rig perk ranks and
## firmware cards (every copy of a firmware card joins the deck upgraded).
var rig: Dictionary = {}
var firmware: Dictionary = {}
## Card id -> mod id baked into its firmware (every copy arrives with that mod).
var firmware_mods: Dictionary = {}
var mods_installed := 0
## The job: client faction ("" = freelance) and the crews it runs against.
## Targets are banned (picks and offers) and their enemies show up on the map.
var job := ""
var banned: Array = []


## picks: card ids chosen from the player's collection (must own each one).
## job: client faction id (see Jobs). targets: crews the job runs against
## (default: the client's rivals); their cards are dropped from picks.
static func start(db_in: CardDB, profile: Profile, picks: Array, seed_in: int, heat_in: int = 0, job_in: String = "", targets: Array = []) -> RunState:
	var r := RunState.new()
	r.db = db_in
	r.seed_value = seed_in
	r.rng = GameRng.new(seed_in)
	r.heat = heat_in
	r.job = job_in
	r.banned = targets.duplicate() if not targets.is_empty() else Jobs.banned(db_in, job_in)
	r.rig = profile.rig.duplicate()
	r.firmware = profile.firmware.duplicate()
	r.firmware_mods = profile.firmware_mods.duplicate()
	r.max_hp = int(db_in.balance.get("player", {}).get("max_hp", 60)) + int(r.heat_mod("max_hp", 0)) + int(r.perk_mod("max_hp"))
	r.hp = r.max_hp
	r.gold = int(db_in.balance.get("start_gold", 50)) + int(r.perk_mod("start_gold"))
	r.remove_cost = int(db_in.balance.get("shop", {}).get("remove_base", 50))
	for raw in db_in.balance.get("base_deck", []):
		var bid := str(raw)
		r.deck.append(r.make_card(bid.trim_suffix("+"), bid.ends_with("+")))
	var allowed := profile.starter_picks(db_in)
	var problem := Jobs.check(db_in, job_in, picks.slice(0, allowed), allowed, r.banned)
	if problem != "":
		push_warning("Job '%s': %s" % [job_in, problem])
	var used := {}
	for id in picks.slice(0, allowed):
		if db_in.card(id) != null and db_in.card(id).faction in r.banned:
			continue
		used[id] = int(used.get(id, 0)) + 1
		if used[id] > profile.collection.count(id):
			push_error("Run pick '%s' exceeds owned copies" % id)
			continue
		r.deck.append(r.make_card(id))
	var curse := str(r.heat_mod("start_curse", ""))
	if curse != "":
		r.deck.append(db_in.instance(curse))
	for tid in db_in.talismans:
		if int(db_in.talismans[tid].get("unlock_level", 1)) > profile.level():
			r.locked_talismans.append(tid)
	r.map = RunMap.generate(db_in, r.rng.fork("map:1"), 1, r.banned)
	var start_t := str(db_in.balance.get("start_talisman", ""))
	if start_t != "":
		r.add_talisman(start_t)
	var n_mods := int(r.perk_mod("start_mods"))
	if n_mods > 0:
		RunOutcomes.apply(r, {"op": "mod", "amount": n_mods, "rarity": "common"})
	for i in int(r.perk_mod("start_perks")):
		RunOutcomes.apply(r, {"op": "perk"})
	return r


## Default picks for a quick start: first owned non-starter cards. With a job,
## the client's cards come first and banned factions are skipped.
static func default_picks(db_in: CardDB, profile: Profile, job_in: String = "", targets: Array = []) -> Array:
	var n := profile.starter_picks(db_in)
	var ban := targets if not targets.is_empty() else Jobs.banned(db_in, job_in)
	var out: Array = []
	if job_in != "":
		var need := Jobs.required(db_in, job_in, n)
		for id in profile.collection.owned_ids():
			var c := db_in.card(id)
			if c == null or c.faction != job_in or c.rarity == "starter":
				continue
			for k in profile.collection.count(id):
				if out.size() < need:
					out.append(id)
	for id in db_in.balance.get("default_picks", []):
		var c := db_in.card(id)
		if c != null and c.faction not in ban and profile.collection.count(id) > out.count(id) and out.size() < n:
			out.append(id)
	for id in profile.collection.owned_ids():
		if out.size() >= n:
			break
		if id in out:
			continue
		var c := db_in.card(id)
		if c != null and c.rarity != "starter" and c.faction not in ban:
			out.append(id)
	return out.slice(0, n)


# --- heat ---------------------------------------------------------------------

## Combined value of a heat modifier across all active heat levels.
## Numbers add (multipliers stored as +0.1 = +10%); strings take the last value.
func heat_mod(key: String, default: Variant) -> Variant:
	var levels: Array = db.balance.get("heat", [])
	var v: Variant = default
	for i in mini(heat, levels.size()):
		var mods: Dictionary = levels[i].get("mods", {})
		if mods.has(key):
			v = (float(v) + float(mods[key])) if (default is int or default is float) else mods[key]
	return v


## Heat stat boosts compound: each level's pct multiplies the ones below it.
func heat_mult(key: String) -> float:
	var levels: Array = db.balance.get("heat", [])
	var v := 1.0
	for i in mini(heat, levels.size()):
		v *= 1.0 + float(levels[i].get("mods", {}).get(key, 0.0))
	return v


## Sum of a perk modifier over this run's subroutines and the rig (x rank).
func perk_mod(key: String) -> float:
	var v := 0.0
	for pid in perks:
		v += float(db.perks.get(pid, {}).get("mods", {}).get(key, 0.0))
	for pid in rig:
		v += float(db.perks.get(pid, {}).get("mods", {}).get(key, 0.0)) * int(rig[pid])
	return v


func combat_opts() -> Dictionary:
	return {
		"max_hp": max_hp,
		"talismans": talismans,
		"perks": perks.map(func(pid: String) -> Dictionary: return db.perks[pid]),
		"start_ward": int(perk_mod("start_ward")),
		"enemy_hp_mult": maxf(heat_mult("enemy_hp_pct") * (1.0 + perk_mod("enemy_hp_pct")), 0.5),
		"enemy_might": int(heat_mod("enemy_might", 0)),
		"enemy_dmg_mult": maxf(heat_mult("enemy_dmg_pct"), 0.5),
	}


# --- map ----------------------------------------------------------------------

func available_nodes() -> Array:
	if over:
		return []
	if node_id < 0:
		return map.start_nodes()
	return map.node(node_id)["next"].duplicate()


func current_node() -> Dictionary:
	return {} if node_id < 0 else map.node(node_id)


func enter(id: int) -> Dictionary:
	if id not in available_nodes():
		push_error("Node %d not reachable" % id)
		return {}
	node_id = id
	path.append(id)
	var node := map.node(id)
	floor_num = (act - 1) * map.rows.size() + int(node["row"]) + 1
	return node


# --- combat -------------------------------------------------------------------

func start_combat(encounter_id: String) -> Combat:
	var c := Combat.create(db, deck, encounter_id, rng.fork("combat:%d" % floor_num), hp, combat_opts())
	return c


## Returns rewards: {"gold": int, "cards": [ids], "talisman": id or ""}.
func finish_combat(c: Combat) -> Dictionary:
	hp = c.player.hp
	for id in c.play_counts():
		card_plays[id] = int(card_plays.get(id, 0)) + c.play_counts()[id]
	var rewards := {"gold": 0, "cards": [], "talisman": ""}
	if c.phase != Combat.Phase.WON:
		over = true
		return rewards
	combats_won += 1
	var kind := str(db.encounters.get(c.encounter_id, {}).get("kind", "normal"))
	var g: Array = db.balance.get("gold", {}).get(kind, [10, 20])
	rewards["gold"] = int(rng.fork("gold:%d" % floor_num).range_i(int(g[0]), int(g[1])) * (1.0 + perk_mod("gold_pct")))
	gold += rewards["gold"]
	var mend := int(perk_mod("combat_heal"))
	if mend > 0:
		var before_hp := hp
		hp = mini(max_hp, hp + mend)
		rewards["healed"] = hp - before_hp
	rewards["cards"] = reward_choices(kind)
	if kind == "elite" or (kind == "boss" and act < total_acts()):
		rewards["perks"] = perk_choices(int(db.balance.get("perk_choices", 3)) + int(perk_mod("perk_choices")), rng.fork("perks:%d" % floor_num))
	if kind == "elite":
		elites_won += 1
		rewards["talisman"] = roll_talisman("", rng.fork("elite_t:%d" % floor_num))
	if kind == "boss":
		acts_cleared += 1
		rewards["talisman"] = roll_talisman("boss", rng.fork("boss_t:%d" % act))
		if act < total_acts():
			_next_act()
			rewards["act_started"] = act
		else:
			boss_won = true
			over = true
	return rewards


func total_acts() -> int:
	return int(db.balance.get("acts", 1))


func _next_act() -> void:
	act += 1
	node_id = -1
	path = []
	map = RunMap.generate(db, rng.fork("map:%d" % act), act, banned)
	var before := hp
	hp = mini(max_hp, hp + int((max_hp - hp) * float(db.balance.get("act_heal_pct", 0.5))))
	if hp < before:
		hp = before


func reward_choices(kind: String = "normal") -> Array:
	return Packs.reward_choices(db, rng.fork("reward:%d" % floor_num), kind, int(perk_mod("reward_choices")) if kind != "shop" else 0, banned)


## New card for this run's deck (firmware cards arrive upgraded).
func make_card(id: String, upgraded: bool = false) -> CardInstance:
	var c := db.instance(id, upgraded or firmware.has(id))
	if c != null and firmware_mods.has(id) and CardMods.can_apply(db.mod(firmware_mods[id]), c):
		c.mod = db.mod(firmware_mods[id])
	return c


func add_card(id: String) -> void:
	deck.append(make_card(id))


# --- perks (subroutines) ------------------------------------------------------

## Up to n distinct run perks you don't have yet.
func perk_choices(n: int, r: GameRng) -> Array:
	var pool := Perks.ids(db, "run").filter(func(id: String) -> bool: return id not in perks)
	r.shuffle(pool)
	return pool.slice(0, n)


## Loads a subroutine. Returns log lines for the UI (empty if it can't be loaded).
func add_perk(id: String) -> Array:
	if id == "" or id in perks or db.perks.get(id, {}).get("scope", "") != "run":
		return []
	perks.append(id)
	var lines: Array = ["Loaded %s" % db.perks[id]["name"]]
	for o in db.perks[id].get("pickup", []):
		var line := RunOutcomes.apply(self, o)
		if line != "":
			lines.append(line)
	return lines


# --- card mods ----------------------------------------------------------------

## rarity "" = weighted roll from balance.mod_weights.
func roll_mod(rarity: String, r: GameRng) -> String:
	if rarity == "":
		rarity = str(r.weighted(db.balance.get("mod_weights", {"common": 1})))
	var pool := db.mods.keys().filter(func(id: String) -> bool: return db.mods[id].get("rarity", "") == rarity)
	pool.sort()
	return str(r.pick(pool)) if not pool.is_empty() else ""


## Deck indices of cards that can take this mod.
func mod_targets(mod_id: String) -> Array:
	var m := db.mod(mod_id)
	var out: Array = []
	for i in deck.size():
		if CardMods.can_apply(m, deck[i]):
			out.append(i)
	return out


func install_mod(deck_idx: int, mod_id: String) -> bool:
	if deck_idx < 0 or deck_idx >= deck.size() or not CardMods.can_apply(db.mod(mod_id), deck[deck_idx]):
		return false
	deck[deck_idx].mod = db.mod(mod_id)
	mods_installed += 1
	return true


## Distinct mods offered at a safehouse ("tinker"); each fits at least one card.
func mod_choices(n: int, r: GameRng) -> Array:
	var out: Array = []
	for i in n * 6:
		if out.size() >= n:
			break
		var mid := roll_mod("", r)
		if mid != "" and mid not in out and not mod_targets(mid).is_empty():
			out.append(mid)
	return out


# --- talismans ----------------------------------------------------------------

func add_talisman(id: String) -> void:
	if id == "" or id in talismans or not db.talismans.has(id):
		return
	talismans.append(id)
	for o in db.talismans[id].get("pickup", []):
		RunOutcomes.apply(self, o)


## rarity "" = weighted roll from balance.talisman_weights.
func roll_talisman(rarity: String, r: GameRng) -> String:
	if rarity == "":
		rarity = str(r.weighted(db.balance.get("talisman_weights", {"common": 1})))
	var pool: Array = []
	for id in db.talismans:
		var t: Dictionary = db.talismans[id]
		if t.get("rarity", "") == rarity and id not in talismans and id not in locked_talismans:
			pool.append(id)
	pool.sort()
	if pool.is_empty() and rarity != "common":
		return roll_talisman("common", r)
	return str(r.pick(pool)) if not pool.is_empty() else ""


# --- rest / shop / events -----------------------------------------------------

func rest_heal_amount() -> int:
	var pct := float(db.balance.get("rest_heal_pct", 0.3)) * (1.0 + float(heat_mod("rest_heal_pct", 0.0)) + perk_mod("rest_heal_pct"))
	return mini(max_hp - hp, int(max_hp * pct))


func rest_heal() -> int:
	var amt := rest_heal_amount()
	hp += amt
	return amt


func upgrade_card(deck_idx: int) -> bool:
	if deck_idx < 0 or deck_idx >= deck.size():
		return false
	var card: CardInstance = deck[deck_idx]
	if card.upgraded or card.def.rarity == "curse":
		return false
	card.upgraded = true
	return true


## {"cards": [{"id", "price"}], "talismans": [{"id", "price"}], "remove": price}
func make_shop() -> Dictionary:
	var cfg: Dictionary = db.balance.get("shop", {})
	var r := rng.fork("shop:%d" % floor_num)
	var prices: Dictionary = cfg.get("card_price", {})
	var off := clampf(1.0 - perk_mod("shop_discount_pct"), 0.3, 1.0)
	var cards: Array = []
	for id in Packs.reward_choices(db, r, "shop", 0, banned):
		var c := db.card(id)
		cards.append({"id": id, "price": int((int(prices.get(c.rarity, 50)) + r.range_i(-5, 5)) * off)})
	var tal: Array = []
	for i in 2:
		var tid := roll_talisman("", r)
		if tid != "" and db.talismans[tid]["rarity"] != "boss" and tid not in tal.map(func(x: Dictionary) -> String: return x["id"]):
			var tp: Dictionary = cfg.get("talisman_price", {})
			tal.append({"id": tid, "price": int(int(tp.get(db.talismans[tid]["rarity"], 150)) * off)})
	var mods: Array = []
	var mp: Dictionary = cfg.get("mod_price", {})
	for mid in mod_choices(int(cfg.get("mod_count", 2)), r):
		mods.append({"id": mid, "price": int(int(mp.get(db.mods[mid]["rarity"], 60)) * off)})
	return {"cards": cards, "talismans": tal, "mods": mods, "remove": remove_price()}


## What deleting a program costs right now (rig perks can discount it).
func remove_price() -> int:
	return maxi(remove_cost - int(perk_mod("remove_discount")), 0)


## Buys a shop mod and installs it on deck[deck_idx].
func buy_mod(item: Dictionary, deck_idx: int) -> bool:
	if gold < int(item["price"]) or item.get("sold", false):
		return false
	if not install_mod(deck_idx, item["id"]):
		return false
	gold -= int(item["price"])
	item["sold"] = true
	return true


func buy(item: Dictionary, is_talisman: bool) -> bool:
	if gold < int(item["price"]) or item.get("sold", false):
		return false
	gold -= int(item["price"])
	item["sold"] = true
	if is_talisman:
		add_talisman(item["id"])
	else:
		add_card(item["id"])
	return true


func remove_card(deck_idx: int) -> bool:
	if gold < remove_price() or deck_idx < 0 or deck_idx >= deck.size():
		return false
	gold -= remove_price()
	deck.remove_at(deck_idx)
	remove_cost += int(db.balance.get("shop", {}).get("remove_step", 25))
	return true


func pick_event() -> Dictionary:
	var ids := db.events.keys()
	ids.sort()
	var id: String = rng.fork("event:%d" % floor_num).pick(ids)
	return db.events[id]


func can_choose(choice: Dictionary) -> bool:
	var req: Dictionary = choice.get("requires", {})
	return gold >= int(req.get("gold", 0)) and hp > int(req.get("hp", 0))


## Applies an event choice. Returns log lines for the UI.
func choose(choice: Dictionary) -> Array:
	var lines: Array = []
	if not can_choose(choice):
		return lines
	for o in choice.get("outcomes", []):
		var line := RunOutcomes.apply(self, o)
		if line != "":
			lines.append(line)
	return lines


func summary() -> String:
	return "act %d floor %d hp %d/%d gold %d deck %d talismans %s perks %s" % [act, floor_num, hp, max_hp, gold, deck.size(), ",".join(talismans), ",".join(perks)]
