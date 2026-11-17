extends TestCase

const DECK := ["jab", "jab", "jab", "brace", "brace", "brace", "kindle", "undertow", "ember_whelp", "tidewall"]


func test_start_draws_hand_and_sets_energy() -> void:
	var c := make_combat(DECK)
	c.start()
	eq(c.hand.size(), 5)
	eq(c.energy, 3)
	eq(c.turn, 1)


func test_cannot_overspend_energy() -> void:
	var c := make_combat([])
	c.energy = 1
	check(c.play_card(give(c, "jab"), 0), "first jab")
	check(not c.play_card(give(c, "jab"), 0), "second jab with 0 energy")


func test_discard_and_reshuffle() -> void:
	var c := make_combat(DECK)
	c.start()
	c.end_turn()
	c.end_turn()
	# 10 cards, 5 per turn: turn 3 must reshuffle the discard.
	eq(c.hand.size(), 5)
	check(c.events.any(func(e: Dictionary) -> bool: return e["t"] == "reshuffle"), "no reshuffle event")


func test_overclock_is_wiped_after_one_use() -> void:
	var c := make_combat([])
	c.start()
	var before := c.energy
	check(c.play_card(give(c, "overclock")), "Overclock")
	eq(c.energy, before + 2)
	check(c.exhaust_pile.any(func(card: CardInstance) -> bool: return card.def.id == "overclock"), "wiped, not discarded")


func test_leech_repairs_you_and_itself() -> void:
	var c := make_combat([])
	c.start()
	c.energy = 10
	c.play_card(give(c, "leech_line"))
	var leech: Fighter = c.units[0]
	leech.hp -= 1
	c.player.hp -= 5
	var hp := c.player.hp
	c.play_card(give(c, "jab"), 0)
	eq(c.player.hp, hp + 1, "repairs you")
	eq(leech.hp, leech.max_hp, "repairs itself")


func test_win_when_all_enemies_die() -> void:
	var c := make_combat([])
	c.energy = 10
	for e in c.enemies:
		e.hp = 1
	c.play_card(give(c, "flare_volley"))
	eq(c.phase, Combat.Phase.WON)


func test_lose_when_player_dies() -> void:
	var c := make_combat(DECK)
	c.start()
	c.player.hp = 1
	c.end_turn()
	eq(c.phase, Combat.Phase.LOST)


func test_same_seed_same_event_log() -> void:
	var a := make_combat(DECK, "wisp_pack", 99)
	var b := make_combat(DECK, "wisp_pack", 99)
	Bot.run_combat(a)
	Bot.run_combat(b)
	eq(JSON.stringify(a.events), JSON.stringify(b.events), "event log")


func test_bot_finishes_starter_fight() -> void:
	var c := make_combat(DECK, "mites", 5)
	var r := Bot.run_combat(c)
	check(not r["timeout"], "bot timed out: " + c.summary())


func test_combat_log_reads_plays_and_enemy_moves() -> void:
	var c := make_combat(DECK)
	c.start()
	var idx := -1
	for i in c.hand.size():
		if c.hand[i].def.id == "jab":
			idx = i
	if idx < 0:
		idx = give(c, "jab")
	check(c.play_card(idx, 0), "jab played")
	c.end_turn()
	var text := CombatLog.as_text(c)
	check(text.contains("Turn 1"), "turn header: " + text)
	check(text.contains("You ran %s" % Lexicon.card_name("jab")), "play line: " + text)
	check(text.contains("    %s A took" % c.enemies[0].name), "indented damage, twins lettered: " + text)
	check(text.contains("Enemy turn"), "enemy header: " + text)
	check(text.contains(" used "), "enemy move: " + text)
	check(text.contains("Turn 2"), "next turn: " + text)
	for l: Dictionary in CombatLog.lines(c):
		check(str(l["text"]) != "", "empty line")


func test_daemons_closing_together_ignore_list_order() -> void:
	var c := Combat.create(db, [], "mites", GameRng.new(1), -1, {"talismans": ["server_farm"], "extra_slots": 1})
	c.start()
	for e in c.enemies:
		e.hp = 99
	c.summon("A", 1)
	c.summon("B", 1)
	c.summon("C", 3)
	c.end_turn()
	eq(c.units.map(func(u: Fighter) -> String: return u.name), ["C"], "both 1 HP daemons close, not just the first")
	eq(c.units[0].hp, 4, "3 - 1, then +1 per daemon that closed")


func test_summoned_enemies_wait_a_turn_before_acting() -> void:
	var c := make_combat([])
	c.start()
	for e in c.enemies:
		e.hp = 99
	give(c, "spore_pod")
	c.end_turn()
	var grub: Fighter = c.enemies.back()
	eq(grub.def_id, "vat_grub", "the unplayed pod hatched")
	var moved := func() -> int: return c.events.filter(func(e: Dictionary) -> bool: return e["t"] == "enemy_move" and e["source"] == grub.id).size()
	eq(moved.call(), 0, "hatched as your turn ended: sits out that enemy turn")
	c.spawn("vat_grub")
	var late: Fighter = c.enemies.back()
	c.end_turn()
	eq(moved.call(), 1, "acts from the next enemy turn")
	eq(c.events.filter(func(e: Dictionary) -> bool: return e["t"] == "enemy_move" and e["source"] == late.id).size(), 1, "spawned during your turn: you saw it, so it acts")


func test_enemy_spawned_mid_enemy_turn_waits() -> void:
	var c := make_combat([])
	c.start()
	c.phase = Combat.Phase.ENEMY
	c.spawn("vat_grub")
	eq(c.enemies.back().arrived, true)
	c.phase = Combat.Phase.PLAYER
	c.end_turn()
	eq(c.enemies.back().arrived, false, "cleared once your next turn ends")
