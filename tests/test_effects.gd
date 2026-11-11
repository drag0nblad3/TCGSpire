extends TestCase
## One test per op/status. Combats here are built but not started, so the hand
## is empty and we hand-place cards with give().

var c: Combat


func before_each() -> void:
	c = make_combat([], "mites")
	c.energy = 10
	for e in c.enemies:
		e.hp = 30
		e.max_hp = 30


func test_damage_hits_target() -> void:
	c.play_card(give(c, "jab"), 1)
	eq(c.enemies[1].hp, 24)
	eq(c.enemies[0].hp, 30, "other enemy")


func test_upgrade_changes_numbers() -> void:
	c.play_card(give(c, "jab+"), 0)
	eq(c.enemies[0].hp, 21)


func test_ward_blocks_then_resets_on_turn_start() -> void:
	c.play_card(give(c, "brace"))
	eq(c.player.ward, 5)
	c.deal_damage(c.player, 3)
	eq(c.player.ward, 2, "ward after hit")
	eq(c.player.hp, c.player.max_hp)
	c._start_player_turn()
	eq(c.player.ward, 0, "ward reset")


func test_aoe_hits_all() -> void:
	c.play_card(give(c, "flare_volley"))
	eq(c.enemies[0].hp, 24)
	eq(c.enemies[1].hp, 24)


func test_multi_hit() -> void:
	c.play_card(give(c, "cinder_storm"))
	eq(c.enemies[0].hp, 18)


func test_burn_ticks_and_decays() -> void:
	c.enemies[0].add_status("burn", 3)
	Statuses.on_turn_start(c, c.enemies[0])
	eq(c.enemies[0].hp, 27)
	eq(c.enemies[0].status("burn"), 2)


func test_brittle_and_might_modify_attacks() -> void:
	c.enemies[0].add_status("brittle", 1)
	c.player.add_status("might", 2)
	c.play_card(give(c, "jab"), 0)
	eq(c.enemies[0].hp, 18, "(6+2)*1.5=12")


func test_weaken_reduces_attacks() -> void:
	c.player.add_status("weaken", 1)
	c.play_card(give(c, "jab"), 0)
	eq(c.enemies[0].hp, 26, "floor(6*0.75)=4")


func test_overcharge_costs_next_turn_energy() -> void:
	c.energy = 0
	c.play_card(give(c, "overclock"))
	eq(c.energy, 2)
	c._start_player_turn()
	eq(c.energy, 2, "3 - 1 overcharge")
	eq(c.player.status("overcharge"), 0, "cleared")


func test_damage_per_ward() -> void:
	c.player.ward = 9
	c.play_card(give(c, "riptide"), 0)
	eq(c.enemies[0].hp, 21)


func test_summon_and_board_limit() -> void:
	for i in 3:
		check(c.play_card(give(c, "sparring_dummy")), "summon %d" % i)
	eq(c.units.size(), 3)
	check(not c.can_play(give(c, "sparring_dummy")), "4th summon blocked")


func test_units_attack_on_end_turn() -> void:
	c.play_card(give(c, "ember_whelp"))
	c.end_turn()
	eq(c.enemies[0].hp, 27)


func test_rally_buffs_units() -> void:
	c.play_card(give(c, "ember_whelp"))
	c.play_card(give(c, "rally_cry"))
	eq(c.units[0].atk, 5)


func test_heal_capped() -> void:
	c.player.hp = c.player.max_hp - 5
	c.play_card(give(c, "field_medic"))
	eq(c.player.hp, c.player.max_hp)
	eq(c.exhaust_pile.size(), 1, "exhausted")


func test_enemy_front_hits_unit_first() -> void:
	var g := make_combat([], "golem")
	g.summon("Wall", 0, 50)
	g.enemies[0].move_idx = 2  # Crush, to: front
	g.end_turn()
	eq(g.units[0].hp, 38)
	eq(g.player.hp, g.player.max_hp)


func test_unknown_op_fails_validation() -> void:
	check(not Effects.validate({"op": "explode"}, "t").is_empty(), "unknown op accepted")
	check(not Effects.validate({"op": "damage", "amout": 3}, "t").is_empty(), "typo param accepted")
