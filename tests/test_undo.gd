extends TestCase
## Undo (CombatUndo): misclick protection that only works while nothing new was revealed.

const DECK := ["jab", "jab", "jab", "brace", "brace", "brace", "kindle", "undertow", "ember_whelp", "tidewall"]


func _started() -> Combat:
	var c := make_combat(DECK)
	c.undo_on = true
	c.start()
	return c


func test_undo_restores_the_board_exactly() -> void:
	var c := _started()
	var hand: Array = c.hand.map(func(k: CardInstance) -> String: return k.key())
	var energy := c.energy
	var events := c.events.size()
	var enemy_hp: int = c.enemies[0].hp
	check(c.play_card(give(c, "jab"), 0), "jab")
	check(c.enemies[0].hp < enemy_hp, "jab hit")
	check(c.can_undo(), "can undo a plain hit")
	check(c.undo(), "undo")
	eq(c.enemies[0].hp, enemy_hp, "enemy HP back")
	eq(c.energy, energy, "RAM back")
	eq(c.events.size(), events, "log cut back")
	# The jab given for the test comes back to hand; the rest of the hand is untouched.
	eq(c.hand.size(), hand.size() + 1)
	eq(c.hand.slice(0, hand.size()).map(func(k: CardInstance) -> String: return k.key()), hand)
	eq(c.discard_pile.size(), 0, "nothing left in discard")
	check(not c.can_undo(), "one step only")


func test_undo_is_one_step() -> void:
	var c := _started()
	c.energy = 10
	c.play_card(give(c, "jab"), 0)
	c.play_card(give(c, "jab"), 0)
	var hp: int = c.enemies[0].hp
	check(c.undo(), "undo second jab")
	check(c.enemies[0].hp > hp, "second hit taken back")
	check(not c.undo(), "first jab stays")


func test_draw_closes_the_window() -> void:
	var c := _started()
	c.energy = 10
	c.play_card(give(c, "seed_burst"))
	check(c.events.any(func(e: Dictionary) -> bool: return e["t"] == "draw"), "drew")
	check(not c.can_undo(), "a draw can't be taken back")


func test_random_roll_closes_the_window() -> void:
	var c := _started()
	var snap := CombatUndo.snapshot(c)
	c.rng.roll()
	check(not CombatUndo.revealed_nothing(c, snap), "rng use counts as new info")


func test_end_turn_closes_the_window() -> void:
	var c := _started()
	c.play_card(give(c, "jab"), 0)
	check(c.can_undo(), "before end turn")
	c.end_turn()
	check(not c.can_undo(), "after end turn")


func test_winning_play_cannot_be_undone() -> void:
	var c := _started()
	c.energy = 10
	for e in c.enemies:
		e.hp = 1
	c.play_card(give(c, "flare_volley"))
	eq(c.phase, Combat.Phase.WON)
	check(not c.can_undo(), "fight is over")


func test_undo_keeps_shared_references() -> void:
	var c := _started()
	c.energy = 10
	c.play_card(give(c, "leech_line"))
	var origin: CardInstance = c.hand[0].origin
	c.play_card(give(c, "jab"), 0)
	check(c.undo(), "undo jab")
	eq(c.units.size(), 1, "daemon still up")
	check(c.hand[0].origin == origin, "run deck card kept by reference")
	# Play continues normally after an undo.
	check(c.play_card(give(c, "jab"), 0), "jab again")


func test_off_by_default() -> void:
	var c := make_combat(DECK)
	c.start()
	c.play_card(give(c, "jab"), 0)
	check(not c.can_undo(), "bot/sims never snapshot")
