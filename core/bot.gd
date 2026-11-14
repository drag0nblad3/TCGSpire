class_name Bot
extends RefCounted
## Greedy autoplayer for sims and tests. Each step it values every playable
## (card, target) pair from the real combat state and plays the best one per RAM.
## No search or state copies, so it costs about the same as a plain greedy bot:
## it just knows what damage, Firewall and statuses are actually worth right now
## (lethal checks, incoming damage, Exposed/Throttled math, wasted Firewall).


static func run_combat(c: Combat, max_turns: int = 50) -> Dictionary:
	c.start()
	var guard := 0
	while not c.is_over() and c.turn <= max_turns and guard < max_turns * 2:
		guard += 1
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
		var best_t := -1
		var best_score := 0.0
		for i in c.hand.size():
			if not c.can_play(i):
				continue
			var card: CardInstance = c.hand[i]
			for t in _targets(c, card):
				var s := score(c, card, t)
				if s > best_score:
					best_score = s
					best = i
					best_t = t
		if best < 0:
			break
		c.play_card(best, best_t)
	if c.phase == Combat.Phase.PLAYER:
		c.end_turn()


static func _targets(c: Combat, card: CardInstance) -> Array:
	if not c.needs_target(card):
		return [-1]
	var out: Array = []
	for i in c.enemies.size():
		if not c.enemies[i].is_dead():
			out.append(i)
	return out


## Value of playing `card` at enemy index t (-1 = no target), per RAM spent.
static func score(c: Combat, card: CardInstance, t: int = -1) -> float:
	var target: Fighter = c.enemies[t] if t >= 0 else null
	if target == null and c.needs_target(card):
		var alive := c.living(c.enemies)
		target = alive[0] if not alive.is_empty() else null
	var v := 0.0
	var ward := c.player.ward
	var effects := CardPrograms.effects(c, card)
	for e in effects:
		# The bot plays "ally" programs on itself (target -1), so value them that way.
		var ev: Dictionary = e
		if c.needs_ally(card) and not e.has("to"):
			ev = e.duplicate()
			ev["to"] = "self"
		v += _effect_value(c, ev, target, ward)
		if e.get("op", "") == "ward" and c.player in Effects.targets(c, e, c.player, target, "self"):
			ward += Effects.ward_gain(c.player, int(e.get("amount", 0)))
	# Hold a partial compiler when another affordable card can still feed it.
	if card.effects().any(func(e: Dictionary) -> bool: return e.get("op") == "compile"):
		var capacity := 0
		for effect in card.effects():
			if effect.get("op") == "compile":
				capacity = int(effect.get("cap", 3))
		if card.compiled.size() < capacity and c.hand.any(func(other: CardInstance) -> bool: return other != card and other.cost() <= c.energy and not other.has_keyword("unplayable") and not c.was_played_this_turn(other)):
			v *= 0.25
	# Loop programs get better every run this fight, so running one early pays later.
	if card.has_loop():
		v *= 1.2
	# Free cards are always worth it; otherwise prefer value per RAM.
	return v / maxf(card.cost(), 0.6) + 0.01


static func _effect_value(c: Combat, e: Dictionary, target: Fighter, ward: int) -> float:
	var n := float(e.get("amount", 0))
	var to := str(e.get("to", ""))
	var foes := c.living(c.enemies)
	match str(e.get("op", "")):
		"plant":
			return n * 0.55 if not c.draw_pile.is_empty() else 0.0
		"relay":
			return n * 1.2 if c.hand.size() > 1 else 0.0
		"damage":
			var hits := int(e.get("hits", 1))
			if to == "all_enemies":
				var s := 0.0
				for f in foes:
					s += _hit_value(c, f, int(n), hits)
				return s
			return _hit_value(c, target, int(n), hits) if target != null else 0.0
		"damage_per_ward":
			var amt := int(ward * float(e.get("mult", 1.0)))
			if to == "all_enemies":
				var s := 0.0
				for f in foes:
					s += _hit_value(c, f, amt, 1)
				return s
			return _hit_value(c, target, amt, 1) if target != null else 0.0
		"damage_per_status":
			var st := str(e.get("status", ""))
			var on_target := str(e.get("of", "")) == "target"
			var s := 0.0
			for f in (foes if to == "all_enemies" else ([target] if target != null else [])):
				var holder: Fighter = f if on_target else c.player
				s += _hit_value(c, f, int(float(e.get("base", 0)) + holder.status(st) * float(e.get("mult", 1.0))), 1)
			if e.get("consume", false) and not on_target:
				s -= c.player.status(st) * 0.8
			return s
		"amplify":
			var st := str(e.get("status", ""))
			var s := 0.0
			for f in (foes if to == "all_enemies" else ([c.player] if to == "self" else ([target] if target != null else []))):
				var extra := float(int(f.status(st) * (float(e.get("mult", 2.0)) - 1.0)))
				if extra > 0:
					s += _self_status_value(c, st, extra) if f == c.player else _enemy_status_value(c, f, st, extra)
			return s
		"strip":
			var s := 0.0
			for f in (foes if to == "all_enemies" else ([target] if target != null else [])):
				for k in f.statuses:
					if not Statuses.DEFS.get(k, {}).get("debuff", true):
						s += f.status(k) * (2.0 if k == "might" else 1.2) + (6.0 if k == "fortify" else 0.0)
			return s
		"sacrifice":
			if c.units.is_empty():
				return -2.0
			var u: Fighter = c.units[0]
			var fx := {"op": str(e.get("effect", "damage")), "amount": int(u.hp * float(e.get("mult", 1.0)))}
			if e.has("to"):
				fx["to"] = e["to"]
			return _effect_value(c, fx, target, ward) - DaemonRules.value({"hp": u.hp, "rule": u.rule}) * 0.6
		"ward":
			var gain := Effects.ward_gain(c.player, int(n) + c.rule_sum("ward_bonus"))
			var need := maxf(c.incoming_damage() - ward, 0.0)
			var retention := c.ward_retention
			if c.player.status("fortify") > 0 or c.rule_sum("keep_ward") > 0:
				retention = 1.0
			return minf(gain, need) * 1.15 + maxf(gain - need, 0.0) * lerpf(0.08, 0.45, retention)
		"apply":
			var st := str(e.get("status", ""))
			var stacks := float(e.get("stacks", 1))
			if to == "self":
				return _self_status_value(c, st, stacks)
			if to == "all_enemies":
				var s := 0.0
				for f in foes:
					s += _enemy_status_value(c, f, st, stacks)
				return s
			return _enemy_status_value(c, target, st, stacks) if target != null else 0.0
		"draw":
			return n * 3.5 if c.hand.size() + int(n) <= Combat.MAX_HAND else 1.0
		"energy":
			return n * 4.5
		"summon":
			return _summon_value(c, e)
		"rally":
			var rv := 0.0
			for u in c.units:
				rv += DaemonRules.value({"hp": 1, "rule": u.rule}) * n * 0.6
			return rv
		"heal":
			return minf(n, c.player.max_hp - c.player.hp) * 0.9
		"lose_hp":
			# HP lost stays lost for the rest of the run.
			return -n * (1.2 + 1.5 * (1.0 - float(c.player.hp) / maxf(c.player.max_hp, 1.0)))
		"cleanse":
			return Statuses.debuffs(c.player).size() * 3.0
		"add_card":
			return 2.0 * maxf(n, 1.0)
	return 0.0


## A daemon is worth its rule for the turns (HP) it adds; one that is already up only tops up.
static func _summon_value(c: Combat, e: Dictionary) -> float:
	var hp := int(e.get("hp", 1)) + c.daemon_hp
	var rule: Dictionary = e.get("rule", {})
	var flags: Dictionary = rule.get("flags", {})
	for u in c.units:
		if u.name == str(e.get("name", "")):
			# Re-running a daemon with a "closed" rule restarts it: the payoff lands now.
			var now := 0.0
			for trig in rule.get("triggers", []):
				if trig.get("on", "") == "closed":
					for fx in trig.get("effects", []):
						now += _effect_value(c, fx, null, c.player.ward)
			return now + DaemonRules.value({"hp": 1, "rule": rule}) * maxf(float(hp - u.hp), 0.0) * 0.6
	if c.units.size() >= c.board_slots:
		return 0.0
	var v := DaemonRules.value(e, c.daemon_hp)
	# State-aware tweaks for rules that only matter in some fights.
	if flags.has("burn_no_decay"):
		var burn := 0
		for f in c.living(c.enemies):
			burn += f.status("burn")
		v = minf(float(burn), 8.0) * 0.9 * minf(float(hp), 4.0) + 1.0
	if flags.has("keep_ward") and c.player.status("fortify") > 0:
		v *= 0.2
	if flags.has("thorns"):
		v += float(flags["thorns"]) * c.living(c.enemies).size()
	# Damage to ALL enemies from a rule lands later and only on who is still up:
	# price it on the live enemy count, at a discount for the delay.
	var aoe: Array = []
	for trig in rule.get("triggers", []):
		if trig.get("effects", []).any(func(fx: Dictionary) -> bool: return fx.get("op", "") == "damage" and fx.get("to", "") == "all_enemies"):
			aoe.append(trig)
	if not aoe.is_empty():
		var part := DaemonRules.value({"hp": e.get("hp", 1), "rule": {"triggers": aoe}}, c.daemon_hp)
		v += part * (float(c.living(c.enemies).size()) / 1.4 * 0.7 - 1.0)
	# Triggers that debuff every enemy: price them on the live enemies, not a flat guess.
	for trig in rule.get("triggers", []):
		var on := str(trig.get("on", ""))
		if on not in ["turn_start", "turn_end"]:
			continue
		var times := float(mini(hp, 4) - (1 if on == "turn_start" else 0))
		for fx in trig.get("effects", []):
			if fx.get("op", "") == "apply" and fx.get("to", "") == "all_enemies":
				var live := 0.0
				for f in c.living(c.enemies):
					live += _enemy_status_value(c, f, str(fx.get("status", "")), float(fx.get("stacks", 1)))
				v += maxf(live - 3.0 * float(fx.get("stacks", 1)), 0.0) * times
	return v


## Worth of hitting f for `amount` (before modifiers) `hits` times.
static func _hit_value(c: Combat, f: Fighter, amount: int, hits: int) -> float:
	if f == null or f.is_dead():
		return 0.0
	var per := Statuses.modify_attack(amount + c.rule_sum("attack_bonus"), c.player, f)
	var hp := f.hp
	var ward := f.ward
	var v := 0.0
	for i in hits:
		var blocked := mini(ward, per)
		ward -= blocked
		var dealt := mini(per - blocked, hp)
		hp -= dealt
		v += dealt + blocked * 0.25
		if f.status("thorns") > 0:
			v -= f.status("thorns") * 0.8
		if hp <= 0:
			# Lethal: also removes that enemy's incoming attack.
			v += 4.0 + c.intent_damage(f) * 1.2
			break
	return v


static func _enemy_status_value(c: Combat, f: Fighter, st: String, stacks: float) -> float:
	if f == null or f.is_dead():
		return 0.0
	match st:
		"burn":
			# Ticks stacks, stacks-1, ... but never more than its HP.
			return minf(stacks * (stacks + 1.0) / 2.0 + f.status("burn") * 0.5, float(f.hp)) * 0.7
		"brittle":
			var attacks := c.hand.filter(func(k: CardInstance) -> bool: return k.def.type == "attack").size()
			return stacks * (1.0 + attacks * 1.5) if f.status("brittle") == 0 else stacks * 1.2
		"weaken":
			return c.intent_damage(f) * 0.25 * minf(stacks, 2.0) + stacks * 0.8
		"frail":
			return stacks * 0.6
		"stall":
			if f.status("stall") > 0:
				return 0.0
			return c.intent_damage(f) * 1.1 + 2.0
	return stacks * 1.5


static func _self_status_value(c: Combat, st: String, stacks: float) -> float:
	match st:
		"might":
			return stacks * 2.5
		"regen":
			# Repairs damage taken later this fight too, not only what is missing now.
			return minf(stacks * (stacks + 1.0) / 2.0, c.player.max_hp - c.player.hp + c.incoming_damage()) * 0.8
		"thorns":
			var hits := 0
			for f in c.living(c.enemies):
				for e in f.current_move().get("effects", []):
					if e.get("op", "") == "damage":
						hits += int(e.get("hits", 1))
			return stacks * (hits + 1.5)
		"fortify":
			return 7.0 if c.player.status("fortify") == 0 else 0.5
		"charge":
			return stacks * 1.8
		"overcharge":
			return -3.0 * stacks
	return stacks * 1.5
