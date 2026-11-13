class_name CardDef
extends RefCounted
## Static card definition loaded from data/cards/*.json. Never mutated at runtime.
## Rules text is generated from effects (Effects.describe) unless "text" is given.

const TYPES := ["attack", "skill", "unit", "power"]
## "ally": you or one of your daemons (hand-picked when a daemon is running).
const TARGETS := ["enemy", "ally", "none"]
const RARITIES := ["starter", "common", "uncommon", "rare", "mythic", "curse"]
const KEYWORDS := ["exhaust", "retain", "unplayable", "innate", "ethereal"]
## Rules glossary for keywords (shown by the card inspector and the rules screen).
const KEYWORD_DESC := {
	"exhaust": "After it runs, the program is wiped for the rest of this fight.",
	"retain": "Stays cached in your hand at the end of your turn instead of being discarded.",
	"unplayable": "Locked: can't be run. It just clogs your hand.",
	"innate": "Always loaded into your opening hand.",
	"ethereal": "If it's still in your hand at the end of your turn, it is wiped.",
}
const TYPE_DESC := {
	"attack": "Exploit: usually deals damage to an enemy.",
	"skill": "Script: Firewall, draws, statuses and other tricks.",
	"unit": "Daemon: runs a program that stays on your board. Daemons hit the front enemy at the end of your turn and can be attacked.",
	"power": "Rootkit: a lasting effect for the rest of the fight. Rootkits are wiped after they run.",
}

var id := ""
var name := ""
var faction := "neutral"
var rarity := "common"
var type := "skill"
var target := "none"
var cost := 1
var effects: Array = []
var keywords: Array = []
var text_override := ""
## Fields replaced when the card is upgraded: any of cost, effects, keywords, text.
var upgrade: Dictionary = {}


static func from_dict(d: Dictionary) -> CardDef:
	var c := CardDef.new()
	c.id = str(d.get("id", ""))
	c.name = str(d.get("name", c.id))
	c.faction = str(d.get("faction", "neutral"))
	c.rarity = str(d.get("rarity", "common"))
	c.type = str(d.get("type", "skill"))
	c.target = str(d.get("target", "none"))
	c.cost = int(d.get("cost", 1))
	c.effects = d.get("effects", [])
	c.keywords = d.get("keywords", [])
	c.text_override = str(d.get("text", ""))
	c.upgrade = d.get("upgrade", {})
	return c


func get_cost(upgraded: bool) -> int:
	return int(upgrade.get("cost", cost)) if upgraded else cost


func get_effects(upgraded: bool) -> Array:
	return upgrade.get("effects", effects) if upgraded else effects


func get_keywords(upgraded: bool) -> Array:
	return upgrade.get("keywords", keywords) if upgraded else keywords


func get_text(upgraded: bool) -> String:
	var override := str(upgrade.get("text", text_override)) if upgraded else text_override
	if override != "":
		return override
	var parts: Array[String] = []
	for e in get_effects(upgraded):
		parts.append(Effects.describe(e))
	for k in get_keywords(upgraded):
		parts.append(Lexicon.keyword(str(k)) + ".")
	return " ".join(parts)


## What recompiling (upgrading) changes, e.g. "Damage 6 → 9. Costs 0 RAM."
## Generated from the base and upgraded data so every card explains itself.
func upgrade_summary() -> String:
	if upgrade.is_empty():
		return "Can't be upgraded."
	var parts: Array[String] = []
	if get_cost(true) != cost:
		parts.append("Costs %d RAM (was %d)." % [get_cost(true), cost])
	var a: Array = get_effects(false).duplicate()
	for eb in get_effects(true):
		var match_i := -1
		for i in a.size():
			if a[i].get("op", "") == eb.get("op", "") and a[i].get("status", "") == eb.get("status", "") and a[i].get("to", "") == eb.get("to", ""):
				match_i = i
				break
		if match_i < 0:
			parts.append("Adds: " + Effects.describe(eb))
			continue
		var ea: Dictionary = a[match_i]
		a.remove_at(match_i)
		for k in eb:
			if k in ["op", "status", "to", "name", "card", "enemy", "consume"]:
				continue
			if k == "rule":
				if eb[k] != ea.get(k, {}):
					parts.append("%s rule: %s" % [eb.get("name", "Daemon"), DaemonRules.describe(eb[k])])
				continue
			if k == "upgraded":
				if bool(eb[k]) and not bool(ea.get(k, false)):
					parts.append("The added program is upgraded.")
				continue
			var dflt := 1 if k == "hits" or (k == "amount" and eb.get("op", "") == "add_card") else 0
			var before := int(ea.get(k, dflt))
			var after := int(eb[k])
			if before != after:
				parts.append("%s %d → %d." % [_param_name(eb, k), before, after])
	for ea in a:
		parts.append("Drops: " + Effects.describe(ea))
	for k in get_keywords(true):
		if k not in keywords:
			parts.append("Gains %s." % Lexicon.keyword(str(k)))
	for k in keywords:
		if k not in get_keywords(true):
			parts.append("Loses %s." % Lexicon.keyword(str(k)))
	return " ".join(parts) if not parts.is_empty() else "No change."


static func _param_name(e: Dictionary, k: String) -> String:
	var op := str(e.get("op", ""))
	if k == "hits":
		return "Hits"
	if op == "summon":
		return "%s HP" % e.get("name", "Daemon")
	if op == "apply" and k == "stacks":
		return Lexicon.status(str(e.get("status", "")))
	if op in ["damage_per_status", "damage_per_ward"]:
		return {"mult": "Damage per stack", "base": "Base damage"}.get(k, k.capitalize())
	match op:
		"damage": return "Damage"
		"ward": return Lexicon.term("ward")
		"heal": return "Repair"
		"draw": return "Draw"
		"energy": return Lexicon.term("energy")
		"rally": return "Daemon HP"
		"lose_hp": return "HP loss"
		"add_card": return "Copies"
	return k.capitalize()


## Returns a list of human-readable problems; empty means valid.
func validate() -> Array[String]:
	var errs: Array[String] = []
	var where := "card '%s'" % id
	if id == "":
		errs.append("card with empty id")
	if type not in TYPES:
		errs.append("%s: bad type '%s'" % [where, type])
	if target not in TARGETS:
		errs.append("%s: bad target '%s'" % [where, target])
	if rarity not in RARITIES:
		errs.append("%s: bad rarity '%s'" % [where, rarity])
	for up in [false, true]:
		for k in get_keywords(up):
			if k not in KEYWORDS:
				errs.append("%s: unknown keyword '%s'" % [where, k])
		for e in get_effects(up):
			errs.append_array(Effects.validate(e, where))
	if upgrade.is_empty() and rarity != "curse":
		errs.append("%s: missing upgrade" % where)
	return errs
