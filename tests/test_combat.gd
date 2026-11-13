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


func test_once_per_turn_cannot_repeat_after_being_redrawn_in_the_same_turn() -> void:
	var c := make_combat(["checksum", "focus+", "arc_bolt"], "last_mirror")
	c.start()
	var once: CardInstance = c.hand.filter(func(card: CardInstance) -> bool: return card.def.id == "checksum")[0]
	check(c.play_card(c.hand.find(once)), "first Checksum")
	check(c.play_card(c.hand.find_custom(func(card: CardInstance) -> bool: return card.def.id == "arc_bolt")), "Arc Bolt")
	check(c.play_card(c.hand.find_custom(func(card: CardInstance) -> bool: return card.def.id == "focus")), "Defrag")
	check(c.hand.has(once), "Defrag redrew Checksum")
	check(not c.play_card(c.hand.find(once)), "the redrawn copy is blocked")
	check(c.play_card(give(c, "checksum")), "a different copy still plays")
	c.end_turn()
	check(c.can_play(c.hand.find(once)), "the first copy is ready next turn")


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
