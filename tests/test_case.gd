class_name TestCase
extends RefCounted
## Base class for tests. Any method named test_* in tests/test_*.gd runs.
## Keep failure messages short and specific: the runner prints only failures.

var failures: Array[String] = []
var db: CardDB


func before_each() -> void:
	pass


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures.append(msg)


func eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		failures.append("%s expected %s, got %s" % [msg, var_to_str(expected).strip_edges(), var_to_str(actual).strip_edges()])


## Builds a combat with a fixed deck against a fixed encounter. Deck ids may end in "+".
func make_combat(deck_ids: Array, encounter: String = "mites", seed_in: int = 1) -> Combat:
	return Combat.create(db, db.make_deck(deck_ids), encounter, GameRng.new(seed_in))


## Puts the given card into hand directly (no draw) and returns its index.
func give(c: Combat, id: String) -> int:
	c.hand.append(db.make_deck([id])[0])
	return c.hand.size() - 1
