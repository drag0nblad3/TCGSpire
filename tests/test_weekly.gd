extends TestCase
## Weekly challenge (rotating rule changes, base-level cards, no rig) and the daily login bonus.


func _veteran() -> Profile:
	var p := Profile.new_player(db)
	var perk_id := ""
	for id in db.perks:
		if db.perks[id].get("scope", "") == "rig" and db.perks[id].get("mods", {}).has("max_hp"):
			perk_id = id
	p.rig[perk_id] = 3
	for id in p.collection.owned_ids():
		p.firmware[id] = 2
	return p


func test_week_starts_on_monday() -> void:
	eq(Weekly.week_of("2026-11-13"), "2026-11-09", "Friday")
	eq(Weekly.week_of("2026-11-09"), "2026-11-09", "Monday")
	eq(Weekly.week_of("2026-11-15"), "2026-11-09", "Sunday")
	eq(Weekly.week_of("2026-11-16"), "2026-11-16")
	eq(Weekly.days_left("2026-11-09"), 7)
	eq(Weekly.days_left("2026-11-15"), 1)


func test_challenge_is_fixed_per_week_and_rotates() -> void:
	var a := Weekly.challenge(db, "2026-11-09")
	eq(a, Weekly.challenge(db, "2026-11-09"))
	eq(int(a["heat"]), int(db.balance["weekly"]["heat"]))
	eq(a["mods"].size(), int(db.balance["weekly"]["mods"]))
	var seen := {}
	for m in a["mods"]:
		check(db.weekly.has(m), "known modifier")
		seen[m] = true
	eq(seen.size(), a["mods"].size(), "no repeats")
	var differs := false
	for week in ["2026-11-16", "2026-11-23", "2026-11-30", "2026-12-07", "2026-12-14"]:
		var b := Weekly.challenge(db, week)
		if b["mods"] != a["mods"]:
			differs = true
	check(differs, "modifiers rotate between weeks")


func test_weekly_run_ignores_rig_and_firmware() -> void:
	var p := _veteran()
	var w := Weekly.challenge(db, "2026-11-09")
	var normal := RunState.start(db, p, RunState.default_picks(db, p, w["job"], w["targets"]), 3, 2, w["job"], w["targets"])
	var run := Weekly.begin(db, p, w, RunState.default_picks(db, p, w["job"], w["targets"]), 3)
	check(normal.rig.size() > 0 and normal.deck.any(func(c: CardInstance) -> bool: return c.fw > 0), "normal runs use rig and firmware")
	check(run.rig.is_empty(), "no rig")
	check(run.deck.all(func(c: CardInstance) -> bool: return c.fw == 0 and c.mod.is_empty()), "every card at base level")
	eq(run.weekly, "2026-11-09")
	eq(int(p.weekly["tries"]), 1)
	var again := RunState.from_dict(db, run.to_dict())
	eq(again.weekly_mods, run.weekly_mods, "modifiers survive a save")


func test_modifiers_apply() -> void:
	var p := Profile.new_player(db)
	var w := {"week": "2026-11-09", "seed": 7, "job": "ember", "heat": 0, "targets": [], "mods": ["overclocked_grid", "field_patch", "scorched_net"]}
	var run := Weekly.begin(db, p, w, RunState.default_picks(db, p, "ember"))
	var base := RunState.start(db, p, RunState.default_picks(db, p, "ember"), 7, 0, "ember")
	eq(run.max_hp, base.max_hp - 15, "Field Patch lowers max HP")
	eq(int(run.perk_mod("combat_heal")), 4)
	var opts := run.combat_opts()
	eq(int(opts["extra_energy"]), 1, "Overclocked Grid RAM")
	eq(int(opts["extra_hand"]), -1)
	check(absf(float(opts["enemy_hp_mult"]) - 1.15) < 0.001, "Scorched Net enemy HP")
	var c := run.start_combat("mites")
	c.start()
	check(c.enemies.all(func(e: Fighter) -> bool: return e.status("burn") > 0), "enemies start burning")
	eq(c.hand.size(), c.hand_size)
	eq(c.hand_size, int(db.balance["player"].get("hand_size", 5)) - 1)


func test_first_clear_pays_once_and_keeps_heat() -> void:
	var p := Profile.new_player(db)
	var w := Weekly.challenge(db, "2026-11-09")
	for k in 2:
		var run := Weekly.begin(db, p, w, RunState.default_picks(db, p, w["job"], w["targets"]))
		run.boss_won = true
		run.acts_cleared = run.total_acts()
		run.floor_num = 30
		var lines := Weekly.finish_run(db, p, run) if k == 0 else p.finish_run(db, run)
		var paid := lines.any(func(l: Variant) -> bool: return str(l).begins_with("Weekly challenge cleared"))
		eq(paid, k == 0, "weekly pack on the first clear only (try %d)" % k)
		check(lines.any(func(l: Variant) -> bool: return str(l).begins_with("Weekly challenge score")), "score line")
	eq(p.max_heat, 0, "weekly wins never unlock heat")
	check(bool(p.weekly["cleared"]), "cleared")
	eq(int(p.weekly["clears"]), 1)
	eq(int(Weekly.state(p, "2026-11-16")["tries"]), 0, "a new week starts fresh")


func test_data_modifiers_valid() -> void:
	check(db.weekly.size() >= int(db.balance["weekly"]["mods"]), "enough modifiers")
	for id in db.weekly:
		eq(Weekly.validate(db.weekly[id]), [] as Array[String], id)
	var bad := Weekly.validate({"id": "x", "name": "X", "text": "t", "mods": {"nope": 1}, "heat": {"double_cross": 1}})
	eq(bad.size(), 2)


func test_login_bonus_escalates_and_never_resets() -> void:
	var p := Profile.new_player(db)
	var scrap: Array = db.balance["login"]["scrap"]
	var dust := p.collection.dust
	var got := LoginBonus.claim(db, p, "2026-11-01")
	eq(int(got["day"]), 1)
	eq(p.collection.dust, dust + int(scrap[0]))
	eq(LoginBonus.claim(db, p, "2026-11-01"), {}, "once a day")
	# A missed week still continues the track at day 2.
	got = LoginBonus.claim(db, p, "2026-11-09")
	eq(int(got["day"]), 2)
	for d in range(10, 14):
		LoginBonus.claim(db, p, "2026-11-%02d" % d)
	eq(int(p.login["day"]), 6)
	check(int(scrap[5]) > int(scrap[0]), "scrap escalates")
	var packs := p.packs_unopened
	got = LoginBonus.claim(db, p, "2026-11-15")
	eq(int(got["day"]), 7)
	eq(p.packs_unopened, packs + int(db.balance["login"]["packs"]), "day 7 pays a pack")
	eq(int(LoginBonus.claim(db, p, "2026-11-16")["day"]), 1, "cycle restarts")
	var again := Profile.from_dict(p.to_dict(), db)
	eq(again.login, p.login, "saved")
