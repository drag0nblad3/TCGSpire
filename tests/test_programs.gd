extends TestCase

func arena() -> Combat:
	var c := make_combat([])
	c.energy = 30
	for enemy in c.enemies:
		enemy.hp = 1000
		enemy.max_hp = 1000
		enemy.moves = [{"name": "Wait", "effects": []}]
	return c

func test_handshake_both_orders_and_turn_reset() -> void:
	var c := arena()
	c.draw_pile = db.make_deck(["jab", "brace"])
	c.play_card(give(c, "downlink"), 0)
	eq(c.enemies[0].hp, 994, "standalone downlink")
	c.play_card(give(c, "uplink"))
	eq(c.hand.size(), 2, "handshake draws two")
	c.end_turn()
	eq(c.played_ids, [], "new turn clears partners")
	var d := arena()
	d.play_card(give(d, "uplink"))
	d.play_card(give(d, "downlink"), 0)
	eq(d.enemies[0].hp, 991, "partner bonus hits selected enemy too")
	eq(d.enemies[1].hp, 997, "partner bonus hits all enemies")

func test_cooldown_discard_cap_reset_and_copies() -> void:
	var c := arena()
	var card := db.instance("capacitor_lance")
	var other := db.instance("capacitor_lance")
	c.hand = [card]
	c.hand_size = 0
	c.end_turn()
	eq(card.cooldown, 4)
	eq(other.cooldown, 0, "separate physical copy")
	for i in 3:
		CardPrograms.on_discard(card)
	eq(card.cooldown, 8)
	c.discard_pile.erase(card)
	c.hand = [card]
	c.play_card(0, 0)
	eq(c.enemies[0].hp, 986)
	eq(card.cooldown, 0)
	c.hand = [other]
	other.mod = {"keywords_add": ["retain"]}
	c.end_turn()
	eq(other.cooldown, 0, "retained card never charges")

func test_compile_retains_caps_executes_and_clears() -> void:
	var c := arena()
	var compiler := db.instance("pocket_compiler")
	c.hand = [compiler]
	c.play_card(give(c, "jab"), 0)
	c.play_card(give(c, "brace"))
	c.play_card(give(c, "jab"), 0)
	c.play_card(give(c, "brace"))
	eq(compiler.compiled, ["attack", "skill", "attack"])
	c.hand_size = 0
	c.end_turn()
	check(compiler in c.hand, "compiler retains")
	var hp: int = c.enemies[0].hp
	c.play_card(c.hand.find(compiler), 0)
	eq(c.enemies[0].hp, hp - 6)
	eq(c.player.ward, 6, "base and compiled Firewall")
	eq(compiler.compiled, [])

func test_compile_cannot_record_play_that_drew_it() -> void:
	var c := arena()
	var compiler := db.instance("pocket_compiler")
	c.draw_pile = [compiler]
	c.played_ids = ["downlink"]
	c.play_card(give(c, "uplink"))
	check(compiler in c.hand, "compiler drawn")
	eq(compiler.compiled, [], "was not held when play began")

func test_compile_power_and_unit_instructions() -> void:
	var c := arena()
	var compiler := db.instance("pocket_compiler", true)
	compiler.compiled = ["power", "unit"]
	c.draw_pile = db.make_deck(["brace"])
	c.hand = [compiler]
	c.play_card(0, 0)
	eq(c.hand.size(), 1)
	eq(c.player.ward, 8)

func test_plant_once_strongest_and_empty_pile() -> void:
	var c := arena()
	var host := db.instance("jab")
	c.draw_pile = [host]
	Effects.resolve(c, {"op": "plant", "amount": 9}, c.player, null)
	Effects.resolve(c, {"op": "plant", "amount": 7}, c.player, null)
	eq(host.payload, 9)
	c.rng.shuffle(c.draw_pile)
	c.draw(1)
	eq(c.player.ward, 9)
	eq(host.payload, 0)
	c.hand.erase(host)
	c.discard_pile.append(host)
	c.draw(1)
	eq(c.player.ward, 9, "not triggered again")
	Effects.resolve(c, {"op": "plant", "amount": 9}, c.player, null)
	eq(host.payload, 0, "empty draw pile is harmless")

func test_sequence_exact_recent_types_and_turn_boundary() -> void:
	var c := arena()
	c.play_card(give(c, "brace"))
	c.play_card(give(c, "jab"), 0)
	var hp: int = c.enemies[0].hp
	c.play_card(give(c, "breach_sequence"), 0)
	eq(c.enemies[0].hp, hp - 11)
	hp = c.enemies[0].hp
	c.play_card(give(c, "breach_sequence"), 0)
	eq(c.enemies[0].hp, hp - 6, "intervening attack breaks sequence")
	c.played_types = ["skill", "attack"]
	c.end_turn()
	eq(c.played_types, [])

func test_relay_passes_grows_caps_and_ends() -> void:
	var c := arena()
	var first := db.instance("jab")
	var second := db.instance("brace")
	c.hand = [first, second]
	c.play_card(give(c, "signal_baton"))
	eq(first.relay, 2)
	c.play_card(0, 0)
	eq(first.relay, 0)
	eq(second.relay, 3)
	eq(c.player.ward, 6, "baton plus relay")
	CardPrograms.pass_relay(c, 2, 5)
	eq(second.relay, 3, "weaker relay cannot replace stronger")
	second.relay = 5
	c.hand.append(first)
	c.play_card(0)
	eq(first.relay, 5, "pass is capped")
	c.play_card(0, 0)
	eq(first.relay, 0, "no recipient ends relay")

func test_combat_memory_copy_and_reset_without_mutating_run_deck() -> void:
	var card := db.instance("pocket_compiler")
	card.compiled = ["attack"]
	card.cooldown = 8
	card.payload = 9
	card.relay = 3
	card.relay_cap = 5
	var preview := card.copy()
	preview.compiled.append("skill")
	eq(card.compiled.size(), 1, "preview state is independent")
	var c := Combat.create(db, [card], "mites", GameRng.new(7))
	var fresh: CardInstance = c.draw_pile[0]
	eq(fresh.compiled, [])
	eq(fresh.cooldown + fresh.payload + fresh.relay + fresh.relay_cap, 0)
	eq(card.payload, 9, "combat does not mutate source deck")

func test_new_cards_text_upgrade_firmware_and_bot() -> void:
	for id in ["uplink", "downlink", "capacitor_lance", "pocket_compiler", "seed_packet", "breach_sequence", "signal_baton"]:
		for upgraded in [false, true]:
			var card := db.instance(id, upgraded, 2)
			check(not card.text().contains("?"), id + " rules")
			check(not card.def.upgrade_summary().is_empty(), id + " upgrade")
			check(not CardInspector.glossary(card).is_empty(), id + " glossary")
			check(Bot.score(arena(), card, 0) > 0, id + " bot score")
	var charged := db.instance("capacitor_lance", false, 2)
	check(int(charged.effects()[0]["amount"]) > 6, "firmware scales new damage")

func test_new_mechanics_deterministic_in_full_fights() -> void:
	var deck := ["uplink", "downlink", "capacitor_lance", "pocket_compiler", "seed_packet", "breach_sequence", "signal_baton", "jab", "brace", "brace"]
	var a := make_combat(deck, "golem", 123)
	var b := make_combat(deck, "golem", 123)
	Bot.run_combat(a)
	Bot.run_combat(b)
	eq(a.events, b.events)
	check(a.is_over(), "combo deck fight finishes")

func test_invalid_play_cannot_consume_memory_or_advance_sequence() -> void:
	var c := arena()
	var card := db.instance("capacitor_lance")
	card.cooldown = 8
	card.relay = 3
	c.hand = [card]
	check(not c.play_card(0, 99), "invalid target rejected")
	eq(card.cooldown, 8)
	eq(card.relay, 3)
	eq(c.played_types, [])
	c.energy = 0
	check(not c.play_card(0, 0), "unaffordable play rejected")
	eq(card.cooldown, 8)

func test_full_hand_does_not_consume_planted_payload() -> void:
	var c := arena()
	var host := db.instance("jab")
	host.payload = 7
	c.draw_pile = [host]
	for i in Combat.MAX_HAND:
		give(c, "brace")
	c.draw(1)
	eq(host.payload, 7)
	eq(c.player.ward, 0)
	c.hand.pop_back()
	c.draw(1)
	eq(host.payload, 0)
	eq(c.player.ward, 7)
