extends TestCase

const NEW_IDS := ["checksum", "reserve_parcel", "heat_sink", "arc_vent", "carrier_wave", "circuit_breaker", "spore_cache", "graft_compiler", "assembly_call", "queue_forge", "ghost_key", "backdoor", "rebroadcast", "encore_buffer"]

func arena() -> Combat:
	var c := make_combat([])
	c.energy = 30
	for enemy in c.enemies:
		enemy.hp = 1000
		enemy.max_hp = 1000
		enemy.moves = [{"name": "Wait", "effects": []}]
	return c

func test_wave2_defensive_and_area_cooldown() -> void:
	var c := arena()
	var shield := db.instance("heat_sink")
	CardPrograms.on_discard(shield)
	CardPrograms.on_discard(shield)
	check(shield.text().contains("+6 Firewall"), "charge text names Firewall")
	c.hand = [shield]
	c.play_card(0)
	eq(c.player.ward, 11)
	eq(shield.cooldown, 0)
	var vent := db.instance("arc_vent")
	CardPrograms.on_discard(vent)
	c.hand = [vent]
	c.play_card(0)
	for enemy in c.enemies:
		eq(enemy.hp, 992, "charged AoE hits each enemy")
	eq(vent.cooldown, 0)

func test_wave2_relay_cashout_keeps_firewall_but_ends_chain() -> void:
	var c := arena()
	var breaker := db.instance("circuit_breaker")
	var next := db.instance("brace")
	c.hand = [breaker, next]
	c.play_card(give(c, "carrier_wave"), 0)
	eq(breaker.relay, 2)
	check(breaker.text().contains("consume"), "cashout state explains consumption")
	c.play_card(0, 0)
	eq(c.enemies[0].hp, 986, "5 carrier + 5 breaker + 4 cashout")
	eq(c.player.ward, 2)
	eq(next.relay, 0, "signal not forwarded")
	eq(breaker.relay, 0)
	c.play_card(give(c, "circuit_breaker"), 0)
	eq(c.enemies[0].hp, 981, "no phantom cashout without Relay")

func test_wave2_specialist_compiler_and_four_slot_forge() -> void:
	var c := arena()
	var graft := db.instance("graft_compiler")
	var forge := db.instance("queue_forge")
	c.hand = [graft, forge]
	for i in 4:
		c.play_card(give(c, "jab"), 0)
	eq(graft.compiled.size(), 3)
	eq(forge.compiled.size(), 4)
	var hp: int = c.enemies[0].hp
	c.play_card(0)
	eq(c.player.ward, 11)
	eq(c.enemies[0].hp, hp, "specialist turns attacks into Firewall")
	c.hand.append(db.instance("brace"))
	c.play_card(0, 0)
	eq(c.enemies[0].hp, hp - 16)
	eq(c.hand[0].relay, 2)

func test_wave2_extended_handshakes_and_once_per_turn() -> void:
	var c := arena()
	c.play_card(give(c, "uplink"))
	c.draw_pile = db.make_deck(["brace"])
	var checksum := db.instance("checksum")
	c.hand = [checksum]
	c.play_card(0)
	eq(c.hand.size(), 1, "checksum draws after uplink")
	c.discard_pile.erase(checksum)
	c.hand.append(checksum)
	check(not c.play_card(1), "checksum redraw cannot loop")
	var d := arena()
	d.play_card(give(d, "downlink"), 0)
	var encore := db.instance("encore_buffer")
	d.hand = [encore]
	d.play_card(give(d, "rebroadcast"))
	eq(encore.relay, 2)
	var ram := d.energy
	d.play_card(0, 0)
	eq(d.energy, ram, "encore refunds cost after rebroadcast")
	d.discard_pile.erase(encore)
	d.hand.append(encore)
	check(not d.play_card(d.hand.find(encore), 0), "encore repeat blocked")

func test_wave2_sequence_orders_and_reserve_payload() -> void:
	var c := arena()
	c.play_card(give(c, "brace"))
	c.play_card(give(c, "brace"))
	c.play_card(give(c, "ghost_key"), 0)
	eq(c.enemies[0].status("brittle"), 1)
	c.play_card(give(c, "brace"))
	c.play_card(give(c, "backdoor"), 0)
	eq(c.enemies[0].status("brittle"), 3, "attack-script order enables Backdoor")
	var host := db.instance("brace")
	c.draw_pile = [host]
	c.play_card(give(c, "reserve_parcel"))
	eq(host.payload, 6)
	check(c.exhaust_pile.any(func(card: CardInstance) -> bool: return card.def.id == "reserve_parcel"), "parcel wipes")
	c.play_card(give(c, "spore_cache"))
	eq(host.payload, 6, "plant still does not stack")
	eq(c.player.status("regen"), 1)

func test_wave2_all_variants_validate_and_play() -> void:
	check(db.errors.is_empty(), str(db.errors))
	for id in NEW_IDS:
		for up in [false, true]:
			for fw in [0, 2]:
				var card := db.instance(id, up, fw)
				check(not card.text().contains("?"), id + " rules text")
				check(not CardInspector.glossary(card).is_empty(), id + " glossary")
				check(not card.def.upgrade_summary().is_empty(), id + " upgrade")
				check(CardArt.texture_for(id) != null, id + " illustration")
				var c := arena()
				c.hand = [card]
				check(c.play_card(0, 0), id + " playable")
				check(c.phase == Combat.Phase.PLAYER, id + " nonlethal")

func test_wave2_invalid_mechanic_parameters_rejected() -> void:
	check(not Effects.validate({"op":"cooldown", "amount":5, "step":2, "cap":4, "effect":"draw"}, "test").is_empty(), "unsupported cooldown")
	check(not Effects.validate({"op":"compile", "amount":3, "cap":3, "mode":"unknown"}, "test").is_empty(), "unknown compile mode")
	check(not Effects.validate({"op":"relay_cashout", "mult":0}, "test").is_empty(), "zero cashout")
