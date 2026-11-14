extends TestCase
## One test per op/status. Combats here are built but not started, so the hand
## is empty and we hand-place cards with give().

var c: Combat


func before_each() -> void:
	c = make_combat([], "mites")
	c.energy = 10
	for e in c.enemies:
		e.hp = 30
		e.max_hp = 30


func test_damage_hits_target() -> void:
	c.play_card(give(c, "jab"), 1)
	eq(c.enemies[1].hp, 24)
	eq(c.enemies[0].hp, 30, "other enemy")


func test_upgrade_changes_numbers() -> void:
	c.play_card(give(c, "jab+"), 0)
	eq(c.enemies[0].hp, 21)


func test_ward_blocks_then_resets_on_turn_start() -> void:
	c.play_card(give(c, "brace"))
	eq(c.player.ward, 5)
	c.deal_damage(c.player, 3)
	eq(c.player.ward, 2, "ward after hit")
	eq(c.player.hp, c.player.max_hp)
	c._start_player_turn()
	eq(c.player.ward, 0, "ward reset")


func test_aoe_hits_all() -> void:
	c.play_card(give(c, "flare_volley"))
	eq(c.enemies[0].hp, 24)
	eq(c.enemies[1].hp, 24)


func test_multi_hit() -> void:
	c.play_card(give(c, "cinder_storm"))
	eq(c.enemies[0].hp, 18)


func test_burn_ticks_and_decays() -> void:
	c.enemies[0].add_status("burn", 3)
	Statuses.on_turn_start(c, c.enemies[0])
	eq(c.enemies[0].hp, 27)
	eq(c.enemies[0].status("burn"), 2)


func test_brittle_and_might_modify_attacks() -> void:
	c.enemies[0].add_status("brittle", 1)
	c.player.add_status("might", 2)
	c.play_card(give(c, "jab"), 0)
	eq(c.enemies[0].hp, 18, "(6+2)*1.5=12")


func test_weaken_reduces_attacks() -> void:
	c.player.add_status("weaken", 1)
	c.play_card(give(c, "jab"), 0)
	eq(c.enemies[0].hp, 26, "floor(6*0.75)=4")


func test_overcharge_costs_next_turn_energy() -> void:
	c.energy = 0
	c.play_card(give(c, "overclock"))
	eq(c.energy, 2)
	c._start_player_turn()
	eq(c.energy, 2, "3 - 1 overcharge")
	eq(c.player.status("overcharge"), 0, "cleared")


func test_damage_per_ward() -> void:
	c.player.ward = 9
	c.play_card(give(c, "riptide"), 0)
	eq(c.enemies[0].hp, 21)


func test_bot_counts_firewall_granted_by_data_flood_against_all_enemies() -> void:
	for enemy in c.enemies:
		enemy.moves = []
	c.player.add_status("frail", 1)
	var idx := give(c, "crashing_wave")
	# 4 Firewall with Fragmented, then 4 damage to each enemy.
	var expected := (4.0 * 0.08 + 8.0) / 2.0 + 0.01
	check(is_equal_approx(Bot.score(c, c.hand[idx]), expected), "score uses Firewall from this card")
	eq(c.player.ward, 0, "scoring leaves combat state untouched")
	c.play_card(idx)
	eq(c.enemies[0].hp, 26)
	eq(c.enemies[1].hp, 26)


func test_summon_and_board_limit() -> void:
	for id in ["sparring_dummy", "ember_whelp", "scrap_golem"]:
		check(c.play_card(give(c, id)), "summon " + id)
	eq(c.units.size(), 3)
	check(not c.can_play(give(c, "drone_swarm")), "4th daemon blocked")
	c.hand.clear()
	c.units[1].hp = 1
	check(c.play_card(give(c, "ember_whelp")), "re-running a daemon tops it up")
	eq(c.units.size(), 3)
	eq(c.units[1].hp, 3, "HP topped back up")


func test_daemon_hp_is_its_countdown() -> void:
	c.play_card(give(c, "ember_whelp"))
	eq(c.units[0].hp, 3)
	c.end_turn()
	eq(c.enemies[0].hp, 30, "no auto-attack")
	eq(c.units[0].hp, 2, "loses 1 HP each turn")
	c.end_turn()
	eq(c.units[0].hp, 1)
	c.end_turn()
	eq(c.units.size(), 0, "closed after 3 rounds")


func test_hits_cost_a_daemon_one_hp() -> void:
	c.summon("A", 5)
	Effects.resolve(c, {"op": "damage", "amount": 40, "to": "all_enemies"}, c.enemies[0], c.player)
	eq(c.units[0].hp, 4, "a big hit still only costs 1")


func test_turret_rule_fires_at_turn_end() -> void:
	c.play_card(give(c, "drone_swarm"))
	c.end_turn()
	eq(c.enemies[0].hp, 28)


func test_rule_burn_does_not_decay() -> void:
	c.enemies[0].add_status("burn", 3)
	c.enemies[1].add_status("burn", 3)
	c.play_card(give(c, "ember_whelp"))
	c.end_turn()
	eq(c.enemies[0].status("burn"), 3, "kept while Burnworm runs")
	c.units.clear()
	c.end_turn()
	eq(c.enemies[0].status("burn"), 2, "decays again once it is gone")


func test_rule_bonuses() -> void:
	c.summon("A", 5, {"flags": {"attack_bonus": 2, "ward_bonus": 2, "burn_bonus": 1, "debuff_bonus": 1, "regen_bonus": 2}})
	c.play_card(give(c, "jab"), 0)
	eq(c.enemies[0].hp, 22, "6 + 2")
	c.play_card(give(c, "brace"))
	eq(c.player.ward, 7, "5 + 2")
	Effects.resolve(c, {"op": "apply", "status": "burn", "stacks": 2}, c.player, c.enemies[1])
	eq(c.enemies[1].status("burn"), 4, "2 + burn bonus + debuff bonus")
	Effects.resolve(c, {"op": "apply", "status": "regen", "stacks": 1, "to": "self"}, c.player, null)
	eq(c.player.status("regen"), 3)


func test_rule_keep_ward_and_guard() -> void:
	var g := make_combat([], "golem")
	g.summon("Gate", 5, {"flags": {"keep_ward": 1}})
	g.summon("Decoy", 3, {"flags": {"guard": 4}})
	eq(g.incoming_damage(), 8, "Slam 15 x0.85 = 12, - 4")
	g.player.ward = 20
	g.end_turn()
	eq(g.player.ward, 12, "20 - 8, and the Firewall is kept")
	eq(g.units[1].hp, 2)


func test_purge_hits_front_daemon_only() -> void:
	var g := make_combat([], "golem")
	var hp := g.player.hp
	Effects.resolve(g, {"op": "damage", "amount": 3, "to": "daemon"}, g.enemies[0], g.player)
	eq(g.player.hp, hp, "no daemon: purge does nothing")
	g.summon("A", 4)
	Effects.resolve(g, {"op": "damage", "amount": 3, "to": "daemon"}, g.enemies[0], g.player)
	eq(g.units[0].hp, 1, "purge takes its full number")
	Effects.resolve(g, {"op": "damage", "amount": 3, "to": "daemon"}, g.enemies[0], g.player)
	eq(g.units.size(), 0, "crashed daemon leaves the board")


func test_rally_and_daemon_hp_bonus() -> void:
	c.play_card(give(c, "ember_whelp"))
	c.play_card(give(c, "rally_cry"))
	eq(c.units[0].hp, 5)
	var g := make_combat([], "golem")
	g.daemon_hp = 2
	g.summon("A", 4)
	eq(g.units[0].hp, 6)


func test_patch_can_target_a_daemon() -> void:
	c.summon("A", 5)
	c.units[0].hp = 2
	check(c.play_card(give(c, "mending_moss"), 1), "ally index 1 = first daemon")
	eq(c.units[0].status("regen"), 3)
	eq(c.player.status("regen"), 0)
	c.end_turn()
	eq(c.units[0].hp, 4, "2 + 3 Patch (capped at 5) - 1 for the new turn")
	check(c.play_card(give(c, "mending_moss")), "no target = yourself")
	eq(c.player.status("regen"), 3)


func test_heal_capped() -> void:
	c.player.hp = c.player.max_hp - 5
	c.play_card(give(c, "field_medic"))
	eq(c.player.hp, c.player.max_hp)
	eq(c.exhaust_pile.size(), 1, "exhausted")


func test_enemy_front_hits_unit_first() -> void:
	var g := make_combat([], "golem")
	g.summon("Wall", 5)
	g.enemies[0].move_idx = 2  # Crush, to: front
	g.end_turn()
	eq(g.units[0].hp, 2, "5 - 2 hits - 1 for the new turn")
	eq(g.player.hp, g.player.max_hp)


func test_unknown_op_fails_validation() -> void:
	check(not Effects.validate({"op": "explode"}, "t").is_empty(), "unknown op accepted")
	check(not Effects.validate({"op": "damage", "amout": 3}, "t").is_empty(), "typo param accepted")


func test_charge_discharge_consumes() -> void:
	c.player.add_status("charge", 4)
	c.play_card(give(c, "discharge"), 0)
	eq(c.enemies[0].hp, 18, "4 charge x3")
	eq(c.player.status("charge"), 0, "consumed")


func test_loop_grows_each_run_this_fight() -> void:
	c.play_card(give(c, "mirror_step"))
	eq(c.player.ward, 5, "first run")
	var card: CardInstance = c.discard_pile.pop_back()
	eq(card.loops, 1)
	c.hand.append(card)
	c.play_card(c.hand.size() - 1)
	eq(c.player.ward, 12, "second run +2")
	check("Loop +2" in card.text(), "text keeps the tag")
	check("9" in card.text(), "text shows the grown number")


func test_loop_resets_next_fight() -> void:
	var deck: Array = db.make_deck(["mirror_step"])
	deck[0].loops = 3
	var c2: Combat = Combat.create(db, deck, "mites", GameRng.new(1))
	eq(c2.draw_pile[0].loops, 0)


func test_loop_bonus_daemon_doubles_growth() -> void:
	c.play_card(give(c, "ghost_thread"))
	c.play_card(give(c, "twin_cast"))
	eq(c.enemies[0].hp, 29)
	var card: CardInstance = c.discard_pile.pop_back()
	eq(card.loops, 2, "1 + Thread's extra step")
	c.hand.append(card)
	c.play_card(c.hand.size() - 1)
	eq(c.enemies[0].hp, 24, "1 + 2x2")


func test_frail_reduces_ward() -> void:
	c.player.add_status("frail", 1)
	c.play_card(give(c, "brace"))
	eq(c.player.ward, 3, "floor(5*0.75)")


func test_lag_skips_one_move_and_keeps_the_intent() -> void:
	var en: Fighter = c.enemies[0]
	var move: Dictionary = en.current_move()
	c.play_card(give(c, "packet_loss"), 0)
	c.play_card(give(c, "packet_loss"), 0)
	eq(en.status("stall"), 1, "Lagged never stacks")
	eq(c.intent_damage(en), 0, "a lagged enemy threatens nothing")
	eq(Intents.of(c, en)[0]["kind"], "stall")
	c.enemies[1].moves = []
	var hp := c.player.hp
	c.end_turn()
	eq(c.player.hp, hp, "skipped its move")
	eq(en.status("stall"), 0, "lag used up")
	eq(en.current_move(), move, "same intent waits")


func test_strip_removes_only_helpful_statuses() -> void:
	var en: Fighter = c.enemies[0]
	en.add_status("might", 3)
	en.add_status("thorns", 2)
	en.add_status("burn", 4)
	c.play_card(give(c, "void_siphon"), 0)
	eq(en.status("might"), 0)
	eq(en.status("thorns"), 0)
	eq(en.status("burn"), 4, "debuffs stay")
	eq(c.player.status("charge"), 2)


func test_amplify_doubles_a_status() -> void:
	var en: Fighter = c.enemies[0]
	en.add_status("burn", 3)
	c.play_card(give(c, "accelerant"), 0)
	eq(en.status("burn"), 6)
	eq(en.hp, 26)
	c.player.add_status("charge", 4)
	c.play_card(give(c, "recursion"))
	eq(c.player.status("charge"), 9, "amplify on self, then +1")


func test_damage_per_status_can_read_the_target() -> void:
	c.enemies[0].add_status("burn", 5)
	c.play_card(give(c, "backdraft"), 0)
	eq(c.enemies[0].hp, 21, "4 + 5 Virus")
	c.play_card(give(c, "backdraft"), 1)
	eq(c.enemies[1].hp, 26, "no Virus, base only")
	c.enemies[1].add_status("burn", 2)
	c.play_card(give(c, "chain_reaction"))
	eq(c.enemies[0].hp, 16, "each enemy takes its own Virus")
	eq(c.enemies[1].hp, 24)
	eq(c.enemies[0].status("burn"), 10)


func test_sacrifice_crashes_the_front_daemon_for_its_hp() -> void:
	c.play_card(give(c, "kamikaze_protocol"))
	eq(c.enemies[0].hp, 30, "no daemon: nothing happens")
	c.play_card(give(c, "sparring_dummy"))
	eq(c.units.size(), 1)
	c.play_card(give(c, "kamikaze_protocol"))
	eq(c.units.size(), 0, "daemon crashed")
	eq(c.enemies[0].hp, 22, "2x its 4 HP")
	eq(c.enemies[1].hp, 22)
	c.play_card(give(c, "sparring_dummy"))
	c.play_card(give(c, "armor_swap"))
	eq(c.player.ward, 12, "3x its 4 HP as Firewall")


func test_joint_op_cards_count_for_both_crews_and_obey_bans() -> void:
	var card: CardDef = db.card("fever_graft")
	check(card.is_of("ember") and card.is_of("bloom"), "counts as both crews")
	check(card.banned_by(["bloom"]) and card.banned_by(["ember"]), "banned if either crew is a target")
	check(not card.banned_by(["tide"]), "fine otherwise")
	eq(Jobs.check(db, "bloom", ["fever_graft", "fever_graft"], 4, ["void"]), "", "fills Wetware picks")
	check(Jobs.check(db, "tide", ["fever_graft"], 2, ["ember"]) != "", "Burner half is banned on a Flux job")
	check("fever_graft" not in Records.binder_ids(db, "ember", "full"), "joint ops stay out of crew binders")


func test_loop_trigger_fires_implants() -> void:
	var c := Combat.create(db, [], "mites", GameRng.new(1), -1, {"talismans": ["tick_counter", "recursion_core"]})
	for e in c.enemies:
		e.hp = 99
	c.energy = 9
	var card: CardInstance = null
	for id in db.cards:
		if db.make_deck([id])[0].has_loop():
			card = db.make_deck([id])[0]
			break
	c.hand.append(card)
	var ward := c.player.ward
	check(c.play_card(c.hand.size() - 1, 0), "played a Loop program")
	eq(card.loops, 2, "Recursion Core adds a step")
	check(c.player.ward >= ward + 2, "Tick Counter Firewall")


func test_closed_rule_fires_when_the_daemon_runs_out_or_is_crashed() -> void:
	c.play_card(give(c, "botnet_lease"))
	var hp: int = c.enemies[0].hp
	c.crash_daemon(c.units[0])
	eq(c.enemies[0].hp, hp - 8, "parting blast on crash")
	c.play_card(give(c, "botnet_lease"))
	hp = c.enemies[0].hp
	c.play_card(give(c, "botnet_lease"))
	eq(c.enemies[0].hp, hp - 8, "re-running restarts it: blast now")
	eq(c.units.size(), 1)
	eq(c.units[0].hp, 3, "fresh lease")
	c.crash_daemon(c.units[0])
	c.play_card(give(c, "botnet_lease"))
	c.units[0].hp = 1
	c.enemies[0].hp = 30
	hp = c.enemies[0].hp
	c.end_turn()
	eq(c.units.size(), 0, "ran out at turn start")
	eq(c.enemies[0].hp, hp - 3 - 8, "drip at turn end, then the blast")
