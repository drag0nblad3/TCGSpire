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
