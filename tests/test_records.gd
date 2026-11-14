extends TestCase
## Records: run tally, contract clauses, Exploit log, binders, daily breach, loadouts, foils.


func _run(job: String = "ember") -> RunState:
	var p := Profile.new_player(db)
	return RunState.start(db, p, RunState.default_picks(db, p, job), 5, 0, job)


func test_tally_reads_fight_events() -> void:
	var run := _run()
	var c := run.start_combat("mites")
	c.start()
	c.energy = 10
	c.hand.append(db.instance("ember_whelp"))
	c.play_card(c.hand.size() - 1)
	Effects.resolve(c, {"op": "apply", "status": "burn", "stacks": 9}, c.player, c.enemies[0])
	Effects.resolve(c, {"op": "ward", "amount": 33}, c.player, null)
	for e in c.enemies:
		e.hp = 0
	c.emit("death", {"target": c.enemies[0].id})
	c._check_end()
	run.finish_combat(c)
	eq(int(run.tally["daemons"]), 1)
	check(int(run.tally["max_burn"]) >= 9, "burn total tracked")
	check(int(run.tally["max_ward"]) >= 33, "Firewall tracked")
	eq(int(run.tally["clean_fights"]), 1, "no HP lost")


func test_clauses_pay_rep_when_met() -> void:
	var p := Profile.new_player(db)
	var run := RunState.start(db, p, RunState.default_picks(db, p, "ember"), 5, 0, "ember")
	run.clauses = ["ghost_protocol", "cold_storage"]
	run.tally = {"clean_fights": 3, "max_ward": 10}
	check(Records.clause_met(db, run, "ghost_protocol"), "3 clean fights")
	check(not Records.clause_met(db, run, "cold_storage"), "only 10 Firewall")
	run.over = true
	var before := p.rep_of("ember")
	var lines := p.finish_run(db, run)
	eq(p.rep_of("ember") - before - Jobs.rep_reward(db, run), Records.clause_rep(db, "ghost_protocol", 0))
	check(lines.any(func(l: String) -> bool: return l.begins_with("Clause met")), "clause line")
	eq(int(p.stats["clauses_met"]), 1)


func test_lean_rig_needs_a_cleared_layer() -> void:
	var run := _run()
	check(not Records.clause_met(db, run, "lean_rig"), "nothing cleared yet")
	run.acts_cleared = 1
	check(Records.clause_met(db, run, "lean_rig") == (run.deck.size() <= 18), "deck size checked")


func test_roll_clauses_is_stable_and_distinct() -> void:
	var a := Records.roll_clauses(db, GameRng.new(3))
	eq(a, Records.roll_clauses(db, GameRng.new(3)))
	eq(a.size(), 2)
	check(a[0] != a[1], "two different clauses")


func test_exploits_unlock_from_lifetime_stats() -> void:
	var p := Profile.new_player(db)
	p.stats["wins"] = 1
	var lines := Records.check_exploits(db, p)
	check(p.exploits.has("first_root"), "first win logged")
	check(not p.exploits.has("pack_rat"), "not earned yet")
	eq(lines.size(), p.exploits.size())
	eq(Records.check_exploits(db, p), [], "logged only once")


func test_binders_claim_once_and_unlock_back() -> void:
	var p := Profile.new_player(db)
	for id in Records.binder_ids(db, "ember", "full"):
		p.collection.add(id)
	var dust := p.collection.dust
	var lines := Records.claim_binders(db, p)
	check(p.binders.has("ember:full") and p.binders.has("ember:common"), "pages claimed")
	check(p.collection.dust > dust, "dust paid")
	check(lines.size() >= 3, "a line per page")
	eq(Records.claim_binders(db, p).filter(func(l: String) -> bool: return "Burner" in l or "ember" in l), [], "no double claim")
	check("ember" in Records.card_backs(p), "crew card back")
	check(Records.title_for("ember") in Records.titles(p), "crew title")


func test_daily_is_fixed_per_date() -> void:
	var a := Records.daily(db, "2026-11-13")
	eq(a, Records.daily(db, "2026-11-13"))
	check(a["job"] in Jobs.board(db), "a real crew")
	check(a["job"] not in a["targets"], "never against itself")
	var b := Records.daily(db, "2026-11-14")
	check(a["seed"] != b["seed"], "new seed tomorrow")


func test_daily_score_recorded_on_finish() -> void:
	var p := Profile.new_player(db)
	var run := _run()
	run.daily = "2026-11-13"
	run.floor_num = 7
	run.over = true
	p.finish_run(db, run)
	eq(int(p.daily["scores"]["2026-11-13"]), 70)
	eq(int(p.daily["best"]), 70)
	eq(int(p.stats["daily_runs"]), 1)


func test_loadouts_save_and_trim() -> void:
	var p := Profile.new_player(db)
	p.save_loadout("ember", 1, ["kindle", "kindle", "shriek"])
	eq(p.loadout("ember", 1), ["kindle", "kindle", "shriek"])
	eq(p.loadout("ember", 0), [])
	# Only owned copies and allowed crews survive.
	var got := p.usable_loadout(db, "ember", 1, ["noise"])
	eq(got, ["kindle", "kindle"])
	var q := Profile.from_dict(p.to_dict(), db)
	eq(q.loadout("ember", 1), ["kindle", "kindle", "shriek"], "saved in the profile")


func test_foil_disenchant_pays_more_and_keeps_last_copy() -> void:
	var col := Collection.new()
	col.add("kindle", 1)
	col.add("kindle", 1, true)
	check(col.disenchant_foil("kindle", db), "spare foil")
	eq(col.dust, 5 * int(db.balance["dust"]["foil_mult"]))
	eq(col.count("kindle"), 1)
	check(not col.foils.has("kindle"), "foil gone")
	col.add("kindle", 1, true)
	check(not col.disenchant_foil("kindle", db) or col.count("kindle") >= 1, "never the last copy")


func test_normal_disenchant_keeps_foils_in_bounds() -> void:
	var col := Collection.new()
	col.add("kindle", 2, true)
	check(col.disenchant("kindle", db), "disenchant")
	check(int(col.foils["kindle"]) <= col.count("kindle"), "foils never exceed copies")


func test_records_data_valid() -> void:
	eq(Records.validate(db), [])


func test_profile_v7_migrates() -> void:
	var p := Profile.from_dict({"version": 7, "collection": {"counts": {"kindle": 1}}}, db)
	eq(p.binders, {})
	eq(p.loadouts, {})
	eq(p.to_dict()["version"], Profile.SAVE_VERSION)


func test_ice_counts_fold_into_the_profile_and_decode() -> void:
	var p := Profile.new_player(db)
	var r := RunState.start(db, p, RunState.default_picks(db, p), 3)
	for i in 3:
		var c := r.start_combat("mites")
		for en in c.enemies:
			en.hp = 0
		c.phase = Combat.Phase.WON
		Records.tally_ice(r, c)
	var id: String = r.ice.keys()[0]
	eq(int(r.ice[id]["seen"]), 3, "seen once per fight")
	check(int(r.ice[id]["crashed"]) >= 3, "every crash counted")
	var before: Dictionary = Records.ice_entries(db, p).filter(func(e: Dictionary) -> bool: return e["id"] == id)[0]
	eq(before["state"], "unknown")
	var lines := Records.fold_ice(db, p, r)
	check(not lines.is_empty() and str(lines[0]).begins_with("ICE decoded"), "decode line")
	var after: Dictionary = Records.ice_entries(db, p).filter(func(e: Dictionary) -> bool: return e["id"] == id)[0]
	eq(after["state"], "decoded")
	check(not after["moves"].is_empty() and after["lore"] != "", "moves and lore shown")
	eq(Profile.from_dict(p.to_dict(), db).ice, p.ice, "saved")


func test_deep_stack_waits_after_the_final_core_then_scales() -> void:
	var p := Profile.new_player(db)
	check(not Records.deep_unlocked(db, p), "locked at first")
	p.stats["best_win_heat"] = 3
	check(Records.deep_unlocked(db, p), "open after a Heat 3 win")
	var r := RunState.start(db, p, RunState.default_picks(db, p), 3)
	r.deep_ok = true
	r.boss_won = true
	r.deep_pending = true
	eq(r.available_nodes(), [], "no moves until the choice is made")
	var hp_mult: float = r.combat_opts()["enemy_hp_mult"]
	r.descend()
	eq(r.deep, 1)
	check(not r.over and not r.deep_pending and not r.available_nodes().is_empty(), "a new layer to play")
	check(r.combat_opts()["enemy_hp_mult"] > hp_mult, "sentries are tougher")
	var r2 := RunState.from_dict(db, r.to_dict())
	eq(r2.deep, 1, "depth saved")
	r.deep_pending = true
	r.jack_out()
	check(r.over and r.boss_won, "jacking out keeps the win")
	p.finish_run(db, r)
	eq(int(p.stats["best_depth"]), 1)
