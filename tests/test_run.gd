extends TestCase
## Map, talismans, run outcomes, shop/rest/events, heat and run-level bot.

var profile: Profile


func before_each() -> void:
	profile = Profile.new_player(db)


func _run(seed_in: int = 1, heat: int = 0) -> RunState:
	return RunState.start(db, profile, RunState.default_picks(db, profile), seed_in, heat)


func test_map_every_node_reachable_and_ends_in_boss() -> void:
	# Without jumps: every node but a sealed vault is reachable, and every node
	# (vaults included) still has a way up, so there are no dead ends.
	for s in 20:
		var m := RunMap.generate(db, GameRng.new(s))
		var seen := {}
		var frontier: Array = m.start_nodes()
		while not frontier.is_empty():
			var id: int = frontier.pop_back()
			if seen.has(id):
				continue
			seen[id] = true
			frontier.append_array(m.node(id)["next"])
		check(seen.has(m.nodes.back()["id"]), "seed %d boss reachable" % s)
		eq(m.nodes.back()["type"], "boss", "seed %d last node" % s)
		for n in m.nodes:
			if n["type"] != "boss":
				check(not n["next"].is_empty(), "seed %d node %d dead end" % [s, n["id"]])
			eq(seen.has(n["id"]), n["type"] != "vault", "seed %d node %d reachable unless a vault" % [s, n["id"]])
			if n["type"] in ["fight", "elite", "boss"]:
				check(n["encounter"] != "", "seed %d node %d has no encounter" % [s, n["id"]])


func test_map_walls_are_short_and_really_cut() -> void:
	var vaults := 0
	var walls := 0
	for s in 20:
		var m := RunMap.generate(db, GameRng.new(s))
		walls += m.walls.size()
		for w in m.walls:
			var span := Vector2(w["a"][0], w["a"][1]).distance_to(Vector2(w["b"][0], w["b"][1]))
			check(span <= (0.51 if w["kind"] == "h" else 1.65), "seed %d wall too long" % s)
			for n in m.nodes:
				for to in n["next"]:
					check(not m.cut_by(n["id"], to, w), "seed %d link %d-%d runs through a wall" % [s, n["id"], to])
		for n in m.nodes:
			if n["type"] == "vault":
				vaults += 1
				var below: Array = m.rows[int(n["row"]) - 1]
				check(below.any(func(x: int) -> bool: return m.node(x)["type"] != "vault" and n["id"] in m.jump_targets(x)), "seed %d vault %d is one jump from a walkable node" % [s, n["id"]])
	check(walls >= 40 and walls <= 100, "about 2-5 walls per map, got %d in 20 maps" % walls)
	check(vaults >= 3 and vaults <= 40, "vaults are rare, got %d in 20 maps" % vaults)


func test_jumps_need_the_upgrade() -> void:
	var r := _run()
	r.enter(r.available_nodes()[0])
	eq(r.jumps_left(), 0, "new runs have no jumps")
	eq(r.jump_moves(), [], "no jump without the upgrade")
	r.perks.append("packet_hop")
	eq(r.jumps_left(), 2, "Packet Hop gives 2 per layer")
	r.rig["ghost_routing"] = 2
	eq(r.jumps_left(), 4, "rig ranks add jumps")


func test_jump_goes_up_through_walls_and_plays_the_node() -> void:
	for s in 30:
		var r := _run(s)
		r.perks.append("packet_hop")
		# Walk normal links until a jump is on offer.
		r.enter(r.available_nodes()[0])
		while r.jump_moves().is_empty() and not r.map.node(r.node_id)["next"].is_empty() and r.map.node(r.node_id)["row"] < 8:
			r.enter(r.map.node(r.node_id)["next"][0])
		if r.jump_moves().is_empty():
			continue
		var from := r.node_id
		var to: int = r.jump_moves()[0]
		check(to not in r.map.node(from)["next"], "jump targets have no normal link")
		eq(int(r.map.node(to)["row"]), int(r.map.node(from)["row"]) + 1, "jump goes up one floor")
		var node := r.enter(to)
		eq(node["id"], to, "you land on (and play) the jump target")
		eq(r.jumps_left(), 1, "one jump spent")
		check(r.was_jump(r.path.size() - 1), "trail marks the jump")
		var r2 := RunState.from_dict(db, JSON.parse_string(JSON.stringify(r.to_dict())))
		eq(r2.jumps_left(), 1, "jumps saved")
		eq(r2.map.walls.size(), r.map.walls.size(), "walls saved")
		return
	check(false, "no jump found in 30 runs")


func test_vault_pays_a_rare_implant_and_creds() -> void:
	var r := _run()
	var gold := r.gold
	var v := r.open_vault()
	check(v["talisman"] != "" and v["talisman"] in r.talismans, "vault implant added")
	eq(str(db.talismans[v["talisman"]]["rarity"]), "rare", "vault implant is rare")
	eq(r.gold, gold + int(v["gold"]), "vault creds added")


func test_map_is_deterministic() -> void:
	eq(RunMap.generate(db, GameRng.new(4)).ascii(), RunMap.generate(db, GameRng.new(4)).ascii())


func test_enter_only_reachable_nodes() -> void:
	var r := _run()
	var start: Array = r.available_nodes()
	r.enter(start[0])
	eq(r.floor_num, 1)
	check(start[0] not in r.available_nodes(), "can re-enter same node")


func test_talisman_combat_start_and_kill() -> void:
	var c := Combat.create(db, db.make_deck(["jab"]), "mites", GameRng.new(1), -1, {"talismans": ["oak_token", "bone_dice"]})
	c.start()
	check(c.player.ward >= 8, "oak token ward")
	c.energy = 0
	c.enemies[0].hp = 1
	c.enemies[0].ward = 0
	c.deal_damage(c.enemies[0], 5)
	eq(c.energy, 1, "bone dice energy on kill")


func test_talisman_every_n_cards() -> void:
	var c := Combat.create(db, [], "mites", GameRng.new(1), -1, {"talismans": ["flint_shard"]})
	for e in c.enemies:
		e.hp = 99
	c.energy = 3
	for i in 3:
		c.play_card(give(c, "jab"), 0)
	eq(c.energy, 1, "3 jabs then +1")


func test_talisman_pickup_outcome() -> void:
	var r := _run()
	var hp := r.max_hp
	r.add_talisman("copper_ring")
	eq(r.max_hp, hp + 8)


func test_talisman_text() -> void:
	for id in db.talismans:
		var t := Talismans.describe(db.talismans[id])
		check(t != "" and not "?" in t, "%s text '%s'" % [id, t])


func test_rest_heal_and_upgrade() -> void:
	var r := _run()
	r.hp = 10
	check(r.rest_heal() > 0, "healed")
	check(r.upgrade_card(0), "upgrade to v1")
	eq(r.deck[0].fw, 1)
	check(r.upgrade_card(0), "upgrade to v2")
	eq(r.deck[0].fw, 2)
	check(not r.upgrade_card(0), "(+) waits until the whole deck is v2")
	var auto := RunState.upgrade_candidates(r.deck)
	check(auto.all(func(c: CardInstance) -> bool: return c.fw == 0), "random upgrades pick unupgraded cards first")
	for i in r.deck.size():
		while r.deck[i].fw < 2 and r.upgrade_card(i):
			pass
	check(r.upgrade_card(0), "(+) once the deck is maxed")
	check(r.deck[0].upgraded, "designed upgrade applied")
	check(not r.upgrade_card(0), "nothing past (+)")


func test_shop_buy_and_remove() -> void:
	var r := _run()
	r.gold = 1000
	var shop := r.make_shop()
	eq(shop["cards"].size(), 5)
	var n := r.deck.size()
	check(r.buy(shop["cards"][0], false), "buy")
	check(not r.buy(shop["cards"][0], false), "buy sold item")
	eq(r.deck.size(), n + 1)
	var cost := r.remove_cost
	check(r.remove_card(0), "remove")
	check(r.remove_cost > cost, "remove cost rises")


func test_event_requirements() -> void:
	var r := _run()
	var ev: Dictionary = db.events["wandering_merchant"]
	r.gold = 0
	check(not r.can_choose(ev["choices"][0]), "gold requirement")
	r.gold = 100
	var n := r.deck.size()
	r.choose(ev["choices"][0])
	eq(r.gold, 60)
	eq(r.deck.size(), n + 1)


func test_every_event_choice_applies() -> void:
	for id in db.events:
		for ch in db.events[id]["choices"]:
			var r := _run()
			r.gold = 500
			r.choose(ch)
			check(r.hp > 0, "%s/%s" % [id, ch["label"]])


func test_heat_stacks() -> void:
	var r0 := _run(1, 0)
	var r2 := _run(1, 2)
	check(r2.combat_opts()["enemy_hp_mult"] > r0.combat_opts()["enemy_hp_mult"], "heat raises enemy hp")
	check(r2.combat_opts()["enemy_dmg_mult"] > r0.combat_opts()["enemy_dmg_mult"], "heat raises enemy damage")
	r0.hp = 1
	r2.hp = 1
	check(r2.rest_heal_amount() < r0.rest_heal_amount(), "heat cuts safehouse repairs")


func test_run_bot_completes_runs() -> void:
	for s in 3:
		var res := RunBot.play(db, profile, s)
		check(res["floor"] >= 1, "seed %d no progress" % s)
		check(not res["stuck"], "seed %d stuck at %s" % [s, res])


func test_progression_levels_and_mastery() -> void:
	var r := _run()
	r.floor_num = 39
	r.boss_won = true
	r.acts_cleared = 3
	r.combats_won = 27
	r.card_plays = {"kindle": 12}
	var before_packs := profile.packs_unopened
	var lines := profile.finish_run(db, r)
	check(profile.level() >= 2, "level up: %s" % [lines])
	check(profile.packs_unopened > before_packs, "packs")
	eq(profile.max_heat, 1, "heat unlocked")
	eq(profile.mastery_tier(db, "kindle"), 1, "mastery tier")


func test_profile_v1_migrates() -> void:
	var old := {"version": 1, "collection": {"counts": {"jab": 2}, "dust": 5}, "stats": {"runs": 3}}
	var p := Profile.from_dict(old)
	eq(p.xp, 60, "credited xp")
	eq(p.collection.count("jab"), 2)


func test_act_boss_advances_to_next_act() -> void:
	var r := _run()
	var boss: Dictionary = r.map.nodes.back()
	r.node_id = boss["id"]
	var c := r.start_combat(boss["encounter"])
	c.start()
	for e in c.enemies:
		e.hp = 0
	c._check_end()
	var rew := r.finish_combat(c)
	eq(r.act, 2, "act advanced")
	check(not r.over, "run continues")
	eq(rew.get("act_started", 0), 2)
	check(r.map.act == 2, "act 2 map")
	for n in r.map.nodes:
		if n["encounter"] != "":
			eq(int(db.encounters[n["encounter"]].get("act", 1)), 2, "act 2 encounter")


## Plays a few nodes, saves, restores: the copy must be the same run and play on identically.
func test_run_save_round_trip() -> void:
	var r := _run(7, 2)
	for i in 3:
		r.enter(r.available_nodes()[0])
	r.gold += 33
	r.card_plays["jab"] = 4
	r.deck[0].level_up()
	r.add_card(r.deck[1].def.id)
	var path := "user://test_run.save"
	eq(RunSave.save(r, {"screen": "reward", "choices": ["jab"]}, path), OK, "save")
	var data := RunSave.load_run(db, path)
	check(not data.is_empty(), "loads")
	var r2: RunState = data["run"]
	eq(data["resume"]["screen"], "reward")
	eq(r2.summary(), r.summary(), "summary")
	eq(r2.map.ascii(), r.map.ascii(), "map")
	eq(r2.deck.map(func(c: CardInstance) -> String: return c.key()), r.deck.map(func(c: CardInstance) -> String: return c.key()), "deck")
	eq(r2.available_nodes(), r.available_nodes(), "next nodes")
	check(typeof(r2.node_id) == TYPE_INT and typeof(r2.map.node(r2.node_id)["next"][0]) == TYPE_INT, "ints stay ints")
	var nid: int = r.available_nodes()[0]
	var a := r.enter(nid)
	var b := r2.enter(nid)
	eq(b, a, "same node")
	if a["type"] in ["fight", "elite", "boss"]:
		var c1 := r.start_combat(a["encounter"])
		var c2 := r2.start_combat(b["encounter"])
		c1.start()
		c2.start()
		eq(c2.hand.map(func(c: CardInstance) -> String: return c.key()), c1.hand.map(func(c: CardInstance) -> String: return c.key()), "same opening hand")
	RunSave.clear(path)
	check(not RunSave.exists(path), "cleared")
	eq(RunSave.load_run(db, path), {}, "no save = empty")
