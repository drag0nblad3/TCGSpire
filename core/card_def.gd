class_name CardDef
extends RefCounted
## Static card definition loaded from data/cards/*.json. Never mutated at runtime.
## Rules text is generated from effects (Effects.describe) unless "text" is given.

const TYPES := ["attack", "skill", "unit", "power"]
const TARGETS := ["enemy", "none"]
const RARITIES := ["starter", "common", "uncommon", "rare", "mythic"]
const KEYWORDS := ["exhaust", "retain", "unplayable"]

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
		parts.append(str(k).capitalize() + ".")
	return " ".join(parts)


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
	if upgrade.is_empty():
		errs.append("%s: missing upgrade" % where)
	return errs
