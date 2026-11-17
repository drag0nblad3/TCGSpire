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
	leech.booting = false  # as if run last turn
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


func test_new_daemons_boot_before_they_act() -> void:
	var c := make_combat([])
	c.start()
	for e in c.enemies:
		e.hp = 99
	c.energy = 10
	c.play_card(give(c, "gun_turret"))
	var turret: Fighter = c.units[0]
	eq(turret.booting, true, "run this turn: booting")
	turret.ward = 99  # enemy hits would shorten its countdown
	var shots := func() -> int: return c.events.filter(func(e: Dictionary) -> bool: return e["t"] == "rule" and e.get("id", "") == turret.id).size()
	c.end_turn()
	eq(shots.call(), 0, "no end-of-turn shot on the turn it is run")
	eq(turret.booting, false, "ready on your next turn")
	eq(turret.hp, turret.max_hp, "its countdown starts a turn later")
	c.end_turn()
	eq(shots.call(), 1, "fires from the next turn")
	c.end_turn()
	eq(c.units.has(turret), false, "2 HP: closed after its shots")
	eq(shots.call(), 2, "same number of shots as before")


func test_booting_daemon_ignores_the_program_that_ran_it() -> void:
	var c := make_combat([])
	c.start()
	c.energy = 10
	c.player.hp -= 10
	var hp := c.player.hp
	c.play_card(give(c, "leech_line"))
	c.play_card(give(c, "jab"), 0)
	eq(c.player.hp, hp, "no repair from plays on the turn it is run")
	c.end_turn()
	hp = c.player.hp
	c.energy = 10
	c.play_card(give(c, "jab"), 0)
	eq(c.player.hp, hp + 1, "repairs from your next turn")


func test_flag_daemons_and_turn_opening_summons_are_ready_at_once() -> void:
	var c := make_combat([])
	c.start()
	c.energy = 10
	c.play_card(give(c, "sparring_dummy"))
	eq(c.units[0].booting, false, "always-on rules have nothing to wait for")
	var d := Combat.create(db, [], "mites", GameRng.new(1), -1, {"talismans": ["pocket_seed"]})
	d.start()
	eq(d.units.size(), 1)
	eq(d.units[0].booting, false, "an implant's combat-start daemon is ready")


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
