class_name CombatLog
extends RefCounted
## Plain-language history of a fight, built from Combat.events (no Nodes, so tests can read it).
## Each line is {"turn": int, "side": "you"|"enemy"|"info"|"head", "indent": bool, "text": String}.
## A card play or enemy move starts a line; what it caused (damage, statuses...) is indented under it.

const STATUS_TICK_KINDS := {"burn": true}


static func lines(c: Combat) -> Array:
	var names := _names(c)
	var out: Array = []
	var turn := 0
	var under := false # true while we are inside a play / move, so results indent
	var side := "info"
	for e: Dictionary in c.events:
		var t := str(e.get("t", ""))
		match t:
			"summon":
				names[str(e["target"])] = str(e["name"])
			"spawn":
				names[str(e["target"])] = Lexicon.enemy_name(str(e["enemy"]))
		var text := _text(c, e, names)
		match t:
			"combat_start":
				out.append(_line(0, "head", false, "Breach started"))
				continue
			"turn_start":
				turn = int(e["turn"])
				under = false
				side = "you"
				out.append(_line(turn, "head", false, "Turn %d" % turn))
				continue
			"enemy_phase":
				under = false
				side = "enemy"
				out.append(_line(turn, "head", false, "Enemy turn"))
				continue
			"play", "enemy_move":
				under = true
				out.append(_line(turn, "you" if t == "play" else "enemy", false, text))
				continue
			"combat_end":
				out.append(_line(turn, "head", false, text))
				continue
		if text == "":
			continue
		out.append(_line(turn, side, under, text))
	return out


## The log as plain text, one line each (tests, debugging).
static func as_text(c: Combat) -> String:
	var parts := PackedStringArray()
	for l: Dictionary in lines(c):
		parts.append(("    " if l["indent"] else "") + str(l["text"]))
	return "\n".join(parts)


static func _line(turn: int, side: String, indent: bool, text: String) -> Dictionary:
	return {"turn": turn, "side": side, "indent": indent, "text": text}


## Fighter id -> shown name. Two enemies with one name get A, B... so lines stay clear.
static func _names(c: Combat) -> Dictionary:
	var names := {"player": "You"}
	var count := {}
	for en: Fighter in c.enemies:
		count[en.name] = int(count.get(en.name, 0)) + 1
	var seen := {}
	for en: Fighter in c.enemies:
		var n := en.name
		if int(count[n]) > 1:
			seen[n] = int(seen.get(n, 0)) + 1
			n = "%s %s" % [n, char(64 + int(seen[n]))]
		names[en.id] = n
	for u: Fighter in c.units:
		names[u.id] = u.name
	return names


static func _who(names: Dictionary, id: String) -> String:
	return str(names.get(id, id if id != "" else "?"))


static func _card(key: String) -> String:
	var base := key.split("#")[0]
	var up := base.ends_with("+")
	return Lexicon.card_name(base.trim_suffix("+")) + ("+" if up else "")


static func _text(c: Combat, e: Dictionary, names: Dictionary) -> String:
	var tgt := _who(names, str(e.get("target", "")))
	match str(e.get("t", "")):
		"play":
			var s := "You ran %s" % _card(str(e["card"]))
			if e.has("x"):
				s += " (X = %d)" % int(e["x"])
			var on := str(e.get("target", ""))
			if on != "" and on != "player":
				s += " on %s" % tgt
			return s
		"enemy_move":
			if e.get("stalled", false):
				return "%s is Lagged and skips its move" % _who(names, str(e["source"]))
			return "%s used %s" % [_who(names, str(e["source"])), str(e["move"])]
		"damage":
			var amount := int(e["amount"])
			var blocked := int(e.get("blocked", 0))
			var s := ""
			match str(e.get("kind", "attack")):
				"burn":
					s = "%s took %d from %s" % [tgt, amount, Lexicon.status("burn")]
				"thorns":
					s = "%s took %d from %s" % [tgt, amount, Lexicon.status("thorns")]
				"lose_hp":
					s = "%s lost %d HP" % [tgt, amount]
				"daemon_explosion":
					s = "%s took %d from a daemon blast" % [tgt, amount]
				_:
					s = "%s took %d" % [tgt, amount]
			if blocked > 0 and amount == 0:
				return "%s %s blocked %d" % ["Your" if tgt == "You" else tgt + "'s", Lexicon.term("ward"), blocked]
			if blocked > 0:
				s += " (%d blocked by %s)" % [blocked, Lexicon.term("ward")]
			return s + ", %d HP left" % int(e.get("hp", 0))
		"immune":
			return "%s is immune" % tgt
		"ward":
			return "%s gained %d %s" % [tgt, int(e["amount"]), Lexicon.term("ward")]
		"heal":
			if int(e["amount"]) <= 0:
				return ""
			return "%s repaired %d HP" % [tgt, int(e["amount"])]
		"status":
			var k := int(e["stacks"])
			if k == 0:
				return ""
			var st := Lexicon.status(str(e["status"]))
			if k > 0:
				return "%s gained %d %s (%d)" % [tgt, k, st, int(e.get("total", k))]
			return "%s lost %d %s (%d)" % [tgt, -k, st, int(e.get("total", 0))]
		"cleanse":
			return "%s was cleansed" % tgt
		"strip":
			var gone: Array = e.get("statuses", [])
			return "%s was stripped of %s" % [tgt, ", ".join(gone.map(func(s: Variant) -> String: return Lexicon.status(str(s))))]
		"energy":
			return "+%d %s" % [int(e["amount"]), Lexicon.term("energy")] if int(e["amount"]) >= 0 else "%d %s" % [int(e["amount"]), Lexicon.term("energy")]
		"draw":
			return "Added %s to your hand" % _card(str(e["card"])) if e.get("created", false) else ""
		"reshuffle":
			return "Discard pile shuffled into draw pile"
		"death":
			return "%s crashed" % tgt
		"summon":
			return "Daemon %s is up (%d HP)" % [str(e["name"]), int(e["hp"])]
		"refresh":
			return "%s refreshed (%d HP)" % [tgt, int(e["hp"])]
		"expire":
			return "%s %s" % [tgt, "crashed" if e.get("crashed", false) else "closed"]
		"spawn":
			return "%s joined the fight" % tgt
		"interrupt":
			var cut: Array = e.get("kinds", [])
			return "Interrupted %s's %s" % [tgt, ", ".join(cut.map(func(s: Variant) -> String: return Lexicon.intent(str(s))))]
		"dump":
			return "Dumped %s" % _card(str(e["card"]))
		"recover":
			return "%s went back %s" % [_card(str(e["card"])), "on top of your draw pile" if str(e.get("into", "")) == "top" else "into your draw pile"]
		"evolve":
			return "%s evolved into %s" % [_card(str(e["card"])), _card(str(e["into"]))]
		"infect":
			return "%d %s put on top of your draw pile" % [int(e["amount"]), Lexicon.card_name(str(e["card"]))]
		"hatch":
			return "%s hatched" % _card(str(e["card"]))
		"loop":
			return "%s looped (+%d)" % [_card(str(e["card"])), int(e.get("grown", 0))]
		"rally":
			return "Daemons gained %d HP" % int(e["amount"])
		"second_wind":
			return "Second Wind kicked in"
		"talisman":
			var d: Dictionary = c.db.talismans.get(e["id"], c.db.perks.get(e["id"], {}))
			return "Implant %s triggered" % str(d.get("name", e["id"]))
		"rule":
			if str(e.get("trigger", "")) == "closed":
				return "%s payoff fired" % _who(names, str(e["id"]))
			return ""
		"phase":
			var n := str(e.get("name", ""))
			return "%s entered a new phase%s" % [tgt, (": " + n) if n != "" else ""]
		"shield_down":
			return "%s lost its shield" % tgt
		"shield_up":
			return "%s is shielding again" % tgt
		"gauge_full":
			return "%s gauge full: %s" % [tgt, str(e.get("name", ""))]
		"twin_down":
			return "%s went down; %s will restore it" % [tgt, _who(names, str(e.get("by", "")))]
		"bond":
			return "%s bonded with its fallen partner" % tgt
		"timer":
			return "%s finished its Trace" % tgt if int(e["left"]) == 0 else ""
		"tide":
			return "%s is at %s tide" % [tgt, "low" if str(e["state"]) == "low" else "high"]
		"devour":
			return "%s devoured %d" % [_who(names, str(e["source"])), int(e["count"])]
		"daemon_explosion":
			return "%s detonated" % tgt
		"combat_end":
			return "Victory" if e.get("won", false) else "Defeated"
	return ""
