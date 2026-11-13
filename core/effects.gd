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
	"add_card": ["card", "amount", "upgraded"],
	"spawn": ["enemy"],
	"lose_hp": ["amount", "to"],
	"damage_per_status": ["status", "mult", "base", "consume", "to"],
}

## "daemon" (enemy moves, Purge): your front daemon only; nothing if none is running.
const TARGETS := ["target", "self", "all_enemies", "all_allies", "front", "daemon"]


static func resolve(c: Combat, e: Dictionary, src: Fighter, target: Fighter) -> void:
	var op := str(e.get("op", ""))
	var n := int(e.get("amount", 0))
	match op:
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
				var w := int(n * 0.75) if t.status("frail") > 0 else n
				t.ward += w
				c.emit("ward", {"target": t.id, "amount": w, "ward": t.ward})
		"heal":
			for t in targets(c, e, src, target, "self"):
				var before: int = t.hp
				t.hp = mini(t.max_hp, t.hp + n)
				c.emit("heal", {"target": t.id, "amount": t.hp - before, "hp": t.hp})
		"apply":
			var s := str(e.get("status", ""))
			var stacks := int(e.get("stacks", 1))
			for t in targets(c, e, src, target, "target"):
				var k := stacks + _apply_bonus(c, s, src, t)
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
			for i in maxi(n, 1):
				if c.hand.size() >= Combat.MAX_HAND:
					break
				var inst := c.db.instance(str(e.get("card", "")), bool(e.get("upgraded", false)))
				if inst != null:
					c.hand.append(inst)
					c.emit("draw", {"card": inst.key(), "created": true})
		"spawn":
			c.spawn(str(e.get("enemy", "")))
		"damage_per_status":
			var st := str(e.get("status", ""))
			var amt2 := int(e.get("base", 0)) + int(src.status(st) * float(e.get("mult", 1.0)))
			for t in targets(c, e, src, target, "target"):
				c.attack(src, t, amt2)
			if e.get("consume", false):
				src.statuses.erase(st)
		"lose_hp":
			for t in targets(c, e, src, target, "self"):
				_lose_hp(c, t, n, src)
		_:
			push_error("Unknown effect op: %s" % op)


## Extra stacks from daemon rules when the player applies a status.
static func _apply_bonus(c: Combat, status: String, src: Fighter, t: Fighter) -> int:
	if src != c.player or c.units.is_empty():
		return 0
	var bonus := 0
	if c.enemies.has(t):
		if status == "burn":
			bonus += c.rule_sum("burn_bonus")
		if Statuses.DEFS.get(status, {}).get("debuff", false):
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
				return [target]
			return foes.slice(0, 1)
		"all_enemies":
			return foes
		"all_allies":
			return allies
		"front":
			if friendly:
				return foes.slice(0, 1)
			return c.units.slice(0, 1) if not c.units.is_empty() else [c.player]
		"daemon":
			return [] if friendly else c.units.slice(0, 1)
	return []


static func describe(e: Dictionary) -> String:
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
			return "Repair %d HP." % n
		"apply":
			var s := Lexicon.status(str(e.get("status", "")))
			var stacks := int(e.get("stacks", 1))
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
			return "Add %s to your hand." % nm if maxi(n, 1) == 1 else "Add %d %s to your hand." % [n, nm]
		"spawn":
			return "Call in a %s." % Lexicon.enemy_name(str(e.get("enemy", "?")))
		"lose_hp":
			return "Lose %d HP." % n
		"damage_per_status":
			var st := Lexicon.status(str(e.get("status", "")))
			var base := int(e.get("base", 0))
			var mult := float(e.get("mult", 1.0))
			var num := str(int(mult)) if mult == int(mult) else str(mult)
			var txt := ("Deal %d damage +%s per %s%s." % [base, num, st, where]) if base > 0 else ("Deal %s damage per %s%s." % [num, st, where])
			return txt + (" Spend all %s." % st if e.get("consume", false) else "")
	return "?%s?" % op


static func validate(e: Dictionary, where: String) -> Array[String]:
	var errs: Array[String] = []
	var op := str(e.get("op", ""))
	if not OPS.has(op):
		errs.append("%s: unknown op '%s'" % [where, op])
		return errs
	for k in e:
		if k != "op" and k not in OPS[op]:
			errs.append("%s: op '%s' has unknown param '%s'" % [where, op, k])
	if e.has("to") and str(e["to"]) not in TARGETS:
		errs.append("%s: bad 'to' value '%s'" % [where, e["to"]])
	if op == "damage_per_status" and not Statuses.is_known(str(e.get("status", ""))):
		errs.append("%s: unknown status '%s'" % [where, e.get("status", "")])
	if op == "summon":
		errs.append_array(DaemonRules.validate(e.get("rule", {}), where))
	if op == "apply" and not Statuses.is_known(str(e.get("status", ""))):
		errs.append("%s: unknown status '%s'" % [where, e.get("status", "")])
	return errs
