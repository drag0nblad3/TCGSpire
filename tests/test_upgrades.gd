extends TestCase
## Card mods, subroutines (run perks), rig upgrades, firmware, faction jobs and rep.

const TMP := "user://test_profile_up.json"

var profile: Profile


func before_each() -> void:
	profile = Profile.new_player(db)


func _run(seed_in: int = 1, job: String = "") -> RunState:
	return RunState.start(db, profile, RunState.default_picks(db, profile, job), seed_in, 0, job)


func _modded(id: String, mod_id: String, up: bool = false) -> CardInstance:
	var c := db.instance(id, up)
	check(CardMods.can_apply(db.mod(mod_id), c), "%s fits %s" % [mod_id, id])
	c.mod = db.mod(mod_id)
	return c


# --- card mods -----------------------------------------------------------------

func test_mod_changes_cost_keywords_and_numbers() -> void:
	eq(_modded("kindle", "overclocked").cost(), 0, "overclocked cost")
	check(_modded("jab", "cached").has_keyword("retain"), "cached retain")
	eq(_modded("jab", "hardened_payload").effects()[0]["amount"], 8, "bump damage")
	eq(_modded("jab", "hardened_payload", true).effects()[0]["amount"], 11, "bump on upgraded")
	eq(int(db.card("jab").effects[0]["amount"]), 6, "def not mutated")
	var looped := _modded("brace", "looped")
	eq(looped.effects().back()["op"], "draw", "effects_add")
	check(looped.text().contains("Draw"), "text shows the mod: " + looped.text())
	check(not _modded("spark", "persistent").has_keyword("exhaust"), "persistent drops exhaust")


func test_mod_restrictions() -> void:
	check(not CardMods.can_apply(db.mod("overclocked"), db.instance("focus")), "overclock needs cost 1+")
	check(not CardMods.can_apply(db.mod("hardened_payload"), db.instance("brace")), "payload needs an attack")
	check(not CardMods.can_apply(db.mod("infected"), db.instance("brace")), "infected needs a target")
	check(not CardMods.can_apply(db.mod("persistent"), db.instance("jab")), "persistent needs exhaust")
	check(not CardMods.can_apply(db.mod("cached"), db.instance("focus")), "already retains")
	var c := _modded("jab", "cached")
	check(not CardMods.can_apply(db.mod("infected"), c), "one mod per card")


func test_modded_card_plays_in_combat() -> void:
	var c := make_combat([])
	c.start()
	c.hand.append(_modded("kindle", "overclocked"))
	c.energy = 0
	check(c.play_card(c.hand.size() - 1, 0), "0-cost after overclock")
	var hp_before: int = c.enemies[0].hp
	c.hand.append(_modded("jab", "infected"))
	c.energy = 1
	c.play_card(c.hand.size() - 1, 0)
	check(c.enemies[0].status("burn") >= 2 or c.enemies[0].hp < hp_before, "infected applies virus")


func test_run_installs_mods_and_shop_sells_them() -> void:
	var r := _run()
	var targets := r.mod_targets("cached")
	check(not targets.is_empty(), "cached fits the deck")
	check(r.install_mod(targets[0], "cached"), "install")
	check(not r.install_mod(targets[0], "infected"), "second mod refused")
	r.floor_num = 3
	var shop := r.make_shop()
	check(not shop["mods"].is_empty(), "shop mods")
	r.gold = 500
	var item: Dictionary = shop["mods"][0]
	var idx: int = r.mod_targets(item["id"])[0]
	check(r.buy_mod(item, idx), "buy mod")
	check(r.deck[idx].mod_id() == item["id"], "bought mod installed")
	check(not r.buy_mod(item, idx), "sold out")


func test_mod_outcome() -> void:
	var r := _run()
	var line := RunOutcomes.apply(r, {"op": "mod", "amount": 2})
	check(line.begins_with("Installed"), line)
	eq(r.deck.filter(func(c: CardInstance) -> bool: return not c.mod.is_empty()).size(), 2, "two mods")


# --- subroutines (run perks) ---------------------------------------------------------

func test_perks_change_rewards_and_combat() -> void:
	var r := _run()
	r.add_perk("deep_scan")
	eq(r.reward_choices().size(), 4, "deep scan extra choice")
	r.add_perk("boot_shield")
	r.add_perk("ram_spike")
	var c := r.start_combat("mites")
	c.start()
	check(c.player.ward >= 6, "boot shield ward")
	eq(c.energy, 4, "ram spike turn 1")
	eq(r.add_perk("ram_spike"), [], "no duplicates")


func test_perk_pickup_and_heal_after_fight() -> void:
	var r := _run()
	var before := r.max_hp
	var lines := r.add_perk("ablative_casing")
	eq(r.max_hp, before + 10, "pickup max hp")
	eq(lines.size(), 2, "log lines")
	r.add_perk("nanite_mesh")
	r.hp = 20
	var c := r.start_combat("mites")
	c.start()
	for e in c.enemies:
		e.hp = 0
	c._check_end()
	var rew := r.finish_combat(c)
	eq(int(rew.get("healed", 0)), 4, "nanite mesh")


func test_elite_offers_subroutines() -> void:
	var r := _run()
	var elite := ""
	for id in db.encounters:
		if db.encounters[id].get("kind", "") == "elite":
			elite = id
			break
	var c := r.start_combat(elite)
	c.start()
	for e in c.enemies:
		e.hp = 0
	c._check_end()
	var rew := r.finish_combat(c)
	eq(rew.get("perks", []).size(), 3, "three choices")


# --- jobs and rep -----------------------------------------------------------------

func test_job_rules_and_bans() -> void:
	var n := profile.starter_picks(db)
	check(Jobs.check(db, "ember", ["kindle", "kindle", "undertow"], n) != "", "rival banned")
	check(Jobs.check(db, "ember", ["kindle", "focus", "second_wind", "sprout"], n) != "", "needs half")
	eq(Jobs.check(db, "ember", ["kindle", "kindle", "focus", "sprout"], n), "", "valid")
	for f in Jobs.board(db):
		var picks := RunState.default_picks(db, profile, f)
		eq(Jobs.check(db, f, picks, n), "", "default picks for " + f)
	var r := _run(3, "ember")
	check(r.deck.all(func(c: CardInstance) -> bool: return c.def.faction != "tide"), "no tide in deck")
	for s in 20:
		r.floor_num = s
		for id in r.reward_choices("elite") + r.make_shop()["cards"].map(func(x: Dictionary) -> String: return x["id"]):
			check(db.card(id).faction != "tide", "tide offered: " + id)


func test_job_pays_rep() -> void:
	var r := _run(1, "void")
	r.floor_num = 10
	r.elites_won = 1
	var lines := profile.finish_run(db, r)
	eq(profile.rep_of("void"), int(26 * float(db.balance["jobs"].get("rep_mult", 1.0))), "rep")
	check(lines.any(func(l: String) -> bool: return l.contains(Jobs.rep_name(db, "void"))), "rep line")
	eq(profile.rep_of("ember"), 0, "only the client pays")


# --- rig upgrades -------------------------------------------------------------------

func test_rig_costs_rep_and_refunds() -> void:
	check(not profile.buy_rig(db, "chassis"), "no rep")
	var r1 := Profile.rank_cost(db, "chassis", 1)
	var r2 := Profile.rank_cost(db, "chassis", 2)
	check(r2 > r1, "ranks get pricier")
	profile.rep["bloom"] = r1 + r2
	check(profile.buy_rig(db, "chassis"), "rank 1")
	eq(profile.rep_of("bloom"), r2)
	check(profile.buy_rig(db, "chassis"), "rank 2")
	eq(profile.rep_of("bloom"), 0)
	var r := _run()
	eq(r.max_hp, int(db.balance["player"]["max_hp"]) + 2 * int(db.perks["chassis"]["mods"]["max_hp"]), "rig max hp")
	profile.reset_rig(db)
	eq(profile.rep_of("bloom"), r1 + r2, "refund")
	eq(profile.rig, {})


func test_v4_rig_keeps_original_refund_value() -> void:
	var old := {
		"version": 4,
		"rep": {"bloom": 7, "ember": 10, "tide": 11},
		"rig": {"chassis": 2, "thermal_runaway": 1},
		"firmware": {"kindle": 2},
	}
	var p := Profile.from_dict(old, db)
	eq(p.rep, old["rep"], "prices match v4")
	eq(p.rig, old["rig"], "keeps purchased ranks")
	eq(p.firmware, {"kindle": 2}, "keeps firmware")
	var reloaded := Profile.from_dict(p.to_dict(), db)
	eq(reloaded.rep, p.rep, "does not credit twice")
	reloaded.reset_rig(db)
	eq(reloaded.rep, {"bloom": 127, "ember": 510, "tide": 11}, "original total rep restored")


func test_v5_rig_refunds_discounted_ranks_and_new_purchases_at_price_paid() -> void:
	var p := Profile.from_dict({
		"version": 5,
		"rep": {"bloom": 200, "ember": 10},
		"rig": {"chassis": 2, "thermal_runaway": 1},
	}, db)
	check(p.buy_rig(db, "chassis"), "buys rank three at the restored price")
	eq(p.rep_of("bloom"), 20, "new rank costs 180")
	var reloaded := Profile.from_dict(p.to_dict(), db)
	reloaded.reset_rig(db)
	eq(reloaded.rep, {"bloom": 275, "ember": 310}, "refunds 75 + 180 and 300")
	reloaded.reset_rig(db)
	eq(reloaded.rep, {"bloom": 275, "ember": 310}, "refund adjustment applies once")


func test_moved_rig_perks_keep_ranks_and_refunds_in_the_original_faction() -> void:
	for version in [5, 6]:
		var p := Profile.from_dict({
			"version": version,
			"rig": {"contract_killer": 2, "crowd_funding": 1, "dividend_plan": 3},
		}, db)
		eq(p.rig, {"signal_override": 2, "contract_killer": 1, "reward_reroute": 3})
		eq(Profile.from_dict(p.to_dict(), db).rig, p.rig, "migration applies once")
		p.reset_rig(db)
		eq(p.rep, {"ember": 50, "noise": 10, "tide": 195} if version == 5 else
			{"ember": 80, "noise": 20, "tide": 300}, "refunds match the prices paid")


func test_rig_rerolls_replace_choices_and_spend_only_their_own_charge() -> void:
	profile.rig = {"signal_override": 1, "reward_reroute": 1}
	var r := _run(17, "ember")
	var original := r.reward_choices("elite")
	var replacement := r.reroll_reward("elite", original)
	eq(replacement.size(), original.size())
	check(replacement.all(func(id: String) -> bool: return id not in original and db.card(id).faction not in r.banned), "reroll offers different legal cards")
	eq(r.reroll_reward("elite", replacement), [], "reward charge exhausted")
	var signal_id: String = r.pick_event()["id"]
	var signal_roll := r.reroll_event(signal_id)
	check(not signal_roll.is_empty() and signal_roll["id"] != signal_id, "reroll offers a different Signal")
	eq(r.reroll_event(signal_roll["id"]), {}, "Signal charge exhausted")
	eq(_run(17, "ember").reroll_reward("elite", original), replacement, "reward rerolls are seeded")


func test_rig_start_mods_and_perks() -> void:
	profile.rig = {"mod_cache": 1, "seed_subroutine": 1}
	var r := _run()
	eq(r.perks.size(), 1, "seeded subroutine")
	check(r.deck.any(func(c: CardInstance) -> bool: return not c.mod.is_empty()), "starting mod")


# --- firmware --------------------------------------------------------------------

func test_firmware_uses_up_extra_copies_and_rep() -> void:
	var ladder := Profile.copy_ladder(db, "kindle")
	var lim := Profile.deck_limit(db)
	profile.collection.counts["kindle"] = lim + int(ladder[0]) - 1
	check(profile.firmware_block(db, "kindle").begins_with("Collect %d extra" % int(ladder[0])), "deck copies don't count")
	profile.collection.add("kindle")
	check(profile.copies_ready(db, "kindle"), "extras ready")
	check(profile.firmware_block(db, "kindle") != "", "rep gate")
	profile.rep["ember"] = int(profile.firmware_price(db, "kindle")["amount"])
	check(profile.flash_firmware(db, "kindle"), "flash")
	eq(profile.rep_of("ember"), 0)
	eq(profile.collection.count("kindle"), lim, "extras used up, deck copies stay")
	profile.collection.dust = int(profile.firmware_price(db, "jab")["amount"])
	check(profile.flash_firmware(db, "jab"), "starters cost dust, no copies")
	eq(profile.collection.dust, 0)
	var r := RunState.start(db, profile, ["kindle"], 1)
	check(r.deck.filter(func(c: CardInstance) -> bool: return c.def.id in ["kindle", "jab"]).all(func(c: CardInstance) -> bool: return c.fw == 1), "firmware copies flashed")
	r.add_card("kindle")
	eq(r.deck.back().fw, 1, "added copies flashed too")
	var jab: CardInstance = r.deck.filter(func(c: CardInstance) -> bool: return c.def.id == "jab")[0]
	eq(int(jab.effects()[0]["amount"]), roundi(6 * 1.25), "v1 scales damage")
	check(not jab.upgraded, "recompile still available in the run")
	# Level 2: more extras, twice the price.
	var base := int(db.balance["firmware"]["rep_cost"][db.card("kindle").rarity])
	eq(int(profile.firmware_price(db, "kindle")["amount"]), base * 2, "v2 costs double")
	profile.rep["ember"] = base * 2
	check(profile.firmware_block(db, "kindle").begins_with("Collect %d" % int(ladder[1])), "v2 needs more extras")
	profile.collection.add("kindle", int(ladder[1]))
	check(profile.flash_firmware(db, "kindle"), "flash v2")
	eq(profile.firmware_level(db.card("kindle").id), 2)
	eq(profile.collection.count("kindle"), lim)
	check(profile.firmware_block(db, "kindle") == "Firmware maxed.", "max two levels")
	check(profile.copies_complete(db, "kindle"), "nothing left to collect")
	var k := db.instance("kindle", false, 2)
	eq(int(k.effects()[0]["amount"]), roundi(float(db.card("kindle").effects[0]["amount"]) * 1.5), "v2 scales by 1.5")


func test_deck_holds_at_most_the_copy_limit() -> void:
	profile.collection.counts["kindle"] = 5
	eq(profile.deck_copies(db, "kindle"), Profile.deck_limit(db))
	var picks := ["kindle", "kindle", "kindle"]
	var r := RunState.start(db, profile, picks, 1)
	eq(r.deck.filter(func(c: CardInstance) -> bool: return c.def.id == "kindle").size(), Profile.deck_limit(db), "third copy refused")


func test_full_run_pays_an_extra_pack() -> void:
	var r := RunState.start(db, profile, [], 1)
	r.acts_cleared = 3
	r.boss_won = true
	var before := profile.packs_unopened
	profile.finish_run(db, r)
	check(profile.packs_unopened - before >= 3 + int(db.balance["run_rewards"]["packs_full_run"]), "boss packs + full run pack")


func test_payout_preview_matches_what_a_full_clear_pays() -> void:
	var job: String = Jobs.board(db)[0]
	var heat := 2
	var pay := Jobs.payout_preview(db, profile, job, heat)
	var r := RunState.start(db, profile, [], 1, heat, job, Jobs.banned(db, job) + ["x"].slice(0, Jobs.extra_targets(db, heat)))
	r.acts_cleared = int(db.balance["acts"])
	r.boss_won = true
	r.floor_num = r.acts_cleared * (int(db.balance["map"]["rows"]) + 1)
	eq(int(pay["packs"]), Profile.run_packs(db, r))
	eq(int(pay["packs"]), r.acts_cleared * int(db.balance["run_rewards"]["packs_per_boss"]) + int(db.balance["run_rewards"]["packs_full_run"]))
	eq(int(pay["xp"]), Profile.run_xp(db, r))
	eq(int(pay["rep"]), Jobs.rep_reward(db, r))
	var rep_before := profile.rep_of(job)
	profile.finish_run(db, r)
	check(profile.rep_of(job) - rep_before >= int(pay["rep"]), "preview rep is paid")
	check(Records.clause_text(db, db.contracts.keys()[0], 0, job).contains(Jobs.rep_name(db, job)), "bonus names its rep")


func test_save_roundtrip_and_migration() -> void:
	profile.rep = {"tide": 7}
	profile.rig = {"chassis": 2}
	profile.firmware = {"kindle": 2}
	eq(profile.save(TMP), OK, "save")
	var q := Profile.load_or_new(db, TMP)
	eq(q.rep, {"tide": 7})
	eq(q.rig, {"chassis": 2})
	eq(q.firmware, {"kindle": 2})
	var v3 := Profile.from_dict({"version": 3, "firmware": ["jab"], "collection": {}})
	eq(v3.firmware, {"jab": 1}, "v3 firmware becomes level 1")
	DirAccess.remove_absolute(TMP)
	var old := Profile.from_dict({"version": 2, "xp": 50, "collection": {}})
	eq(old.rig, {})
	eq(old.rep, {})
	eq(old.xp, 50)


func test_rules_mention_new_systems() -> void:
	var heads: Array = Rules.sections(db).map(func(s: Array) -> String: return s[0])
	check("Jobs and rep" in heads and "Upgrades and perks" in heads, "rules sections")
	for id in db.perks:
		check(not Perks.describe(db.perks[id]).contains("?"), "perk text " + id)
	for id in db.mods:
		check(CardMods.describe(db.mods[id]) != "", "mod text " + id)


# --- six crews, faction enemies, multi-target jobs ------------------------------------

func test_six_crews_in_rival_pairs() -> void:
	eq(Jobs.board(db).size(), 6, "six crews")
	for f in Jobs.board(db):
		var r: Array = Jobs.banned(db, f)
		eq(r.size(), 1, "one rival for " + f)
		eq(Jobs.banned(db, r[0]), [f], "rivalry is mutual for " + f)


func test_map_uses_target_crew_enemies() -> void:
	var seen := {}
	for s in 10:
		for act in [1, 2]:
			var m := RunMap.generate(db, GameRng.new(s), act, ["chrome"])
			for n in m.nodes:
				var f := str(db.encounters.get(n["encounter"], {}).get("faction", ""))
				check(f in ["", "chrome"], "non-target crew on the map: " + n["encounter"])
				seen[f] = true
			var free := RunMap.generate(db, GameRng.new(s), act)
			for n in free.nodes:
				eq(str(db.encounters.get(n["encounter"], {}).get("faction", "")), "", "freelance map has crew enemies")
	check(seen.has("chrome"), "chrome enforcers appear")


func test_high_heat_adds_targets_with_one_client() -> void:
	eq(Jobs.extra_targets(db, 0), 0)
	for f in Jobs.board(db):
		var t := Jobs.targets(db, f, 2, GameRng.new(5))
		eq(t.size(), 3, "targets for " + f)
		check(f not in t, "client never a target")
		eq(t[0], Jobs.banned(db, f)[0], "rival first")
	var targets := Jobs.targets(db, "ember", 1, GameRng.new(2))
	var r := RunState.start(db, profile, RunState.default_picks(db, profile, "ember", targets), 1, 3, "ember", targets)
	eq(r.banned, targets, "run targets")
	check(r.reward_choices("elite").all(func(id: String) -> bool: return db.card(id).faction not in targets), "targets not offered")
	r.floor_num = 10
	var base := RunState.start(db, profile, RunState.default_picks(db, profile, "ember"), 1, 3, "ember")
	base.floor_num = 10
	check(Jobs.rep_reward(db, r) > Jobs.rep_reward(db, base), "extra target pays more")


# --- crew bosses, firmware mods, new perk keys ----------------------------------------

func test_every_crew_has_a_boss_per_act_and_jobs_meet_them() -> void:
	for f in Jobs.board(db):
		for act in [1, 2]:
			check(db.encounters.values().any(func(e: Dictionary) -> bool:
				return e.get("faction", "") == f and e.get("kind", "") == "boss" and int(e.get("act", 1)) == act), "%s act %d boss" % [f, act])
	var crew_bosses := 0
	for s in 40:
		var m := RunMap.generate(db, GameRng.new(s), 1, ["noise"])
		var f := str(db.encounters[m.nodes.back()["encounter"]].get("faction", ""))
		check(f in ["", "noise"], "boss from a non-target crew")
		if f == "noise":
			crew_bosses += 1
	check(crew_bosses >= 20, "most job bosses are the target crew's (%d/40)" % crew_bosses)


func test_firmware_mod_bakes_into_every_copy() -> void:
	check(profile.firmware_mod_block(db, "kindle", "cached") != "", "needs firmware")
	profile.firmware["kindle"] = true
	profile.mastery["kindle"] = 10
	check(profile.firmware_mod_block(db, "kindle", "cached").begins_with("Run it"), "needs mastery tier 2")
	profile.mastery["kindle"] = 30
	profile.rep["ember"] = 200
	var price := int(profile.firmware_mod_price(db, "kindle", "cached")["amount"])
	check(profile.bake_firmware_mod(db, "kindle", "cached"), "bake")
	eq(profile.rep_of("ember"), 200 - price, "common mod price")
	var r := RunState.start(db, profile, ["kindle"], 1)
	r.add_card("kindle")
	for c in r.deck:
		if c.def.id == "kindle":
			eq(c.mod_id(), "cached", "baked mod")
			check(c.fw > 0, "and flashed")
	var q := Profile.from_dict(profile.to_dict())
	eq(q.firmware_mods, {"kindle": "cached"}, "saved")


func test_new_perk_keys() -> void:
	profile.rig = {"pirate_coupons": 2, "wider_menu": 1, "contract_killer": 3}
	var r := _run(1, "ember")
	eq(r.remove_price(), int(db.balance["shop"]["remove_base"]) - 2 * int(db.perks["pirate_coupons"]["mods"]["remove_discount"]), "deletion discount")
	r.floor_num = 10
	var base := RunState.start(db, Profile.new_player(db), RunState.default_picks(db, profile, "ember"), 1, 0, "ember")
	base.floor_num = 10
	eq(Jobs.rep_reward(db, r), int(Jobs.rep_reward(db, base) * 1.15), "rep bonus")
	var elite := ""
	for id in db.encounters:
		if db.encounters[id].get("kind", "") == "elite" and not db.encounters[id].has("faction"):
			elite = id
			break
	var c := r.start_combat(elite)
	c.start()
	for e in c.enemies:
		e.hp = 0
	c._check_end()
	eq(r.finish_combat(c).get("perks", []).size(), 4, "extra subroutine choice")


func test_every_card_explains_its_upgrade() -> void:
	eq(db.card("jab").upgrade_summary(), "Damage 6 → 9.")
	eq(db.card("second_wind").upgrade_summary(), "Costs 0 RAM (was 1).")
	for id in db.cards:
		var t: String = db.cards[id].upgrade_summary()
		check(t != "No change." and t != "" and not t.contains("?"), "upgrade text for %s: %s" % [id, t])
	check(CardInspector.glossary(db.instance("kindle")).any(func(l: String) -> bool: return l.contains("Damage 4 → 6.")), "inspector shows the upgrade")


func test_profile_bot_builds_sim_saves() -> void:
	var v := ProfileBot.veteran(db, 2)
	eq(int(v.stats["runs"]), 2, "two runs played")
	eq(v.packs_unopened, 0, "packs opened")
	var m := ProfileBot.maxed(db)
	check(m.rig.size() == Perks.ids(db, "rig").size(), "every rig perk")
	check(m.firmware.has("jab") and m.firmware_mods.size() > 20, "firmware everywhere")
	for f in Jobs.board(db):
		var picks := RunBot.best_picks(db, m, f, [])
		eq(picks.size(), m.starter_picks(db), "full picks for " + f)
		eq(Jobs.check(db, f, picks, m.starter_picks(db)), "", "legal picks for " + f)


func test_heat_stat_boosts_compound() -> void:
	var r := RunState.start(db, profile, [], 1, 2)
	var levels: Array = db.balance["heat"]
	var want := (1.0 + float(levels[0]["mods"].get("enemy_hp_pct", 0.0))) * (1.0 + float(levels[1]["mods"].get("enemy_hp_pct", 0.0)))
	check(absf(r.heat_mult("enemy_hp_pct") - want) < 0.001, "hp boosts multiply")
	var c := r.start_combat(db.encounters.keys()[0])
	check(c.enemy_dmg_mult > 1.0, "heat raises enemy damage")
	var f := Fighter.make("x", "x", 10)
	f.dmg_mult = 1.5
	eq(Statuses.modify_attack(10, f, null), 15, "damage multiplier applies")


func test_runs_pay_a_pack_per_boss() -> void:
	var r := RunState.start(db, profile, [], 1)
	r.acts_cleared = 2
	r.combats_won = 12
	var before := profile.packs_unopened
	profile.finish_run(db, r)
	eq(profile.packs_unopened - before, 2 * int(db.balance["run_rewards"]["packs_per_boss"]))


func test_double_cross_turns_client_in_final_act() -> void:
	var targets := Jobs.targets(db, "ember", 0, GameRng.new(1))
	var r := RunState.start(db, profile, RunState.default_picks(db, profile, "ember", targets), 1, 6, "ember", targets)
	check(not r.double_crossed, "loyal at first")
	while r.act < r.total_acts():
		r._next_act()
	check(r.double_crossed, "client sells you out in the last act")
	check("ember" in r.banned, "client crew now a target")
	var boss: Dictionary = r.map.nodes.back()
	eq(str(db.encounters[boss["encounter"]].get("faction", "")), "ember", "client's Core guards the top")
	var r0 := RunState.start(db, profile, RunState.default_picks(db, profile, "ember", targets), 1, 5, "ember", targets)
	while r0.act < r0.total_acts():
		r0._next_act()
	check(not r0.double_crossed, "only at heat 6")


func test_level_rewards_and_cap() -> void:
	var before_packs := profile.packs_unopened
	var before_dust := profile.collection.dust
	profile.add_xp(db, Profile.xp_for_level(4))
	eq(profile.level(), 4)
	eq(profile.packs_unopened - before_packs, 3, "a pack per level")
	eq(profile.collection.dust - before_dust, 10 * (2 + 3 + 4), "10 dust x level")
	var picks := profile.starter_picks(db)
	var basics := profile.base_deck(db).size()
	profile.add_xp(db, Profile.xp_for_level(5) - profile.xp)
	eq(profile.starter_picks(db), picks + 1, "pick at level 5")
	eq(profile.base_deck(db).size(), basics - 1, "it replaces a basic")
	profile.add_xp(db, 10000000)
	eq(profile.level(), Profile.LEVEL_CAP, "level cap")
	var deck := profile.base_deck(db)
	eq(deck.count("jab"), 2, "swaps alternate")
	eq(deck.count("brace"), 2, "swaps alternate")


func test_capstone_needs_crew_maxed_and_changes_combat() -> void:
	profile.rep["ember"] = 10000
	check(not profile.can_buy_rig(db, "thermal_runaway"), "locked until the crew is maxed")
	for id in db.perks:
		var p: Dictionary = db.perks[id]
		if p.get("scope", "") == "rig" and p.get("faction", "") == "ember" and not p.get("capstone", false):
			while profile.buy_rig(db, id):
				pass
	check(profile.buy_rig(db, "thermal_runaway"), "unlocked")
	var r := RunState.start(db, profile, [], 1)
	r.perks.clear() # Isolate the capstone from randomly installed start perks.
	var c := r.start_combat(db.encounters.keys()[0])
	var base_ram := int(db.balance["player"]["max_energy"])
	c.start()
	for turn_index in range(1, 5):
		eq(c.energy, base_ram + (1 if turn_index <= 3 else 0), "Thermal Runaway turn %d" % turn_index)
		c._start_player_turn()



func test_liquidity_engine_preserves_thirty_percent_firewall_and_extra_draw() -> void:
	profile.rig = {"liquidity_engine": 1, "boot_firewall": 3}
	var r := _run()
	var c := r.start_combat(db.encounters.keys()[0])
	for enemy in c.enemies:
		enemy.moves = []
	c.start()
	eq(c.hand.size(), int(db.balance["player"]["hand_size"]) + 1, "extra draw")
	eq(c.player.ward, 9, "Boot Firewall grants its full opening amount")
	c.end_turn()
	eq(c.player.ward, 3, "retained Firewall rounds up")
	var starts := c.events.filter(func(e: Dictionary) -> bool: return e["t"] == "turn_start")
	eq(starts.back()["ward"], 3, "turn animation shows retained Firewall")
	c.player.ward = 10
	c.end_turn()
	eq(c.player.ward, 3, "30% of 10")
	c.player.add_status("fortify", 1)
	c.end_turn()
	eq(c.player.ward, 3, "Hardened keeps all Firewall")


func test_hive_link_explodes_once_for_each_destroyed_daemon() -> void:
	profile.rig["hive_link"] = 1
	var c := _run().start_combat("mites")
	c.start()
	eq(c.units.size(), 0, "Hive Link starts with an empty board")
	eq(c.board_slots, int(db.balance["board_slots"]), "normal board capacity")
	c.summon("Drone", 2)
	c.summon("Backup", 8)
	var drone: Fighter = c.units[0]
	var first: Fighter = c.enemies[0]
	var second: Fighter = c.enemies[1]
	var blast := int(db.perks["hive_link"]["mods"]["daemon_death_damage"])
	first.hp = 30
	first.ward = 2
	second.hp = 30
	c.deal_damage(drone, 1)
	eq(second.hp, 30, "surviving damage doesn't trigger the blast")
	c.deal_damage(drone, 1)
	eq(first.hp, 32 - blast, "enemy Firewall blocks part of the blast")
	eq(second.hp, 30 - blast, "blast hits every living enemy")
	eq(c.player.hp, c.player.max_hp, "blast leaves the player unharmed")
	eq(c.units[0].hp, 8, "blast leaves other daemons unharmed")
	c.deal_damage(drone, 1)
	eq(second.hp, 30 - blast, "a dead daemon can't explode twice")
