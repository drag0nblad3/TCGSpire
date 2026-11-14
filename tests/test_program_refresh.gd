extends TestCase

func arena() -> Combat:
	var c := make_combat([])
	c.energy = 20
	for enemy in c.enemies:
		enemy.hp = 1000
		enemy.max_hp = 1000
	return c

func test_refreshed_hydraulics_charge_without_changing_cost() -> void:
	for up in [false, true]:
		var c := arena()
		var card := db.instance("hydraulic_slam", up)
		eq(card.cost(), 2)
		for i in 3:
			CardPrograms.on_discard(card)
		eq(card.cooldown, 8)
		c.hand = [card]
		c.play_card(0, 0)
		eq(c.enemies[0].hp, 1000 - (22 if up else 18))
		eq(card.cooldown, 0)

func test_hard_reset_sequence_strips_before_bonus_hit() -> void:
	var c := arena()
	c.enemies[0].add_status("thorns", 3)
	c.enemies[0].add_status("might", 2)
	c.played_types = ["skill", "attack"]
	var hp := c.player.hp
	c.play_card(give(c, "hard_reset"), 0)
	eq(c.enemies[0].hp, 986)
	eq(c.enemies[0].status("might"), 0)
	eq(c.player.hp, hp - 3, "only base hit retaliates before strip")
	var d := arena()
	d.enemies[0].add_status("might", 2)
	d.play_card(give(d, "hard_reset"), 0)
	eq(d.enemies[0].hp, 991)
	eq(d.enemies[0].status("might"), 2, "no sequence no strip")

func test_overwatch_supports_daemon_and_passes_defence() -> void:
	var c := arena()
	c.summon("Test", 3)
	var receiver := db.instance("jab")
	c.hand = [receiver]
	c.play_card(give(c, "overwatch"))
	eq(c.units[0].hp, 4)
	eq(c.player.ward, 2)
	eq(receiver.relay, 2)
	eq(receiver.relay_cap, 4)
	c.play_card(0, 0)
	eq(c.player.ward, 4)

func test_dead_drop_draws_then_plants_on_following_card() -> void:
	for up in [false, true]:
		var c := arena()
		var host := db.instance("jab")
		c.draw_pile = [host, db.instance("brace"), db.instance("brace")]
		var card := db.instance("dead_drop", up)
		c.hand = [card]
		check(card.has_keyword("retain"), "Dead Drop keeps Cache")
		c.play_card(0)
		eq(c.hand.size(), 2 if up else 1)
		eq(c.player.ward, 0, "payload stays for a later draw")
		var next: CardInstance = c.draw_pile.back()
		eq(next.payload, 8 if up else 6)
		c.draw(1)
		eq(c.player.ward, 8 if up else 6)

func test_cold_storage_retains_two_defensive_instructions() -> void:
	var c := arena()
	var card := db.instance("cold_storage")
	c.hand = [card]
	for i in 3:
		c.play_card(give(c, "jab"), 0)
	eq(card.compiled.size(), 2)
	check(card.has_keyword("retain"), "Cold Storage retains")
	var hp: int = c.enemies[0].hp
	c.play_card(0)
	eq(c.player.ward, 8)
	eq(c.enemies[0].hp, hp, "attack instructions become Firewall")
	eq(card.compiled, [])

func test_bone_saw_nerve_lash_partnership_both_orders() -> void:
	var c := arena()
	c.play_card(give(c, "bramble_lash"), 0)
	c.play_card(give(c, "bone_saw"), 0)
	eq(c.player.status("thorns"), 5)
	var d := arena()
	d.draw_pile = db.make_deck(["brace"])
	d.play_card(give(d, "bone_saw"), 0)
	eq(d.player.status("thorns"), 1, "Bone Saw alone gives its base Feedback")
	d.play_card(give(d, "bramble_lash"), 0)
	eq(d.hand.size(), 1, "reverse order draws")
	eq(d.player.status("thorns"), 3)

func test_refresh_preserves_simple_staples_and_unique_names() -> void:
	eq(db.card("tidewall").effects, [{"op":"ward", "amount":12.0}])
	eq(db.card("second_wind").effects, [{"op":"ward", "amount":3.0}, {"op":"draw", "amount":2.0}])
	eq(db.card("molten_shield").name, "Heat Sink")
	eq(db.card("heat_sink").name, "Thermal Reservoir")
	var names := {}
	for card in db.cards.values():
		check(not names.has(card.name), "duplicate name: " + card.name)
		names[card.name] = true

func test_hydraulic_damage_mods_survive_rework() -> void:
	var card := db.instance("hydraulic_slam")
	var mod := db.mod("hardened_payload")
	check(CardMods.can_apply(mod, card), "charged attacks still accept damage mods")
	card.mod = mod
	CardPrograms.on_discard(card)
	eq(int(card.effects()[0]["amount"]), 12)
	eq(card.cooldown, 4, "mod does not increase charge step")
	var c := arena()
	c.hand = [card]
	c.play_card(0, 0)
	eq(c.enemies[0].hp, 984)
