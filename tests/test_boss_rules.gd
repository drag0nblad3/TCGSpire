extends TestCase
## Boss rules (core/boss_rules.gd): one test per rule, on the encounters that carry it.

const DECK := ["jab", "jab", "jab", "jab", "brace", "brace", "brace", "brace"]


func _fight(encounter: String, seed_in: int = 3) -> Combat:
	var c := make_combat(DECK, encounter, seed_in)
	c.start()
	return c


func _enemy(c: Combat, id: String) -> Fighter:
	for e in c.enemies:
		if e.def_id == id and not e.is_dead():
			return e
	return null


func test_phase_holds_at_the_mark_and_swaps_moves() -> void:
	var c := _fight("ember_a3b")
	var boss := _enemy(c, "kiln_heart")
	var mark := BossRules.phase_floor(boss)
	boss.add_status("brittle", 2)
	c.deal_damage(boss, 9999, "player", "lose_hp")
	eq(boss.hp, mark, "a hit can't carry past the phase mark")
	eq(int(boss.state["phase"]), 1, "phase entered")
	eq(str(boss.current_move()["name"]), "Flare", "phase 2 move list")
	eq(boss.status("brittle"), 0, "debuffs wiped")
	eq(BossRules.phase_floor(boss), 0, "no further phase")
	eq(BossRules.taken_mult(c, boss, "attack"), 1.3, "phase rules replace the plating")
	c.deal_damage(boss, 9999, "player", "lose_hp")
	check(boss.is_dead(), "last phase can die")


func test_trace_timer_boosts_after_the_countdown() -> void:
	var c := _fight("ember_a2b")
	var boss := _enemy(c, "furnace_king")
	var turns := int(boss.rules["timer"]["turns"])
	boss.moves = [{"name": "Idle", "effects": []}]
	for i in turns:
		c.player.hp = c.player.max_hp
		c.end_turn()
	eq(boss.status("might"), 0, "no Boost during the countdown")
	eq(int(boss.state["timer"]), 0, "countdown done")
	c.end_turn()
	eq(boss.status("might"), int(boss.rules["timer"]["stacks"]), "Boost every move after")


func test_tide_scales_damage_and_low_tide_only_defends() -> void:
	var c := _fight("tide_a1b")
	var boss := _enemy(c, "undertow_broker")
	eq(BossRules.tide(c, boss), "high", "starts high")
	var hp := boss.hp
	c.deal_damage(boss, 20, "player")
	eq(hp - boss.hp, 15, "high tide: 75%")
	boss.moves = [{"name": "Idle", "effects": []}]
	c.end_turn()
	c.end_turn()
	eq(BossRules.tide(c, boss), "low", "third round is low")
	eq(str(boss.current_move()["name"]), "Ebb", "low tide move")
	eq(c.intent_damage(boss), 0, "no attack at low tide")
	hp = boss.hp
	boss.ward = 0
	c.deal_damage(boss, 20, "player")
	eq(hp - boss.hp, 30, "low tide: 150%")
	c.end_turn()
	eq(BossRules.tide(c, boss), "high", "back to high")
	eq(str(boss.current_move()["name"]), "Idle", "list move again")


func test_heat_gauge_vents_on_the_next_move_and_resets() -> void:
	var c := _fight("ember_a1b")
	var boss := _enemy(c, "kiln_mother")
	var cap := int(boss.rules["gauge"]["max"])
	for i in cap - 1:
		c.attack(c.player, boss, 1)
	eq(int(boss.state["gauge"]), cap - 1, "one heat per hit")
	var before := c.intent_damage(boss)
	c.attack(c.player, boss, 1)
	check(c.intent_damage(boss) > before, "vent is added to the shown intent")
	check(str(boss.current_move()["name"]).begins_with("Backdraft"), "vent named in the move")
	c.attack(c.player, boss, 1)
	eq(int(boss.state["gauge"]), cap, "full gauge stops counting")
	c.player.hp = c.player.max_hp
	c.end_turn()
	eq(int(boss.state["gauge"]), 0, "reset after venting")


func test_jam_hides_intent_until_exposed_or_interrupted() -> void:
	var c := _fight("noise_a3b")
	var boss := _enemy(c, "dead_air")
	check(not BossRules.jammed(c, boss), "turn 1 is clear")
	boss.moves = [{"name": "Idle", "effects": []}]
	c.end_turn()
	check(BossRules.jammed(c, boss), "turn 2 is jammed")
	eq(str(Intents.of(c, boss)[0]["kind"]), "jammed", "intent hidden")
	boss.add_status("brittle", 1)
	check(not BossRules.jammed(c, boss), "Exposed clears it")
	boss.statuses.erase("brittle")
	Effects.resolve(c, {"op": "interrupt", "kinds": ["heal"]}, c.player, boss)
	check(not BossRules.jammed(c, boss), "an Interrupt clears it, hit or miss")


func test_twin_is_restored_unless_both_fall() -> void:
	var c := _fight("bloom_a1b")
	var chief := _enemy(c, "chief_surgeon")
	var clone := _enemy(c, "surgeon_clone")
	chief.moves = [{"name": "Idle", "effects": []}]
	c.deal_damage(clone, 9999, "player", "lose_hp")
	check(c.phase == Combat.Phase.PLAYER, "fight goes on")
	c.end_turn()
	eq(str(chief.current_move()["name"]), "Restore", "survivor lines up Restore a turn later")
	eq(str(Intents.of(c, chief)[0]["kind"]), "restore", "restore intent")
	c.end_turn()
	var back := _enemy(c, "surgeon_clone")
	check(back != null, "twin restored")
	var full := clone.max_hp
	eq(back.hp, maxi(roundi(full * 0.4), 1), "at the listed share of HP")
	eq(back.max_hp, back.hp, "that share is its new max HP")
	# A second crash restores a share of the shrunken max.
	c.deal_damage(back, 9999, "player", "lose_hp")
	c.end_turn()
	c.end_turn()
	var again := _enemy(c, "surgeon_clone")
	check(again != null and again != back, "restored again")
	eq(again.max_hp, maxi(roundi(back.max_hp * 0.4), 1), "each Restore is smaller")
	back = again
	# Both down before the Restore lands: the fight ends.
	c.deal_damage(back, 9999, "player", "lose_hp")
	c.deal_damage(chief, 9999, "player", "lose_hp")
	c._check_end()
	eq(c.phase, Combat.Phase.WON, "both down wins")


func test_interrupt_stops_a_restore_for_good() -> void:
	var c := _fight("noise_a2b")
	var boss := _enemy(c, "the_broadcast")
	var co := _enemy(c, "co_anchor")
	boss.moves = [{"name": "Idle", "effects": []}]
	c.deal_damage(co, 9999, "player", "lose_hp")
	c.end_turn()
	Effects.resolve(c, {"op": "interrupt", "kinds": ["heal"]}, c.player, boss)
	c.end_turn()
	check(_enemy(c, "co_anchor") == null, "restore cancelled")
	eq(str(boss.current_move()["name"]), "Idle", "back to its own moves")


func test_shared_hp_pool_and_bodies_leaving() -> void:
	var c := _fight("tide_a2b")
	var vault := _enemy(c, "tidal_exchange")
	var bear := _enemy(c, "bear_desk")
	var bull := _enemy(c, "bull_desk")
	eq(bear.hp, vault.hp, "one total")
	eq(bull.max_hp, vault.max_hp, "same bar")
	c.deal_damage(bull, 10, "player")
	eq(vault.hp, vault.max_hp - 10, "damage to one body counts for all")
	eq(bear.hp, vault.hp, "synced")
	c.deal_damage(bear, 5, "", "burn")
	eq(vault.hp, vault.max_hp - 20, "Bear Desk takes double from Virus")
	Effects.resolve(c, {"op": "heal", "amount": 4, "to": "self"}, vault, vault)
	eq(bull.hp, vault.max_hp - 16, "repairs are shared too")
	c.deal_damage(vault, vault.hp - int(vault.max_hp * 0.6), "player", "lose_hp")
	check(bear.is_dead(), "Bear Desk shuts down at 66%")
	check(not bull.is_dead() and not vault.is_dead(), "the others stay")
	c.deal_damage(vault, 9999, "player", "lose_hp")
	c._check_end()
	eq(c.phase, Combat.Phase.WON, "empty pool ends the fight")


func test_pylons_shield_the_boss_and_come_back() -> void:
	var c := _fight("chrome_a3b")
	var boss := _enemy(c, "hive_throne")
	var hp := boss.hp
	eq(c.deal_damage(boss, 30, "player"), 0, "shielded")
	c.deal_damage(boss, 9, "", "burn")
	eq(boss.hp, hp, "Virus is stopped too")
	for e in c.enemies:
		if e.def_id == "aegis_drone":
			c.deal_damage(e, 9999, "player", "lose_hp")
	check(not BossRules.shielded(c, boss), "shield down")
	check(c.deal_damage(boss, 30, "player") > 0, "window open")
	boss.moves = [{"name": "Idle", "effects": []}]
	var after := int(boss.rules["respawn"]["after"])
	for i in after:
		check(not BossRules.shielded(c, boss), "still down on move %d" % i)
		c.player.hp = c.player.max_hp
		c.end_turn()
	check(BossRules.shielded(c, boss), "pylons return after %d moves" % after)


func test_formation_redirects_single_target_hits() -> void:
	var c := _fight("monarch")
	var boss := _enemy(c, "hollow_monarch")
	var wisp := _enemy(c, "hollow_wisp")
	var hp := boss.hp
	c.energy = 10
	c.play_card(give(c, "jab"), c.enemies.find(boss))
	eq(boss.hp, hp, "boss untouched")
	check(wisp.hp < wisp.max_hp, "escort took the hit")
	Effects.resolve(c, {"op": "damage", "amount": 3, "to": "all_enemies"}, c.player, null)
	eq(boss.hp, hp - 3, "hit-all reaches the boss")
	c.deal_damage(wisp, 9999, "player", "lose_hp")
	c.play_card(give(c, "jab"), c.enemies.find(boss))
	check(boss.hp < hp - 3, "open once the escorts are down")


func test_bonded_survivor_powers_up() -> void:
	var c := _fight("twin_reavers")
	var a: Fighter = c.enemies[0]
	var b: Fighter = c.enemies[1]
	b.hp = 10
	c.deal_damage(a, 9999, "player", "lose_hp")
	eq(b.status("might"), 3, "survivor gains Boost")
	eq(b.hp, 10 + int(b.max_hp * 0.3), "and repairs")


func test_devour_eats_only_called_in_helpers() -> void:
	var c := _fight("bloom_a3b")
	var boss := _enemy(c, "mother_vat")
	c.spawn("spore_nurse")
	c.spawn("spore_nurse")
	boss.hp = 100
	Effects.resolve(c, {"op": "devour", "amount": 18, "stacks": 1}, boss, c.player)
	eq(c.living(c.enemies).size(), 1, "helpers eaten")
	eq(boss.hp, 136, "repair per helper")
	eq(boss.status("might"), 2, "Boost per helper")
	Effects.resolve(c, {"op": "devour", "amount": 18, "stacks": 1}, boss, c.player)
	eq(boss.hp, 136, "nothing to eat, nothing gained")


func test_spores_hatch_when_left_unplayed() -> void:
	var c := _fight("bloom_a2b")
	var n := c.draw_pile.size()
	Effects.resolve(c, {"op": "add_card", "card": "spore_pod", "amount": 2, "pile": "draw"}, c.enemies[0], c.player)
	eq(c.draw_pile.size(), n + 2, "shuffled into the draw pile")
	c.enemies[0].moves = [{"name": "Idle", "effects": []}]
	var i := give(c, "spore_pod")
	c.energy = 3
	check(c.play_card(i), "a spore can be cleared for RAM")
	eq(c.energy, 2, "costs 1")
	give(c, "spore_pod")
	var foes := c.living(c.enemies).size()
	c.hand = c.hand.filter(func(card: CardInstance) -> bool: return card.def.id == "spore_pod")
	c.end_turn()
	check(c.living(c.enemies).size() > foes, "an unplayed spore hatches")
	check(not c.discard_pile.any(func(card: CardInstance) -> bool: return card.def.id == "spore_pod"), "and is used up")


func test_boss_rules_have_text_and_chips() -> void:
	for id in db.enemies:
		var rules: Dictionary = db.enemies[id].get("rules", {})
		if rules.is_empty():
			continue
		check(not BossRules.describe(rules).is_empty(), "no rule text: " + id)
		for k in rules:
			check(BossRules.DESC.has(k) or k in ["leaves_at", "respawn"], "rule without a rules-page entry: " + k)


func test_bot_finishes_every_boss_and_elite() -> void:
	for id in db.encounters:
		if db.encounters[id].get("kind", "normal") == "normal":
			continue
		var deck: Array = []
		for i in 6:
			deck.append_array(["jab+", "brace+"])
		var c := Combat.create(db, db.make_deck(deck), id, GameRng.new(7), -1, {"max_hp": 5000, "extra_energy": 3, "enemy_hp_mult": 0.4})
		var r := Bot.run_combat(c, 120)
		check(not r["timeout"], "bot stuck on %s: %s" % [id, c.summary()])
		check(r["won"], "bot lost a 5000 HP fight on %s" % id)


func test_daemons_aim_past_a_shielded_boss() -> void:
	var c := _fight("chrome_a3b")
	var boss := _enemy(c, "hive_throne")
	var rule := {"triggers": [{"on": "turn_end", "effects": [{"op": "damage", "amount": 5, "to": "front"}]}]}
	c.summon("Drone", 3, rule)
	var pylon_hp := 0
	for e in c.enemies:
		if e.def_id == "aegis_drone":
			pylon_hp += e.hp + e.ward
	var boss_hp := boss.hp
	Talismans.fire(c, "turn_end")
	var after := 0
	for e in c.enemies:
		if e.def_id == "aegis_drone":
			after += e.hp + e.ward
	eq(boss.hp, boss_hp, "shielded boss untouched")
	eq(pylon_hp - after, 5, "the drone hit a pylon instead")
