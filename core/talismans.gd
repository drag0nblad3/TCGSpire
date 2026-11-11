class_name Talismans
extends RefCounted
## Passive run items. Defined in data/talismans.json:
##   {"id", "name", "rarity", "triggers": [{"on": TRIGGER, "effects": [...], filters...}],
##    "pickup": [run outcomes, e.g. {"op": "max_hp", "amount": 8}]}
## Trigger effects use the normal Effects vocabulary with the player as source.
## Filters: "every": N (fires on every Nth event), "turn": N (only that turn),
## "card_type": "attack" (card_played only).

const TRIGGERS := ["combat_start", "turn_start", "turn_end", "card_played", "kill"]
const RARITIES := ["common", "uncommon", "rare", "boss"]
const LABEL := {
	"combat_start": "When you jack in",
	"turn_start": "Start of each turn",
	"turn_end": "End of turn",
	"card_played": "When you play a card",
	"kill": "When you crash an enemy",
}


## Fires implants, then subroutines (perks share the trigger format).
static func fire(c: Combat, on: String, ctx: Dictionary = {}) -> void:
	for t in c.talismans + c.perks:
		var tid: String = t.get("id", "")
		for i in t.get("triggers", []).size():
			var trig: Dictionary = t["triggers"][i]
			if trig.get("on", "") != on or c.is_over():
				continue
			if trig.has("turn") and int(trig["turn"]) != c.turn:
				continue
			if trig.has("card_type"):
				var card: CardInstance = ctx.get("card")
				if card == null or card.def.type != trig["card_type"]:
					continue
			if trig.has("every"):
				var key := "%s:%d" % [tid, i]
				c.talisman_counters[key] = int(c.talisman_counters.get(key, 0)) + 1
				if c.talisman_counters[key] % int(trig["every"]) != 0:
					continue
			c.emit("talisman", {"id": tid})
			for e in trig.get("effects", []):
				Effects.resolve(c, e, c.player, ctx.get("target"))


static func describe(t: Dictionary) -> String:
	var parts: Array[String] = []
	for o in t.get("pickup", []):
		parts.append(RunOutcomes.describe(o))
	for trig in t.get("triggers", []):
		var on: String = trig.get("on", "")
		var when: String = LABEL.get(on, "?")
		if trig.has("card_type"):
			var tn := Lexicon.type_name(str(trig["card_type"]))
			when = "When you play %s %s" % ["an" if tn[0].to_lower() in "aeiou" else "a", tn]
		if trig.has("every"):
			var noun: String = {"card_played": "cards you play", "turn_start": "turns", "turn_end": "turns", "kill": "crashed enemies"}.get(on, "times")
			if trig.has("card_type"):
				noun = "%ss you play" % Lexicon.type_name(str(trig["card_type"]))
			when = "Every %d %s" % [int(trig["every"]), noun]
		if trig.has("turn"):
			when = "On turn %d" % int(trig["turn"])
		var fx: Array[String] = []
		for e in trig.get("effects", []):
			fx.append(Effects.describe(e))
		parts.append("%s: %s" % [when, " ".join(fx)])
	return " ".join(parts)


static func validate(t: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var where := "talisman '%s'" % t.get("id", "")
	if str(t.get("rarity", "")) not in RARITIES:
		errs.append("%s: bad rarity '%s'" % [where, t.get("rarity", "")])
	for trig in t.get("triggers", []):
		if trig.get("on", "") not in TRIGGERS:
			errs.append("%s: bad trigger '%s'" % [where, trig.get("on", "")])
		for e in trig.get("effects", []):
			errs.append_array(Effects.validate(e, where))
	for o in t.get("pickup", []):
		errs.append_array(RunOutcomes.validate(o, where))
	return errs
