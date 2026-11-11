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
	eq(profile.rep_of("void"), 26, "rep")
	check(lines.any(func(l: String) -> bool: return l.contains(Jobs.rep_name(db, "void"))), "rep line")
	eq(profile.rep_of("ember"), 0, "only the client pays")


# --- rig upgrades -------------------------------------------------------------------

func test_rig_costs_rep_and_refunds() -> void:
	check(not profile.buy_rig(db, "chassis"), "no rep")
	profile.rep["bloom"] = 80
	check(profile.buy_rig(db, "chassis"), "rank 1")
	eq(profile.rep_of("bloom"), 55)
	check(profile.buy_rig(db, "chassis"), "rank 2 costs more")
	eq(profile.rep_of("bloom"), 5)
	var r := _run()
	eq(r.max_hp, int(db.balance["player"]["max_hp"]) + 8, "rig max hp")
	profile.reset_rig(db)
	eq(profile.rep_of("bloom"), 80, "refund")
	eq(profile.rig, {})


func test_rig_start_mods_and_perks() -> void:
	profile.rig = {"mod_cache": 1, "seed_subroutine": 1}
	var r := _run()
	eq(r.perks.size(), 1, "seeded subroutine")
	check(r.deck.any(func(c: CardInstance) -> bool: return not c.mod.is_empty()), "starting mod")


# --- firmware --------------------------------------------------------------------

func test_firmware_needs_mastery_and_rep() -> void:
	check(profile.firmware_block(db, "kindle").begins_with("Run it"), "mastery gate")
	profile.mastery["kindle"] = 10
	check(profile.firmware_block(db, "kindle") != "", "rep gate")
	profile.rep["ember"] = 30
	check(profile.flash_firmware(db, "kindle"), "flash")
	eq(profile.rep_of("ember"), 0)
	profile.collection.dust = 120
	check(profile.flash_firmware(db, "jab"), "starters cost dust, no mastery")
	eq(profile.collection.dust, 0)
	var r := RunState.start(db, profile, ["kindle"], 1)
	check(r.deck.filter(func(c: CardInstance) -> bool: return c.def.id in ["kindle", "jab"]).all(func(c: CardInstance) -> bool: return c.upgraded), "firmware copies upgraded")
	r.add_card("kindle")
	check(r.deck.back().upgraded, "added copies upgraded too")


func test_save_roundtrip_and_migration() -> void:
	profile.rep = {"tide": 7}
	profile.rig = {"chassis": 2}
	profile.firmware = {"kindle": true}
	eq(profile.save(TMP), OK, "save")
	var q := Profile.load_or_new(db, TMP)
	eq(q.rep, {"tide": 7})
	eq(q.rig, {"chassis": 2})
	eq(q.firmware, {"kindle": true})
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
	check(Jobs.extra_targets(db, 6) >= 2, "two extra at max heat")
	for offer in Jobs.offers(db, 6, GameRng.new(5)):
		var t: Array = offer["targets"]
		eq(t.size(), 1 + Jobs.extra_targets(db, 6), "targets for " + offer["client"])
		check(offer["client"] not in t, "client never a target")
		eq(t[0], Jobs.banned(db, offer["client"])[0], "rival first")
	var targets := Jobs.targets(db, "ember", 1, GameRng.new(2))
	var r := RunState.start(db, profile, RunState.default_picks(db, profile, "ember", targets), 1, 3, "ember", targets)
	eq(r.banned, targets, "run targets")
	check(r.reward_choices("elite").all(func(id: String) -> bool: return db.card(id).faction not in targets), "targets not offered")
	r.floor_num = 10
	var base := RunState.start(db, profile, RunState.default_picks(db, profile, "ember"), 1, 3, "ember")
	base.floor_num = 10
	check(Jobs.rep_reward(db, r) > Jobs.rep_reward(db, base), "extra target pays more")
