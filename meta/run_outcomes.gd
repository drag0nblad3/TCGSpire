class_name RunOutcomes
extends RefCounted
## Run-level effects used by events, talisman pickups and rest sites. Like
## Effects, but they change the RunState (deck, gold, HP) instead of a combat.
##   {"op": "gold", "amount": -30}
##   {"op": "add_card", "rarity": "rare"}  or  {"op": "add_card", "card": "kindle"}
## To add an op: OPS + apply() + describe(), then a test in tests/test_run.gd.

const OPS := {
	"gold": ["amount"],
	"heal": ["amount", "pct"],
	"lose_hp": ["amount"],
	"max_hp": ["amount"],
	"add_card": ["card", "rarity", "faction", "upgraded"],
	"remove_card": ["amount"],
	"upgrade": ["amount"],
	"talisman": ["id", "rarity"],
	"mod": ["id", "rarity", "amount"],
	"perk": ["id"],
}


## Applies one outcome. Returns a short line for the UI log.
static func apply(run: RunState, o: Dictionary) -> String:
	var n := int(o.get("amount", 0))
	var rng := run.rng.fork("outcome:%d:%d" % [run.floor_num, run.outcome_counter])
	run.outcome_counter += 1
	match str(o.get("op", "")):
		"gold":
			run.gold = maxi(run.gold + n, 0)
			return "%+d gold" % n
		"heal":
			var amt := n if not o.has("pct") else int(run.max_hp * float(o["pct"]))
			var before := run.hp
			run.hp = mini(run.max_hp, run.hp + amt)
			return "Healed %d" % (run.hp - before)
		"lose_hp":
			run.hp = maxi(run.hp - n, 1)
			return "Lost %d HP" % n
		"max_hp":
			run.max_hp += n
			run.hp = clampi(run.hp + maxi(n, 0), 1, run.max_hp)
			return "%+d max HP" % n
		"add_card":
			var id := str(o.get("card", ""))
			if id == "":
				var pool := run.db.ids_where(func(c: CardDef) -> bool:
					return c.rarity == str(o.get("rarity", "common")) and (not o.has("faction") or c.faction == o["faction"]) and c.faction not in run.banned)
				pool.sort()
				id = str(rng.pick(pool)) if not pool.is_empty() else ""
			if id == "" or run.db.card(id) == null:
				return ""
			run.deck.append(run.make_card(id, bool(o.get("upgraded", false))))
			return "Added %s" % run.db.card(id).name
		"remove_card":
			var names: Array[String] = []
			for i in maxi(n, 1):
				var removable := run.deck.filter(func(c: CardInstance) -> bool: return c.def.rarity in ["starter", "curse"])
				if removable.is_empty():
					removable = run.deck
				if removable.is_empty():
					break
				var card: CardInstance = rng.pick(removable)
				run.deck.erase(card)
				names.append(card.display_name())
			return "Removed %s" % ", ".join(names)
		"upgrade":
			var names: Array[String] = []
			for i in maxi(n, 1):
				var up := RunState.upgrade_candidates(run.deck)
				if up.is_empty():
					break
				var card: CardInstance = rng.pick(up)
				card.level_up()
				names.append(card.display_name())
			return "Upgraded %s" % ", ".join(names)
		"talisman":
			var tid := str(o.get("id", ""))
			if tid == "":
				tid = run.roll_talisman(str(o.get("rarity", "common")), rng)
			if tid == "":
				return ""
			run.add_talisman(tid)
			return "Got %s" % run.db.talismans[tid]["name"]
		"mod":
			var names: Array[String] = []
			for i in maxi(n, 1):
				var mid := str(o.get("id", ""))
				if mid == "":
					mid = run.roll_mod(str(o.get("rarity", "")), rng)
				var fits := run.mod_targets(mid)
				if fits.is_empty():
					continue
				var idx: int = rng.pick(fits)
				var card: CardInstance = run.deck[idx]
				run.install_mod(idx, mid)
				names.append("%s on %s" % [run.db.mod(mid)["name"], card.display_name()])
			return "Installed %s" % ", ".join(names) if not names.is_empty() else ""
		"perk":
			var pid := str(o.get("id", ""))
			if pid == "":
				var pool := run.perk_choices(1, rng)
				pid = str(pool[0]) if not pool.is_empty() else ""
			var got := run.add_perk(pid)
			return ". ".join(got)
	push_error("Unknown run outcome %s" % o)
	return ""


static func describe(o: Dictionary) -> String:
	var n := int(o.get("amount", 0))
	match str(o.get("op", "")):
		"gold":
			return "%s %d creds." % ["Gain" if n >= 0 else "Lose", absi(n)]
		"heal":
			return "Repair %d%% of max HP." % int(float(o["pct"]) * 100) if o.has("pct") else "Heal %d." % n
		"lose_hp":
			return "Lose %d HP." % n
		"max_hp":
			return "%s %d max HP." % ["Gain" if n >= 0 else "Lose", absi(n)]
		"add_card":
			if o.has("card"):
				return "Add %s to your deck." % Lexicon.card_name(str(o["card"]))
			return "Add a random %s%s card." % [o.get("rarity", "common"), (" " + Lexicon.faction(str(o["faction"]))) if o.has("faction") else ""]
		"remove_card":
			return "Remove %d starter card%s." % [maxi(n, 1), "" if maxi(n, 1) == 1 else "s"]
		"upgrade":
			return "Upgrade %d random card%s." % [maxi(n, 1), "" if maxi(n, 1) == 1 else "s"]
		"talisman":
			return "Gain a %s implant." % o.get("rarity", "random") if not o.has("id") else "Gain %s." % str(CardDB.shared().talismans.get(str(o["id"]), {}).get("name", o["id"]))
		"mod":
			var cnt := maxi(n, 1)
			if o.has("id"):
				return "Install %s on a random program." % str(CardDB.shared().mods.get(str(o["id"]), {}).get("name", o["id"]))
			return "Install %d random %smod%s." % [cnt, (str(o["rarity"]) + " ") if o.has("rarity") else "", "" if cnt == 1 else "s"]
		"perk":
			if o.has("id"):
				return "Load the %s subroutine." % str(CardDB.shared().perks.get(str(o["id"]), {}).get("name", o["id"]))
			return "Load a random subroutine."
	return "?"


static func validate(o: Dictionary, where: String) -> Array[String]:
	var errs: Array[String] = []
	var op := str(o.get("op", ""))
	if not OPS.has(op):
		errs.append("%s: unknown run outcome '%s'" % [where, op])
		return errs
	for k in o:
		if k != "op" and k not in OPS[op]:
			errs.append("%s: outcome '%s' has unknown param '%s'" % [where, op, k])
	return errs
