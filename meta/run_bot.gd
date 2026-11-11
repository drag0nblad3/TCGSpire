class_name RunBot
extends RefCounted
## Plays a whole run with simple rules, for tools/sim.gd mode=run and tests.
## Path: prefer rest when hurt, elites when healthy, otherwise fights/events.


static func play(db: CardDB, profile: Profile, seed_in: int, heat: int = 0, job: String = "") -> Dictionary:
	var run := RunState.start(db, profile, RunState.default_picks(db, profile, job), seed_in, heat, job)
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
				if not rewards["cards"].is_empty():
					run.add_card(_best_card(db, rewards["cards"]))
				run.add_talisman(rewards["talisman"])
				if not rewards.get("perks", []).is_empty():
					run.add_perk(_best_perk(rewards["perks"]))
			"rest":
				if run.hp < run.max_hp * 0.65:
					run.rest_heal()
				else:
					run.upgrade_card(_upgrade_target(run))
			"shop":
				var shop := run.make_shop()
				if run.gold >= shop["remove"] and run.deck.size() > 12:
					run.remove_card(_remove_target(run))
				for item in shop["cards"]:
					if run.gold - int(item["price"]) >= 40 and db.card(item["id"]).rarity != "common":
						run.buy(item, false)
			"event":
				var ev := run.pick_event()
				for ch in ev["choices"]:
					if run.can_choose(ch):
						run.choose(ch)
						break
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
		if s > best_score:
			best_score = s
			best = id
	return best


static func _best_card(db: CardDB, ids: Array) -> String:
	var rank := {"common": 1, "uncommon": 2, "rare": 3, "mythic": 4}
	var best: String = ids[0]
	for id in ids:
		if rank.get(db.card(id).rarity, 0) > rank.get(db.card(best).rarity, 0):
			best = id
	return best


## Simple preference: survival first, then tempo, then economy.
static func _best_perk(ids: Array) -> String:
	var order := ["nanite_mesh", "ablative_casing", "boot_shield", "ram_spike", "hot_patch", "wide_bus", "clean_room", "mod_kit", "burst_buffer", "deep_scan", "scavenger", "fence_contact"]
	var best: String = ids[0]
	for id in ids:
		if order.find(id) >= 0 and (order.find(best) < 0 or order.find(id) < order.find(best)):
			best = id
	return best


static func _upgrade_target(run: RunState) -> int:
	for i in run.deck.size():
		var c: CardInstance = run.deck[i]
		if not c.upgraded and c.def.rarity not in ["starter", "curse"]:
			return i
	for i in run.deck.size():
		if not run.deck[i].upgraded and run.deck[i].def.rarity != "curse":
			return i
	return -1


static func _remove_target(run: RunState) -> int:
	for i in run.deck.size():
		if run.deck[i].def.rarity == "curse":
			return i
	for i in run.deck.size():
		if run.deck[i].def.id == "jab":
			return i
	return 0
