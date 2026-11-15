class_name Effects
extends RefCounted
## The effect vocabulary shared by cards AND enemy moves. An effect is a dict:
##   {"op": "damage", "amount": 6, "hits": 2, "to": "all_enemies"}
## To add an op: add it to OPS (with its params), then a branch in resolve() and
## describe(), then a test in tests/test_effects.gd.
##
## "to" is relative to the source: for the player, "all_enemies" = enemies;
## for an enemy, "all_enemies" = the player plus their units.

const OPS := {
	"handshake": ["card", "effects"],
	"sequence": ["types", "effects"],
	"cooldown": ["amount", "step", "cap", "effect", "to"],
	"compile": ["amount", "cap", "mode"],
	"plant": ["amount"],
	"relay": ["amount", "cap"],
	"relay_cashout": ["mult"],
	"damage": ["amount", "hits", "to"],
	"damage_per_ward": ["mult", "to"],
	"ward": ["amount", "to"],
	"heal": ["amount", "to"],
	"apply": ["status", "stacks", "to"],
	"draw": ["amount"],
	"energy": ["amount"],
	"summon": ["name", "hp", "rule"],
	"rally": ["amount"],
	"cleanse": ["to"],
	"add_card": ["card", "amount", "upgraded", "pile"],
	"spawn": ["enemy"],
	"devour": ["amount", "stacks"],
	"revive": ["enemy", "pct"],
	"lose_hp": ["amount", "to"],
	"damage_per_status": ["status", "mult", "base", "consume", "to", "of"],
	"amplify": ["status", "mult", "base", "to"],
	"strip": ["to"],
	"sacrifice": ["effect", "mult", "to"],
	"interrupt": ["kinds", "effects", "to"],
	"fuel": ["status", "stacks", "effects", "to"],
	"dump": ["amount"],
	"recover": ["from", "into", "amount"],
}

## Scaling: any effect may carry "per" (what to count), "per_mult" (default 1) and "per_key"
## (the number that grows; default LOOP_KEY's). At resolve time that number becomes
## its printed value + floor(count x per_mult). "x" counts the RAM an X-cost card spent.
const PER_KEYS := ["per", "per_mult", "per_key"]
const PER_SOURCES := {
	"x": "", "draw_pile": "N = cards in your draw pile.", "discard_pile": "N = cards in your discard pile.",
	"hand": "N = other cards in your hand.", "wiped": "N = your Wiped programs.", "dumped": "N = cards dumped.",
}
## Where "recover" takes a card from, and where it puts it.
const RECOVER_FROM := ["discard", "wiped"]
const RECOVER_INTO := ["draw", "top"]

## Loop: any effect below may carry "loop": n (a card keyword shown as "Loop +n").
## Each time the card runs in a fight, that number grows by n (CardInstance.looped).
const LOOP_KEY := {
	"damage": "amount", "ward": "amount", "heal": "amount", "apply": "stacks", "draw": "amount",
	"energy": "amount", "rally": "amount", "summon": "hp", "damage_per_status": "mult",
}

## Ops a "sacrifice" can turn the crashed daemon's HP into.
const SACRIFICE_EFFECTS := ["damage", "ward", "heal", "draw", "energy"]

## "daemon" (enemy moves, Purge): your front daemon only; nothing if none is running.
## "this" (daemon rule triggers only): the daemon whose rule is firing.
const TARGETS := ["target", "self", "all_enemies", "all_allies", "front", "daemon", "this"]


static func resolve(c: Combat, e: Dictionary, src: Fighter, target: Fighter) -> void:
	if e.has("per"):
		e = with_per(e, per_count(c, str(e["per"])))
	var op := str(e.get("op", ""))
	var n := int(e.get("amount", 0))
	match op:
		"plant":
			if not c.draw_pile.is_empty():
				var host: CardInstance = c.draw_pile.back()
				host.payload = maxi(host.payload, n)
				c.emit("plant", {"card": host.key(), "amount": host.payload})
		"relay":
			CardPrograms.pass_relay(c, n, int(e.get("cap", 6)))
		"handshake", "sequence", "cooldown", "compile", "relay_cashout":
			# CardPrograms expands these using the physical card and play history.
			pass
		"damage":
			if src == c.player:
				n += c.rule_sum("attack_bonus")
			for i in int(e.get("hits", 1)):
				for t in targets(c, e, src, target, "target"):
					if str(e.get("to", "")) == "daemon":
						c.deal_damage(t, n, src.id, "purge")
					else:
						c.attack(src, t, n)
		"damage_per_ward":
			var amt := int(src.ward * float(e.get("mult", 1.0)))
			for t in targets(c, e, src, target, "target"):
				c.attack(src, t, amt)
		"ward":
			for t in targets(c, e, src, target, "self"):
				if t == c.player and src == c.player:
					n += c.rule_sum("ward_bonus")
				var gain := ward_gain(t, n)
				t.ward += gain
				c.emit("ward", {"target": t.id, "amount": gain, "ward": t.ward})
		"heal":
			for t in targets(c, e, src, target, "self"):
				var before: int = t.hp
				t.hp = mini(t.max_hp, t.hp + n)
				c.emit("heal", {"target": t.id, "amount": t.hp - before, "hp": t.hp})
				BossRules.after_heal(c, t)
		"apply":
			var s := str(e.get("status", ""))
			var stacks := int(e.get("stacks", 1))
			for t in targets(c, e, src, target, "target"):
				var k := stacks + _apply_bonus(c, s, src, t)
				if s == "stall":
					k = mini(k, 1 - t.status("stall"))  # Lag never stacks past one skipped move.
					if k <= 0:
						continue
				t.add_status(s, k)
				c.emit("status", {"target": t.id, "status": s, "stacks": k, "total": t.status(s)})
		"draw":
			c.draw(n)
		"energy":
			c.energy += n
			c.emit("energy", {"amount": n})
		"summon":
			c.summon(str(e.get("name", "Unit")), int(e.get("hp", 1)), e.get("rule", {}))
		"rally":
			for u in c.units:
				u.hp += n
				u.max_hp = maxi(u.max_hp, u.hp)
				c.emit("uptime", {"target": u.id, "hp": u.hp})
			c.emit("rally", {"amount": n})
		"cleanse":
			for t in targets(c, e, src, target, "self"):
				for s in Statuses.debuffs(t):
					t.statuses.erase(s)
				c.emit("cleanse", {"target": t.id})
		"add_card":
			if str(e.get("pile", "hand")) == "draw":
				# Shuffled into your draw pile (spores).
				for i in maxi(n, 1):
					var planted := c.db.instance(str(e.get("card", "")), bool(e.get("upgraded", false)))
					if planted != null:
						c.draw_pile.insert(c.rng.range_i(0, c.draw_pile.size()), planted)
				c.emit("infect", {"card": str(e.get("card", "")), "amount": maxi(n, 1)})
				return
			for i in maxi(n, 1):
				if c.hand.size() >= Combat.MAX_HAND:
					break
				var inst := c.db.instance(str(e.get("card", "")), bool(e.get("upgraded", false)))
				if inst != null:
					c.hand.append(inst)
					c.emit("draw", {"card": inst.key(), "created": true})
		"spawn":
			c.spawn(str(e.get("enemy", "")))
		"revive":
			c.spawn(str(e.get("enemy", "")), float(e.get("pct", 0.5)))
		"devour":
			# Eats every helper it called in: repair and a status per helper eaten.
			var eaten: Array = c.living(c.enemies).filter(func(f: Fighter) -> bool: return f != src and f.spawned)
			for f in eaten:
				f.hp = 0
				c.emit("death", {"target": f.id, "devoured": true})
			if not eaten.is_empty():
				c.emit("devour", {"source": src.id, "count": eaten.size()})
				resolve(c, {"op": "heal", "amount": n * eaten.size(), "to": "self"}, src, src)
				if int(e.get("stacks", 0)) > 0:
					resolve(c, {"op": "apply", "status": "might", "stacks": int(e["stacks"]) * eaten.size(), "to": "self"}, src, src)
		"damage_per_status":
			var st := str(e.get("status", ""))
			var on_target := str(e.get("of", "")) == "target"
			for t in targets(c, e, src, target, "target"):
				var holder: Fighter = t if on_target else src
				c.attack(src, t, int(e.get("base", 0)) + int(holder.status(st) * float(e.get("mult", 1.0))))
				if e.get("consume", false) and on_target:
					t.statuses.erase(st)
			if e.get("consume", false) and not on_target:
				src.statuses.erase(st)
		"amplify":
			var st2 := str(e.get("status", ""))
			for t in targets(c, e, src, target, "target"):
				var extra := int(t.status(st2) * (float(e.get("mult", 2.0)) - 1.0))
				if t.status(st2) <= 0:
					extra = int(e.get("base", 0))  # "base": gain this many instead when there are none to multiply.
				if extra > 0:
					t.add_status(st2, extra)
					c.emit("status", {"target": t.id, "status": st2, "stacks": extra, "total": t.status(st2)})
		"strip":
			for t in targets(c, e, src, target, "target"):
				var gone: Array = t.statuses.keys().filter(func(k: String) -> bool: return not Statuses.DEFS.get(k, {}).get("debuff", true))
				for k in gone:
					t.statuses.erase(k)
				if not gone.is_empty():
					c.emit("strip", {"target": t.id, "statuses": gone})
		"sacrifice":
			if c.units.is_empty():
				return
			var u: Fighter = c.units[0]
			var amt3 := int(u.hp * float(e.get("mult", 1.0)))
			c.crash_daemon(u)
			var fx := {"op": str(e.get("effect", "damage")), "amount": amt3}
			if e.has("to"):
				fx["to"] = e["to"]
			resolve(c, fx, src, target)
		"lose_hp":
			for t in targets(c, e, src, target, "self"):
				_lose_hp(c, t, n, src)
		"dump":
			c.dump(n)
		"recover":
			c.recover(str(e.get("from", "discard")), str(e.get("into", "draw")), maxi(n, 1))
		"interrupt":
			# Cancels the named parts of each target's next move; "effects" pay off once per enemy cut.
			for t in targets(c, e, src, target, "target"):
				var cut: Array = Intents.matching(t, e.get("kinds", []))
				if t.rules.has("jam"):
					t.state["revealed"] = true
				if cut.is_empty():
					continue
				t.interrupted.append_array(cut)
				t.state["revealed"] = true
				c.emit("interrupt", {"target": t.id, "kinds": cut})
				for fx in e.get("effects", []):
					resolve(c, fx, src, t)
		"fuel":
			# Burns the target's own buff as fuel: only when it has the full amount; pays once per enemy.
			var st3 := str(e.get("status", "might"))
			var need := maxi(int(e.get("stacks", 1)), 1)
			for t in targets(c, e, src, target, "target"):
				if t.status(st3) < need:
					continue
				t.add_status(st3, -need)
				c.emit("status", {"target": t.id, "status": st3, "stacks": -need, "total": t.status(st3)})
				c.emit("fuel", {"target": t.id, "status": st3, "stacks": need})
				for fx in e.get("effects", []):
					resolve(c, fx, src, t)
		_:
			push_error("Unknown effect op: %s" % op)


## The number a "per" effect counts right now.
static func per_count(c: Combat, per: String) -> int:
	match per:
		"x": return c.x_spent
		"draw_pile": return c.draw_pile.size()
		"discard_pile": return c.discard_pile.size()
		"hand": return c.hand.size()
		"wiped": return c.exhaust_pile.size()
		"dumped": return c.last_dumped
	return 0


static func per_key(e: Dictionary) -> String:
	return str(e.get("per_key", LOOP_KEY.get(str(e.get("op", "")), "amount")))


## The effect with its "per" number filled in for `count`, and the per params removed.
static func with_per(e: Dictionary, count: int) -> Dictionary:
	var d := e.duplicate()
	var k := per_key(d)
	var base: Variant = d.get(k, 0)
	var add := int(floor(float(count) * float(d.get("per_mult", 1)) + 0.0001))
	d[k] = float(base) + add if base is float else int(base) + add
	for pk in PER_KEYS:
		d.erase(pk)
	return d


static func ward_gain(f: Fighter, amount: int) -> int:
	return int(amount * 0.75) if f.status("frail") > 0 else amount


## Extra stacks from daemon rules when the player applies a status.
static func _apply_bonus(c: Combat, status: String, src: Fighter, t: Fighter) -> int:
	if src != c.player or c.units.is_empty():
		return 0
	var bonus := 0
	if c.enemies.has(t):
		if status == "burn":
			bonus += c.rule_sum("burn_bonus")
		if Statuses.DEFS.get(status, {}).get("debuff", false) and status != "stall":
			bonus += c.rule_sum("debuff_bonus")
	elif c.is_friendly(t) and status == "regen":
		bonus += c.rule_sum("regen_bonus")
	return bonus


## HP loss ignores Ward.
static func _lose_hp(c: Combat, t: Fighter, n: int, src: Fighter) -> void:
	var w := t.ward
	t.ward = 0
	c.deal_damage(t, n, src.id, "lose_hp")
	t.ward = w


static func targets(c: Combat, e: Dictionary, src: Fighter, target: Fighter, default_to: String) -> Array:
	var to := str(e.get("to", default_to))
	var friendly := c.is_friendly(src)
	var foes: Array = c.living(c.enemies) if friendly else [c.player] + c.units
	var allies: Array = [c.player] + c.units if friendly else c.living(c.enemies)
	match to:
		"self":
			return [src]
		"target":
			if target != null and not target.is_dead():
				return [BossRules.guard_target(c, target)] if friendly else [target]
			return _front(c, foes, friendly)
		"all_enemies":
			return foes
		"all_allies":
			return allies
		"this":
			return [c.rule_daemon] if c.rule_daemon != null and c.units.has(c.rule_daemon) else []
		"front":
			if friendly:
				return _front(c, foes, friendly)
			return c.units.slice(0, 1) if not c.units.is_empty() else [c.player]
		"daemon":
			return [] if friendly else c.units.slice(0, 1)
	return []


## The first foe in line; for your programs a guarded boss's escort stands in front of it.
static func _front(c: Combat, foes: Array, friendly: bool) -> Array:
	if foes.is_empty():
		return []
	return [BossRules.guard_target(c, foes[0])] if friendly else [foes[0]]


static func describe(e: Dictionary) -> String:
	if e.has("per"):
		return _describe_per(e)
	var s := _describe(e)
	if not e.has("loop"):
		return s
	var tag := "Loop +%d" % int(e["loop"])
	if str(e.get("op", "")) == "summon":
		return s.replace(" HP):", " HP, %s):" % tag)
	var i := s.find(". ")
	if i < 0:
		i = s.length() - 1
	return s.substr(0, i) + " (%s)" % tag + s.substr(i)


## "Deal 3+N damage. N = cards in your draw pile." / "Gain 6X Firewall." / "Deal 5 damage X times."
static func _describe_per(e: Dictionary) -> String:
	var per := str(e["per"])
	var k := per_key(e)
	var d := e.duplicate()
	for pk in PER_KEYS:
		d.erase(pk)
	var base := int(d.get(k, 0))
	d[k] = 7777
	var s := describe(d)
	var letter := "X" if per == "x" else "N"
	var m := float(e.get("per_mult", 1))
	var note: String = PER_SOURCES.get(per, "")
	var term := letter
	if is_equal_approx(m, roundf(m)):
		term = (str(int(m)) if int(m) != 1 else "") + letter
	elif letter == "N":
		# Fractions count part of the pile: "N = half the cards in your draw pile, rounded down."
		var part := "half the" if is_equal_approx(m, 0.5) else "%s x the" % str(m)
		note = note.replace("N = cards", "N = %s cards" % part).replace("N = other cards", "N = %s other cards" % part).replace("N = your", "N = %s" % part).trim_suffix(".") + ", rounded down."
	else:
		term = "%s%s" % [str(m), letter]
	if base > 0:
		term = "%d+%s" % [base, term]
	s = s.replace("7777", term)
	return s + (" " + note if note != "" else "")


static func _describe(e: Dictionary) -> String:
	var op := str(e.get("op", ""))
	var n := int(e.get("amount", 0))
	var to := str(e.get("to", ""))
	var where := ""
	match to:
		"all_enemies":
			where = " to ALL enemies"
		"all_allies":
			where = " to you and your daemons"
		"front":
			where = " to the front enemy"
		"daemon":
			where = " to your front daemon"
	match op:
		"handshake":
			return "Handshake — if you played %s this turn: %s" % [Lexicon.card_name(str(e.get("card", ""))), " ".join(e.get("effects", []).map(func(fx: Dictionary) -> String: return describe(fx)))]
		"sequence":
			return "Sequence — after %s, in order this turn: %s" % [" → ".join(e.get("types", []).map(func(t: String) -> String: return Lexicon.type_name(t))), " ".join(e.get("effects", []).map(func(fx: Dictionary) -> String: return describe(fx)))]
		"cooldown":
			var effect := str(e.get("effect", "damage"))
			var base := _describe({"op": effect, "amount": n, "to": to})
			return "%s Cooldown: discarded unplayed at turn end, charge +%d %s (max +%d). Playing resets charge." % [base, int(e.get("step", 4)), "Firewall" if effect == "ward" else "damage", int(e.get("cap", 8))]
		"relay_cashout":
			return "Consume this card's Relay: deal %d damage per point. Keep its Firewall payout; do not pass it." % int(e.get("mult", 2))
		"compile":
			if e.get("mode", "mixed") == "ward":
				return "Compile up to %d other plays while held: each adds %d Firewall; Rootkits instead draw 1. Execute and clear on play." % [int(e.get("cap", 3)), n]
			return "Compile up to %d other plays while held: Exploit +%d damage, Script/Daemon +%d Firewall, Rootkit draw 1. Execute and clear on play." % [int(e.get("cap", 3)), n, n]
		"plant":
			return "Plant %d Firewall on the top draw-pile card: gain it once when drawn. Replaces weaker payloads." % n
		"relay":
			return "Give the leftmost other card in hand Relay %d: on play gain that much Firewall, then pass +1 (max %d). Stronger Relay replaces weaker." % [n, int(e.get("cap", 6))]
		"damage":
			var hits := int(e.get("hits", 1))
			if to == "daemon":
				return "Purge %d: your front daemon loses %d HP." % [n, n]
			return "Deal %d damage%s%s." % [n, (" %d times" % hits) if hits > 1 else "", where]
		"damage_per_ward":
			var mult := float(e.get("mult", 1.0))
			var m := "" if mult == 1.0 else " x%s" % str(mult)
			return "Deal damage equal to your Firewall%s%s." % [m, where]
		"ward":
			return "Gain %d Firewall." % n
		"heal":
			return ("This daemon repairs %d HP." % n) if to == "this" else ("Repair %d HP." % n)
		"apply":
			var s := Lexicon.status(str(e.get("status", "")))
			var stacks := int(e.get("stacks", 1))
			if str(e.get("status", "")) == "stall":
				# Lagged is on or off: never written as a stack count.
				if to == "all_enemies":
					return "Lag ALL enemies: each skips its next move (no effect on an enemy already Lagged)."
				return "Lag the target: it skips its next move (no effect if already Lagged)."
			if to == "self":
				return "Gain %d %s." % [stacks, s]
			return "Apply %d %s%s." % [stacks, s, where]
		"draw":
			return "Draw %d card%s." % [n, "" if n == 1 else "s"]
		"energy":
			return "Gain %d RAM." % n
		"summon":
			return "Run %s (%d HP): %s" % [e.get("name", "Unit"), int(e.get("hp", 1)), DaemonRules.describe(e.get("rule", {}))]
		"rally":
			return "Your daemons gain +%d HP." % n
		"cleanse":
			return "Purge your harmful statuses."
		"add_card":
			var nm := Lexicon.card_name(str(e.get("card", "?"))) + ("+" if e.get("upgraded", false) else "")
			if str(e.get("pile", "hand")) == "draw":
				return "Shuffle %d %s into your draw pile." % [maxi(n, 1), nm]
			return "Add %s to your hand." % nm if maxi(n, 1) == 1 else "Add %d %s to your hand." % [n, nm]
		"spawn":
			return "Call in a %s." % Lexicon.enemy_name(str(e.get("enemy", "?")))
		"devour":
			var boost := int(e.get("stacks", 0))
			return "Devour every helper it called in: repair %d HP%s for each one eaten." % [n, (" and gain %d %s" % [boost, Lexicon.status("might")]) if boost > 0 else ""]
		"revive":
			return "Restore its crashed twin at %d%% HP." % roundi(float(e.get("pct", 0.5)) * 100)
		"lose_hp":
			return "Lose %d HP." % n
		"damage_per_status":
			var st := Lexicon.status(str(e.get("status", "")))
			var base := int(e.get("base", 0))
			var mult := float(e.get("mult", 1.0))
			var num := str(int(mult)) if mult == int(mult) else str(mult)
			var txt := ("Deal %d damage +%s per %s%s." % [base, num, st, where]) if base > 0 else ("Deal %s damage per %s%s." % [num, st, where])
			if str(e.get("of", "")) == "target":
				var who := " on each enemy" if to == "all_enemies" else " on the target"
				txt = ("Deal %d damage +%s per %s%s." % [base, num, st, who]) if base > 0 else ("Deal %s damage per %s%s." % [num, st, who])
				return txt + (" Remove it." if e.get("consume", false) else "")
			return txt + (" Spend all %s." % st if e.get("consume", false) else "")
		"amplify":
			var st2 := Lexicon.status(str(e.get("status", "")))
			var m2 := float(e.get("mult", 2.0))
			var word: String = {2.0: "Double", 3.0: "Triple"}.get(m2, "Multiply by %s" % str(m2))
			var whose := "each enemy's" if to == "all_enemies" else ("your" if to == "self" else "the target's")
			var b := int(e.get("base", 0))
			if b > 0:
				var gain := "gain %d" % b if to == "self" else "apply %d" % b
				return "%s %s %s (%s if there is none)." % [word, whose, st2, gain]
			return "%s %s %s." % [word, whose, st2]
		"strip":
			return "Strip all helpful statuses from %s." % ("ALL enemies" if to == "all_enemies" else "the target")
		"dump":
			if n <= 0:
				return "Dump your hand: discard every other card in it."
			return "Dump %d: discard %s from your hand." % [n, "a card" if n == 1 else "%d cards" % n]
		"recover":
			var from := "a Wiped program (not a Rootkit)" if str(e.get("from", "")) == "wiped" else "a program from your discard pile"
			if maxi(n, 1) > 1:
				from = from.replace("a Wiped program", "%d Wiped programs" % n).replace("a program", "%d programs" % n)
			if str(e.get("into", "draw")) == "top":
				return "Put %s on top of your draw pile." % from
			return "Shuffle %s into your draw pile." % from
		"interrupt":
			var names: Array = e.get("kinds", []).map(func(k: String) -> String: return Lexicon.intent(k))
			var txt2 := "Interrupt %s%s." % [" or ".join(names), " on ALL enemies" if to == "all_enemies" else ""]
			var bonus: Array = e.get("effects", [])
			if not bonus.is_empty():
				txt2 += " If it cancels: %s" % " ".join(bonus.map(func(fx: Dictionary) -> String: return describe(fx)))
			return txt2
		"fuel":
			var bonus2: Array = e.get("effects", [])
			return "Fuel %d %s%s: %s" % [maxi(int(e.get("stacks", 1)), 1), Lexicon.status(str(e.get("status", "might"))),
				" (each enemy)" if to == "all_enemies" else "", " ".join(bonus2.map(func(fx: Dictionary) -> String: return describe(fx)))]
		"sacrifice":
			var m3 := float(e.get("mult", 1.0))
			var x := "its HP" if m3 == 1.0 else "%sx its HP" % (str(int(m3)) if m3 == int(m3) else str(m3))
			var then := ""
			match str(e.get("effect", "damage")):
				"damage": then = "deal damage equal to %s%s" % [x, where]
				"ward": then = "gain Firewall equal to %s" % x
				"heal": then = "repair HP equal to %s" % x
				"draw": then = "draw cards equal to %s" % x
				"energy": then = "gain RAM equal to %s" % x
			return "Crash your front daemon: %s." % then
	return "?%s?" % op


static func validate(e: Dictionary, where: String) -> Array[String]:
	var errs: Array[String] = []
	var op := str(e.get("op", ""))
	if not OPS.has(op):
		errs.append("%s: unknown op '%s'" % [where, op])
		return errs
	for k in e:
		if k in PER_KEYS:
			continue
		if k == "loop":
			if not LOOP_KEY.has(op) or not (e[k] is int or e[k] is float) or int(e[k]) <= 0:
				errs.append("%s: bad loop on op '%s'" % [where, op])
			continue
		if k != "op" and k not in OPS[op]:
			errs.append("%s: op '%s' has unknown param '%s'" % [where, op, k])
	if e.has("to") and str(e["to"]) not in TARGETS:
		errs.append("%s: bad 'to' value '%s'" % [where, e["to"]])
	if op in ["apply", "amplify"] and str(e.get("status", "")) == "stall":
		# Lagged never stacks, so no content may offer more than one at a time.
		if op == "amplify" or int(e.get("stacks", 1)) != 1 or e.has("loop") or str(e.get("to", "")) == "self":
			errs.append("%s: Lagged is applied once, to enemies only (no stacks, Loop or Amplify)" % where)
	if op in ["damage_per_status", "amplify"] and not Statuses.is_known(str(e.get("status", ""))):
		errs.append("%s: unknown status '%s'" % [where, e.get("status", "")])
	if op in ["handshake", "sequence"]:
		for fx in e.get("effects", []):
			errs.append_array(validate(fx, where))
			if fx.get("op", "") in ["handshake", "sequence", "cooldown", "compile", "relay_cashout"]:
				errs.append("%s: nested program condition" % where)
	if op == "interrupt":
		if e.get("kinds", []).is_empty():
			errs.append("%s: interrupt names no intent" % where)
		for k in e.get("kinds", []):
			if k not in Intents.INTERRUPTIBLE:
				errs.append("%s: interrupt can't cancel '%s'" % [where, k])
		for fx in e.get("effects", []):
			errs.append_array(validate(fx, where))
			if fx.get("op", "") in ["handshake", "sequence", "cooldown", "compile", "relay_cashout", "interrupt"]:
				errs.append("%s: nested program condition" % where)
	if op == "fuel":
		if not Statuses.is_known(str(e.get("status", ""))) or int(e.get("stacks", 0)) <= 0:
			errs.append("%s: fuel needs a known status and stacks" % where)
		if e.get("effects", []).is_empty():
			errs.append("%s: fuel pays nothing" % where)
		for fx in e.get("effects", []):
			errs.append_array(validate(fx, where))
			if fx.get("op", "") in ["handshake", "sequence", "cooldown", "compile", "relay_cashout", "interrupt", "fuel"]:
				errs.append("%s: nested program condition" % where)
	if op == "sequence":
		if e.get("types", []).is_empty():
			errs.append("%s: empty sequence" % where)
		for t in e.get("types", []):
			if t not in CardDef.TYPES:
				errs.append("%s: bad sequence type" % where)
	if op in ["cooldown", "compile", "plant", "relay"]:
		for k in OPS[op]:
			if k in ["effect", "to", "mode"]:
				continue
			if not (e.get(k) is int or e.get(k) is float) or int(e.get(k, 0)) <= 0:
				errs.append("%s: %s needs positive %s" % [where, op, k])
	if op == "cooldown" and str(e.get("effect", "damage")) not in ["damage", "ward"]:
		errs.append("%s: cooldown effect must be damage or ward" % where)
	if op == "compile" and str(e.get("mode", "mixed")) not in ["mixed", "ward"]:
		errs.append("%s: unknown compile mode" % where)
	if op == "relay_cashout" and int(e.get("mult", 0)) <= 0:
		errs.append("%s: relay cashout needs positive multiplier" % where)
	if op == "summon":
		errs.append_array(DaemonRules.validate(e.get("rule", {}), where))
	if op == "sacrifice" and str(e.get("effect", "damage")) not in SACRIFICE_EFFECTS:
		errs.append("%s: sacrifice can't become '%s'" % [where, e.get("effect", "")])
	if e.has("per"):
		if str(e["per"]) not in PER_SOURCES:
			errs.append("%s: bad 'per' value '%s'" % [where, e["per"]])
		if per_key(e) not in OPS[op] and per_key(e) != "hits":
			errs.append("%s: op '%s' can't scale '%s'" % [where, op, per_key(e)])
		if not (e.get("per_mult", 1) is int or e.get("per_mult", 1) is float) or float(e.get("per_mult", 1)) <= 0.0:
			errs.append("%s: per_mult must be positive" % where)
		if op == "apply" and str(e.get("status", "")) == "stall":
			errs.append("%s: Lagged can't scale" % where)
	elif e.has("per_mult") or e.has("per_key"):
		errs.append("%s: per_mult/per_key without per" % where)
	if op == "dump" and (not (e.get("amount", 0) is int or e.get("amount", 0) is float) or int(e.get("amount", 0)) < 0):
		errs.append("%s: dump amount must be 0 (whole hand) or more" % where)
	if op == "recover" and (str(e.get("from", "discard")) not in RECOVER_FROM or str(e.get("into", "draw")) not in RECOVER_INTO):
		errs.append("%s: recover needs from discard/wiped and into draw/top" % where)
	if e.has("of") and str(e["of"]) not in ["self", "target"]:
		errs.append("%s: bad 'of' value '%s'" % [where, e["of"]])
	if op == "apply" and not Statuses.is_known(str(e.get("status", ""))):
		errs.append("%s: unknown status '%s'" % [where, e.get("status", "")])
	return errs
