class_name Bot
extends RefCounted
## Simple greedy autoplayer. Not smart, but consistent: it exists so balance
## changes can be measured with tools/sim.gd instead of playing by hand.


static func run_combat(c: Combat, max_turns: int = 50) -> Dictionary:
	c.start()
	while not c.is_over() and c.turn <= max_turns:
		play_turn(c)
	return {
		"won": c.phase == Combat.Phase.WON,
		"turns": c.turn,
		"hp": c.player.hp,
		"timeout": not c.is_over(),
	}


static func play_turn(c: Combat) -> void:
	var guard := 0
	while c.phase == Combat.Phase.PLAYER and guard < 30:
		guard += 1
		var best := -1
		var best_score := 0.0
		for i in c.hand.size():
			if not c.can_play(i):
				continue
			var s := score(c, c.hand[i])
			if s > best_score:
				best_score = s
				best = i
		if best < 0:
			break
		c.play_card(best, _pick_target(c))
	if c.phase == Combat.Phase.PLAYER:
		c.end_turn()


static func score(c: Combat, card: CardInstance) -> float:
	var need_ward := maxi(c.incoming_damage() - c.player.ward, 0)
	var s := 0.0
	for e in card.effects():
		var n := float(e.get("amount", 0))
		match str(e.get("op", "")):
			"damage":
				var mult := float(e.get("hits", 1))
				if e.get("to", "") == "all_enemies":
					mult *= c.living(c.enemies).size()
				s += n * mult
			"damage_per_ward":
				s += c.player.ward * float(e.get("mult", 1.0))
			"ward":
				s += minf(n, need_ward) * 1.2 + n * 0.2
			"apply":
				s += float(e.get("stacks", 1)) * 2.5
			"draw", "energy":
				s += n * 4.0
			"summon":
				s += float(e.get("atk", 0)) * 3.0 + float(e.get("hp", 0)) * 0.5
			"rally":
				s += n * c.units.size() * 2.0
			"heal":
				s += minf(n, c.player.max_hp - c.player.hp)
	# Free cards are always worth it; otherwise prefer value per energy.
	return s / maxf(card.cost(), 0.5) + 0.01


static func _pick_target(c: Combat) -> int:
	var best := -1
	for i in c.enemies.size():
		var e: Fighter = c.enemies[i]
		if e.is_dead():
			continue
		if best < 0 or e.hp < c.enemies[best].hp:
			best = i
	return best
