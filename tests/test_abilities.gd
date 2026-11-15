extends TestCase
## Card abilities wave: X cost, Dump (+ When dumped), pile counts, recover, Evolve.

var c: Combat


func before_each() -> void:
	c = make_combat([], "mites")
	c.energy = 3
	for e in c.enemies:
		e.hp = 60
		e.max_hp = 60


func _pile(n: int, id: String = "jab") -> Array:
	return db.make_deck(Array(range(n)).map(func(_i: int) -> String: return id))


func test_x_cost_spends_all_ram_and_scales() -> void:
	var i := give(c, "full_send")
	check(c.can_play(i), "X card playable")
	var hp: int = c.enemies[0].hp
	c.play_card(i, 0)
	eq(c.energy, 0, "all RAM spent")
	eq(c.x_spent, 3, "X recorded")
	eq(c.enemies[0].hp, hp - 21, "7X damage at X=3")
	eq(c.player.status("overcharge"), 1, "Overheat")
	check(c.events.any(func(e: Dictionary) -> bool: return e["t"] == "play" and int(e.get("x", -1)) == 3), "play event carries X")


func test_x_hits_scale_and_zero_ram_does_nothing() -> void:
	c.energy = 2
	var hp: int = c.enemies[0].hp
	c.play_card(give(c, "thermal_runaway"))
	eq(c.enemies[0].hp, hp - 10, "5 damage X=2 times")
	hp = c.enemies[0].hp
	c.play_card(give(c, "thermal_runaway"))
	eq(c.enemies[0].hp, hp, "X=0 deals nothing")


func test_x_cards_refuse_cost_mods() -> void:
	var card: CardInstance = db.make_deck(["full_send"])[0]
	check(not CardMods.can_apply({"id": "t", "cost": -1}, card), "no cost mod on X")
	eq(card.cost_label(), "X", "shows X")


func test_dump_is_a_cost() -> void:
	var i := give(c, "clear_cache")
	check(not c.can_play(i), "needs another card to dump")
	give(c, "jab")
	check(c.can_play(0), "playable with one other card")


func test_dump_uses_picks_first() -> void:
	var a := give(c, "jab")
	var b := give(c, "brace")
	var keep: CardInstance = c.hand[a]
	var toss: CardInstance = c.hand[b]
	c.draw_pile = _pile(5)
	c.play_card(give(c, "clear_cache"), -1, [toss])
	check(c.discard_pile.has(toss), "picked card dumped")
	check(c.hand.has(keep), "other card kept")
	eq(c.hand.size(), 3, "kept 1 + drew 2")


func test_dump_picks_when_dumped_and_locked_cards_first() -> void:
	give(c, "jab")
	give(c, "white_noise")
	c.draw_pile = _pile(5)
	c.play_card(give(c, "clear_cache"))
	check(c.discard_pile.any(func(k: CardInstance) -> bool: return k.def.id == "white_noise"), "When-dumped card went first")
	eq(c.enemies[0].status("weaken"), 2, "When dumped: Throttled to all")
	eq(c.hand.size(), 4, "strike + 2 drawn + 1 from White Noise")


func test_dump_hand_scales_per_card() -> void:
	for k in 3:
		give(c, "jab")
	var hp: int = c.enemies[0].hp
	c.play_card(give(c, "burn_the_logs"))
	eq(c.hand.size(), 0, "whole hand dumped")
	eq(c.last_dumped, 3, "three dumped")
	eq(c.enemies[0].hp, hp - 12, "4N damage")
	var plays := c.can_play(give(c, "burn_the_logs"))
	check(plays, "Dump your hand works with an empty hand")


func test_dump_charges_cooldown() -> void:
	give(c, "hydraulic_slam")
	c.draw_pile = _pile(5)
	c.play_card(give(c, "clear_cache"))
	var slam: CardInstance = c.discard_pile.filter(func(k: CardInstance) -> bool: return k.def.id == "hydraulic_slam")[0]
	check(slam.cooldown > 0, "dumped Cooldown card charged")


func test_pile_counts() -> void:
	c.draw_pile = _pile(10)
	var hp: int = c.enemies[0].hp
	c.play_card(give(c, "index_scan"), 0)
	eq(c.enemies[0].hp, hp - 7, "2 + half of 10")
	c.discard_pile = _pile(6)
	var ward := c.player.ward
	c.play_card(give(c, "backlog"))
	eq(c.player.ward, ward + 3 + 6, "3 + discard pile")
	eq(c.enemies[0].status("frail"), 1, "handshake: Fragmented")


func test_recover_from_wiped_skips_rootkits() -> void:
	var power: CardInstance = db.make_deck(["wild_bloom"])[0]
	var burst: CardInstance = db.make_deck(["root_access"])[0]
	c.exhaust_pile = [power, burst]
	c.draw_pile = _pile(3)
	var pool := c.recover_pool("wiped")
	check(not pool.has(power), "Rootkits stay wiped")
	c.play_card(give(c, "undelete"))
	check(not c.exhaust_pile.has(burst), "pulled out of Wiped")
	check(c.draw_pile.has(burst) or c.hand.has(burst), "back in the draw pile (or just drawn)")


func test_recover_to_top_uses_pick() -> void:
	var a: CardInstance = db.make_deck(["jab"])[0]
	var b: CardInstance = db.make_deck(["brace"])[0]
	c.discard_pile = [a, b]
	c.draw_pile = _pile(3)
	var i := give(c, "rewind_buffer")
	var req := c.pick_request(i)
	eq(str(req.get("kind", "")), "recover", "asks for a pick")
	c.play_card(i, -1, [a])
	check(c.draw_pile.back() == a, "picked card on top")


func test_evolve_after_twenty_runs_and_back_to_the_deck() -> void:
	var p := Profile.new_player(db)
	var run := RunState.start(db, p, RunState.default_picks(db, p), 7)
	run.deck.append(run.make_card("script_kiddie"))
	var src: CardInstance = run.deck.back()
	src.uses = 19
	var fight := run.start_combat(run.db.encounters.keys()[0])
	var copy: CardInstance = null
	for k in fight.draw_pile:
		if k.origin == src:
			copy = k
	check(copy != null, "combat copy points at the deck card")
	fight.draw_pile.erase(copy)
	fight.hand.append(copy)
	fight.energy = 3
	fight.play_card(fight.hand.size() - 1, 0)
	eq(copy.def.id, "black_hat", "evolved on run 20")
	check(fight.events.any(func(e: Dictionary) -> bool: return e["t"] == "evolve"), "evolve event")
	fight.sync_origins()
	eq(src.def.id, "black_hat", "deck card evolved")
	var back := RunState.from_dict(db, run.to_dict())
	eq(back.deck.back().def.id, "black_hat", "evolved form saved")
	var other := run.make_card("pilot_light")
	other.uses = 5
	run.deck.append(other)
	eq(RunState.from_dict(db, run.to_dict()).deck.back().uses, 5, "evolve progress saved")


func test_evolved_forms_never_drop() -> void:
	for id in ["black_hat", "wildfire", "seawall", "bloomhost", "echo_array", "war_drone"]:
		check(db.card(id) != null and db.card(id).token, id + " is a token")
		check(id not in db.ids_where(func(_k: CardDef) -> bool: return true), id + " not collectible")
		check(id not in Packs._pool(db, "common"), id + " not in packs")


func test_bot_plays_the_new_cards() -> void:
	var ids: Array = []
	for line in FileAccess.get_file_as_string("res://data/cards/abilities.json").split("\n"):
		if line.begins_with("{"):
			ids.append(JSON.parse_string(line.trim_suffix(","))["id"])
	var deck := db.make_deck(ids)
	var fight := Combat.create(db, deck, "mites", GameRng.new(3))
	for e in fight.enemies:
		e.hp = 999
		e.max_hp = 999
	fight.player.max_hp = 999
	fight.player.hp = 999
	var res := Bot.run_combat(fight, 12)
	check(res["turns"] > 0, "bot fight ran")
	var played := fight.play_counts()
	check(played.size() >= 8, "bot played a spread of the new cards (%d)" % played.size())
