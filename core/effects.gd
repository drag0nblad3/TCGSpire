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
	"summon": ["name", "atk", "hp"],
	"rally": ["amount"],
	"grow": ["atk", "hp"],
	"cleanse": ["to"],
	"add_card": ["card", "amount", "upgraded"],
	"spawn": ["enemy"],
	"lose_hp": ["amount", "to"],
	"damage_per_status": ["status", "mult", "base", "consume", "to"],
}

const TARGETS := ["target", "self", "all_enemies", "all_allies", "front"]


static func resolve(c: Combat, e: Dictionary, src: Fighter, target: Fighter) -> void:
	var op := str(e.get("op", ""))
	var n := int(e.get("amount", 0))
	match op:
		"damage":
			for i in int(e.get("hits", 1)):
				for t in targets(c, e, src, target, "target"):
					c.attack(src, t, n)
		"damage_per_ward":
			var amt := int(src.ward * float(e.get("mult", 1.0)))
			for t in targets(c, e, src, target, "target"):
				c.attack(src, t, amt)
		"ward":
			for t in targets(c, e, src, target, "self"):
				var gain := ward_gain(t, n)
				t.ward += gain
				c.emit("ward", {"target": t.id, "amount": gain, "ward": t.ward})
		"heal":
			for t in targets(c, e, src, target, "self"):
				var before: int = t.hp
				t.hp = mini(t.max_hp, t.hp + n)
				c.emit("heal", {"target": t.id, "amount": t.hp - before, "hp": t.hp})
		"apply":
			var s := str(e.get("status", ""))
			var stacks := int(e.get("stacks", 1))
			for t in targets(c, e, src, target, "target"):
				t.add_status(s, stacks)
				c.emit("status", {"target": t.id, "status": s, "stacks": stacks, "total": t.status(s)})
		"draw":
			c.draw(n)
		"energy":
			c.energy += n
			c.emit("energy", {"amount": n})
		"summon":
			c.summon(str(e.get("name", "Unit")), int(e.get("atk", 0)), int(e.get("hp", 1)))
		"rally":
			for u in c.units:
				u.atk += n
			c.emit("rally", {"amount": n})
		"grow":
			var ga := int(e.get("atk", 0))
			var gh := int(e.get("hp", 0))
			for u in c.units:
				u.atk += ga
				u.max_hp += gh
				u.hp += gh
			c.emit("grow", {"atk": ga, "hp": gh})
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


static func ward_gain(f: Fighter, amount: int) -> int:
	return int(amount * 0.75) if f.status("frail") > 0 else amount


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
	match op:
		"damage":
			var hits := int(e.get("hits", 1))
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
			return "Run %s (%d/%d)." % [e.get("name", "Unit"), int(e.get("atk", 0)), int(e.get("hp", 1))]
		"rally":
			return "Your daemons gain +%d attack." % n
		"grow":
			return "Your daemons gain +%d/+%d." % [int(e.get("atk", 0)), int(e.get("hp", 0))]
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
	if op == "apply" and not Statuses.is_known(str(e.get("status", ""))):
		errs.append("%s: unknown status '%s'" % [where, e.get("status", "")])
	return errs
