class_name RunBot
extends RefCounted
## Plays a whole run with simple rules, for tools/sim.gd mode=run and tests.
## Path: prefer rest when hurt, elites when healthy, otherwise fights/events.
## Card picks, upgrades, shop buys and event choices use cheap static value
## estimates (card_value, _outcome_value), so it stays fast.


static func play(db: CardDB, profile: Profile, seed_in: int, heat: int = 0, job: String = "") -> Dictionary:
	var targets := Jobs.targets(db, job, Jobs.extra_targets(db, heat), GameRng.new(seed_in).fork("job")) if job != "" else []
	var run := RunState.start(db, profile, best_picks(db, profile, job, targets), seed_in, heat, job, targets)
	var died_to := ""
	var steps := 0
	while not run.over and steps < 80:
		steps += 1
		var options := run.available_nodes()
		if options.is_empty():
			break
		var node := run.enter(_choose_node(run, options))
		match node["type"]:
			"fight", "elite", "boss":
				var c := run.start_combat(node["encounter"])
				Bot.run_combat(c)
				var rewards := run.finish_combat(c)
				if c.phase != Combat.Phase.WON:
					died_to = node["encounter"]
					break
				var pick := _pick_reward(run, rewards["cards"])
				if pick != "":
					run.add_card(pick)
				run.add_talisman(rewards["talisman"])
				if not rewards.get("perks", []).is_empty():
					run.add_perk(_best_perk(rewards["perks"]))
			"rest":
				if run.hp < run.max_hp * 0.6 or (run.hp < run.max_hp * 0.8 and run.rest_heal_amount() >= 18):
					run.rest_heal()
				elif _upgrade_target(run) >= 0:
					run.upgrade_card(_upgrade_target(run))
				else:
					var mods := run.mod_choices(2, run.rng.fork("tinker:%d" % run.floor_num))
					if not mods.is_empty():
						run.install_mod(_mod_target(run, mods[0]), mods[0])
			"shop":
				var shop := run.make_shop()
				if run.gold >= shop["remove"] and run.deck.size() > 12:
					run.remove_card(_remove_target(run))
				var items: Array = shop["cards"].duplicate()
				items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return card_value(db.card(a["id"])) > card_value(db.card(b["id"])))
				for item in items:
					if run.gold - int(item["price"]) >= 30 and card_value(db.card(item["id"])) >= _deck_bar(run):
						run.buy(item, false)
				for item in shop.get("mods", []):
					var fits := run.mod_targets(item["id"])
					if not fits.is_empty() and run.gold - int(item["price"]) >= 40:
						run.buy_mod(item, _mod_target(run, item["id"]))
			"event":
				var ev := run.pick_event()
				var best_ch: Dictionary = {}
				var best_v := -999.0
				for ch in ev["choices"]:
					if not run.can_choose(ch):
						continue
					var v := 0.0
					for o in ch.get("outcomes", []):
						v += _outcome_value(run, o)
					if v > best_v:
						best_v = v
						best_ch = ch
				if not best_ch.is_empty():
					run.choose(best_ch)
			"treasure":
				run.add_talisman(run.roll_talisman("", run.rng.fork("treasure:%d" % run.floor_num)))
	return {
		"won": run.boss_won,
		"floor": run.floor_num,
		"hp": run.hp,
		"deck": run.deck.size(),
		"died_to": died_to,
		"stuck": not run.over and died_to == "",
		"run": run,
	}


static func _choose_node(run: RunState, options: Array) -> int:
	var hurt := run.hp < run.max_hp * 0.5
	var best: int = options[0]
	var best_score := -999.0
	for id in options:
		var t: String = run.map.node(id)["type"]
		var s: float = {"fight": 2.0, "event": 1.5, "shop": 1.0, "treasure": 3.0, "rest": 0.5, "elite": 1.0, "boss": 0.0}.get(t, 0.0)
		if hurt and t == "rest":
			s += 4.0
		if hurt and t == "elite":
			s -= 3.0
		if not hurt and t == "elite":
			s += 1.5
		if t == "shop" and run.gold >= 120:
			s += 2.0
		if s > best_score:
			best_score = s
			best = id
	return best


## Strongest legal picks from the collection: the client's best cards up to the
## job's quota, then the best of the rest (firmware cards count as upgraded).
static func best_picks(db: CardDB, profile: Profile, job: String, targets: Array) -> Array:
	var n := profile.starter_picks(db)
	var ban := targets if not targets.is_empty() else Jobs.banned(db, job)
	var pool: Array = []
	for id in profile.collection.owned_ids():
		var c := db.card(id)
		if c == null or c.rarity in ["starter", "curse"] or c.faction in ban:
			continue
		for k in mini(profile.collection.count(id), 2):
			pool.append(id)
	var val := func(id: String) -> float: return card_value(db.card(id), profile.firmware.has(id))
	pool.sort_custom(func(a: String, b: String) -> bool: return val.call(a) > val.call(b))
	var out: Array = []
	for id in pool:
		if out.size() < Jobs.required(db, job, n) and db.card(id).faction == job:
			out.append(id)
	for id in pool:
		if out.size() >= n:
			break
		if out.count(id) < pool.count(id):
			out.append(id)
	return out


## Rough worth of a card per RAM, from its effects alone (no combat state).
static func card_value(c: CardDef, upgraded: bool = false) -> float:
	if c == null:
		return 0.0
	var v := 0.0
	for e in c.get_effects(upgraded):
		var n := float(e.get("amount", 0))
		var aoe := 1.7 if str(e.get("to", "")) == "all_enemies" else 1.0
		match str(e.get("op", "")):
			"damage":
				v += n * float(e.get("hits", 1)) * aoe
			"damage_per_ward", "damage_per_status":
				v += 8.0 * aoe
			"ward":
				v += n * 0.85
			"apply":
				var st := str(e.get("status", ""))
				var k := float(e.get("stacks", 1))
				v += k * ({"burn": 2.2, "brittle": 2.5, "weaken": 2.0, "might": 3.0, "regen": 2.0, "thorns": 1.8, "fortify": 8.0, "echo": 6.0, "charge": 1.6, "frail": 0.8, "overcharge": -3.0}.get(st, 1.5)) * aoe
			"draw":
				v += n * 3.5
			"energy":
				v += n * 4.5
			"summon":
				v += float(e.get("atk", 0)) * 3.5 + float(e.get("hp", 0)) * 0.6
			"rally", "grow":
				v += 3.0 + float(e.get("atk", n)) * 2.0
			"heal":
				v += n * 0.7
			"lose_hp":
				v -= n * 0.6
			"add_card":
				v += 3.0
	if c.type == "power":
		v *= 1.6  # lasts the whole fight
	if "exhaust" in c.get_keywords(upgraded) and c.type != "power":
		v *= 0.85
	if "unplayable" in c.get_keywords(upgraded):
		return -10.0
	return v / maxf(c.get_cost(upgraded), 0.6)


## Average worth of the deck's non-curse cards; new cards should beat it.
static func _deck_bar(run: RunState) -> float:
	var total := 0.0
	var n := 0
	for card in run.deck:
		if card.def.rarity != "curse":
			total += card_value(card.def, card.upgraded)
			n += 1
	var bar := total / maxf(n, 1)
	# Bigger decks dilute good draws: be pickier as the deck grows.
	return bar * (0.9 + maxf(run.deck.size() - 14, 0) * 0.04)


static func _pick_reward(run: RunState, ids: Array) -> String:
	var best := ""
	var best_v := 0.0
	for id in ids:
		var v := card_value(run.db.card(id)) * (1.1 if run.db.card(id).faction == run.job else 1.0)
		if v > best_v:
			best_v = v
			best = id
	return best if best != "" and best_v >= _deck_bar(run) * 0.7 else ""


## Event outcomes in rough "HP-equivalent" points.
static func _outcome_value(run: RunState, o: Dictionary) -> float:
	var n := float(o.get("amount", 0))
	var missing := float(run.max_hp - run.hp)
	match str(o.get("op", "")):
		"gold":
			return n * 0.12
		"heal":
			return minf(float(run.max_hp) * float(o["pct"]) if o.has("pct") else n, missing)
		"lose_hp":
			return -n * (1.0 + 2.0 * (1.0 - float(run.hp) / maxf(run.max_hp, 1.0))) if run.hp - n > 8 else -100.0
		"max_hp":
			return n * 1.4
		"add_card":
			var id := str(o.get("card", ""))
			if id != "":
				return -14.0 if run.db.card(id).rarity == "curse" else card_value(run.db.card(id)) - _deck_bar(run)
			return {"common": 1.0, "uncommon": 3.0, "rare": 6.0}.get(str(o.get("rarity", "common")), 2.0)
		"remove_card":
			return 5.0 * maxf(n, 1.0)
		"upgrade":
			return 6.0 * maxf(n, 1.0)
		"mod":
			return 5.0 * maxf(n, 1.0)
		"perk":
			return 12.0
		"talisman":
			return 14.0
	return 0.0


## Card that gains the most from mod_id (prefers high-value cards).
static func _mod_target(run: RunState, mod_id: String) -> int:
	var best := -1
	var best_v := -999.0
	for i in run.mod_targets(mod_id):
		var v := card_value(run.deck[i].def, run.deck[i].upgraded)
		if v > best_v:
			best_v = v
			best = i
	return best


## Simple preference: survival first, then tempo, then economy.
static func _best_perk(ids: Array) -> String:
	var order := ["nanite_mesh", "ablative_casing", "boot_shield", "ram_spike", "hot_patch", "wide_bus", "clean_room", "mod_kit", "burst_buffer", "deep_scan", "scavenger", "fence_contact"]
	var best: String = ids[0]
	for id in ids:
		if order.find(id) >= 0 and (order.find(best) < 0 or order.find(id) < order.find(best)):
			best = id
	return best


## Card whose upgrade adds the most value.
static func _upgrade_target(run: RunState) -> int:
	var best := -1
	var best_gain := 0.0
	for i in run.deck.size():
		var c: CardInstance = run.deck[i]
		if c.upgraded or c.def.rarity == "curse" or c.def.upgrade.is_empty():
			continue
		var gain := card_value(c.def, true) - card_value(c.def, false) + (0.5 if c.def.rarity != "starter" else 0.0)
		if gain > best_gain:
			best_gain = gain
			best = i
	return best


static func _remove_target(run: RunState) -> int:
	var worst := 0
	var worst_v := 999.0
	for i in run.deck.size():
		var v := card_value(run.deck[i].def, run.deck[i].upgraded)
		if v < worst_v:
			worst_v = v
			worst = i
	return worst
