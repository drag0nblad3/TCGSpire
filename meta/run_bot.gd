class_name RunBot
extends RefCounted
## Plays a whole run with simple rules, for tools/sim.gd mode=run and tests.
## Path: prefer rest when hurt, elites when healthy, otherwise fights/events.
## Card picks, upgrades, shop buys and event choices use cheap static value
## estimates (card_value, _outcome_value), so it stays fast.


## forced: card ids that replace the weakest starter picks (per-card sims).
## stats: optional Dictionary filled with per-card offers, picks and plays
## (card id -> {offered, picked, plays, dmg, ward}) for tools/sim.gd mode=cards.
static func play(db: CardDB, profile: Profile, seed_in: int, heat: int = 0, job: String = "", forced: Array = [], stats = null) -> Dictionary:
	var targets := Jobs.targets(db, job, Jobs.extra_targets(db, heat), GameRng.new(seed_in).fork("job")) if job != "" else []
	var picks := best_picks(db, profile, job, targets)
	if not forced.is_empty():
		picks = picks.filter(func(id: String) -> bool: return id not in forced)
		picks.resize(mini(picks.size(), maxi(profile.starter_picks(db) - forced.size(), 0)))
		picks.append_array(forced)
	var run := RunState.start(db, profile, picks, seed_in, heat, job, targets)
	var died_to := ""
	var fights: Array = []
	var steps := 0
	while not run.over and steps < 80:
		steps += 1
		var options := run.available_nodes()
		if options.is_empty():
			break
		# The bot never jumps (walls never strand a node).
		var up: Array = options.filter(func(id: int) -> bool: return id not in run.jump_moves())
		if not up.is_empty():
			options = up
		var node := run.enter(_choose_node(run, options))
		match node["type"]:
			"fight", "elite", "boss":
				var c := run.start_combat(node["encounter"])
				var act_now := run.act
				var res := Bot.run_combat(c)
				fights.append({"act": act_now, "kind": node["type"], "turns": int(res["turns"]), "won": c.phase == Combat.Phase.WON})
				if stats != null:
					tally_plays(c, stats)
				var rewards := run.finish_combat(c)
				if c.phase != Combat.Phase.WON:
					died_to = node["encounter"]
					break
				var pick := _pick_reward(run, rewards["cards"])
				if pick == "" and run.reward_rerolls_left > 0:
					pick = _pick_reward(run, run.reroll_reward(rewards["kind"], rewards["cards"]))
				if stats != null:
					for id in rewards["cards"]:
						_stat(stats, id)["offered"] += 1
					if pick != "":
						_stat(stats, pick)["picked"] += 1
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
				var choice := _pick_event_choice(run, ev)
				if choice["value"] <= 0.0 and run.event_rerolls_left > 0:
					var replacement := run.reroll_event(ev["id"])
					if not replacement.is_empty():
						choice = _pick_event_choice(run, replacement)
				if not choice["choice"].is_empty():
					run.choose(choice["choice"])
			"treasure":
				run.add_talisman(run.roll_talisman("", run.rng.fork("treasure:%d" % run.floor_num)))
	return {
		"won": run.boss_won,
		"floor": run.floor_num,
		"hp": run.hp,
		"deck": run.deck.size(),
		"died_to": died_to,
		"fights": fights,
		"stuck": not run.over and died_to == "",
		"run": run,
	}


static func _stat(stats: Dictionary, id: String) -> Dictionary:
	if not stats.has(id):
		stats[id] = {"offered": 0, "picked": 0, "plays": 0, "dmg": 0, "ward": 0}
	return stats[id]


## Credits each card play with the enemy damage and Firewall that follow it
## until the next play or the enemy phase (status ticks and daemon rules that
## fire later are not credited, so this undercounts slow cards).
static func tally_plays(c: Combat, stats: Dictionary) -> void:
	var cur: Dictionary = {}
	for e in c.events:
		match e["t"]:
			"play":
				cur = _stat(stats, str(e["card"]).split("#")[0].trim_suffix("+"))
				cur["plays"] += 1
			"enemy_phase", "turn_start":
				cur = {}
			"damage":
				if not cur.is_empty() and str(e["target"]).begins_with("e"):
					cur["dmg"] += int(e["amount"]) + int(e["blocked"])
			"ward":
				if not cur.is_empty() and e["target"] == "player":
					cur["ward"] += int(e["amount"])


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
## job's quota, then the best of the rest (firmware scales a card's value).
static func best_picks(db: CardDB, profile: Profile, job: String, targets: Array) -> Array:
	var n := profile.starter_picks(db)
	var ban := targets if not targets.is_empty() else Jobs.banned(db, job)
	var pool: Array = []
	for id in profile.collection.owned_ids():
		var c := db.card(id)
		if c == null or c.rarity in ["starter", "curse"] or c.banned_by(ban):
			continue
		for k in profile.deck_copies(db, id):
			pool.append(id)
	var scale := db.firmware_scale()
	var val := func(id: String) -> float: return card_value(db.card(id)) * float(scale[mini(profile.firmware_level(id), scale.size() - 1)])
	pool.sort_custom(func(a: String, b: String) -> bool: return val.call(a) > val.call(b))
	var out: Array = []
	for id in pool:
		if out.size() < Jobs.required(db, job, n) and db.card(id).is_of(job):
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
		if e.has("loop"):
			v += float(e["loop"]) * 2.0 * aoe
		match str(e.get("op", "")):
			"cooldown":
				v += n + float(e.get("step", 0)) * 0.5
			"relay_cashout":
				v += 2.0 * float(e.get("mult", 2))
			"compile":
				v += n * 2.0
			"plant", "relay":
				v += n * 0.8
			"handshake", "sequence":
				v += 3.0
			"damage":
				v += n * float(e.get("hits", 1)) * aoe
			"damage_per_ward", "damage_per_status":
				if str(e.get("of", "")) == "target":
					# Reads the enemy's stacks: only as good as the rest of the deck's setup.
					v += (float(e.get("base", 0)) + float(e.get("mult", 1.0)) * 2.0) * aoe
				elif str(e.get("op", "")) == "damage_per_ward":
					v += 8.0 * aoe * minf(float(e.get("mult", 1.0)), 1.0)
				else:
					v += 8.0 * aoe
			"ward":
				v += n * 0.85
			"apply":
				var st := str(e.get("status", ""))
				var k := float(e.get("stacks", 1))
				v += k * ({"burn": 2.2, "brittle": 2.5, "weaken": 2.0, "might": 3.0, "regen": 2.0, "thorns": 1.8, "fortify": 8.0, "charge": 1.6, "frail": 0.8, "overcharge": -3.0, "stall": 6.0}.get(st, 1.5)) * aoe
			"draw":
				v += n * 3.5
			"energy":
				v += n * 4.5
			"summon":
				v += DaemonRules.value(e) * 0.9
			"rally":
				v += 1.0 + n * 1.5
			"heal":
				v += n * 1.2  # HP carries between fights
			"lose_hp":
				v -= n * 0.6
			"add_card":
				v += 3.0
			"amplify":
				v += 2.0 * aoe
			"strip":
				v += 2.0 * aoe
			"sacrifice":
				v += 1.5 * float(e.get("mult", 1.0))  # dead without a daemon up
	if c.get_effects(upgraded).any(func(e: Dictionary) -> bool: return str(e.get("op", "")) == "sacrifice"):
		v *= 0.5  # needs a daemon up
	if c.type == "power":
		v *= 1.6  # lasts the whole fight
	if "exhaust" in c.get_keywords(upgraded) and c.type != "power":
		v *= 0.85
	if "unplayable" in c.get_keywords(upgraded):
		return -10.0
	return v / maxf(c.get_cost(upgraded), 0.6)


## card_value of an instance, including its firmware level.
static func _inst_value(c: CardInstance) -> float:
	return card_value(c.def, c.upgraded) * c.fw_mult()


## Average worth of the deck's non-curse cards; new cards should beat it.
static func _deck_bar(run: RunState) -> float:
	var total := 0.0
	var n := 0
	for card in run.deck:
		if card.def.rarity != "curse":
			total += _inst_value(card)
			n += 1
	var bar := total / maxf(n, 1)
	# Bigger decks dilute good draws: be pickier as the deck grows.
	return bar * (0.9 + maxf(run.deck.size() - 14, 0) * 0.04)


static func _pick_reward(run: RunState, ids: Array) -> String:
	var best := ""
	var best_v := 0.0
	for id in ids:
		var v := card_value(run.db.card(id)) * (1.1 if run.db.card(id).is_of(run.job) else 1.0)
		if v > best_v:
			best_v = v
			best = id
	return best if best != "" and best_v >= _deck_bar(run) * 0.7 else ""


static func _pick_event_choice(run: RunState, ev: Dictionary) -> Dictionary:
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
	return {"choice": best_ch, "value": best_v}


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
	var maxed := RunState.deck_maxed(run.deck)
	for i in run.deck.size():
		var c: CardInstance = run.deck[i]
		if not c.can_level_up(maxed):
			continue
		var after := c.copy()
		after.level_up()
		var gain := _inst_value(after) - _inst_value(c) + (0.5 if c.def.rarity != "starter" else 0.0)
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
