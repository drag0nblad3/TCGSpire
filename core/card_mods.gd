class_name CardMods
extends RefCounted
## Card mods: one per card instance, installed during a run (safehouse tinkering,
## the Fixer, signals). Defined in data/mods.json:
##   {"id", "name", "rarity", optional restrictions and changes}
## Restrictions: "types": [card types], "target": "enemy", "min_cost": N,
##   "needs_keyword": [any of these keywords].
## Changes: "cost": delta, "keywords_add"/"keywords_remove": [...],
##   "effects_add": [Effects ops], "bump": {"op": "damage", "amount": 2} (adds the
##   numbers to every effect with that op).

const RARITIES := ["common", "uncommon", "rare"]
const CHANGES := ["cost", "keywords_add", "keywords_remove", "effects_add", "bump"]
const RESTRICTIONS := ["types", "target", "min_cost", "needs_keyword"]


static func can_apply(m: Dictionary, card: CardInstance) -> bool:
	if m.is_empty() or card == null or card.def.rarity == "curse" or not card.mod.is_empty():
		return false
	var d := card.def
	if m.has("types") and d.type not in m["types"]:
		return false
	if m.has("target") and d.target != str(m["target"]):
		return false
	if card.base_cost() < int(m.get("min_cost", 0)):
		return false
	if m.has("needs_keyword"):
		var kws := d.get_keywords(card.upgraded)
		if not m["needs_keyword"].any(func(k: String) -> bool: return k in kws):
			return false
	if m.has("bump"):
		var op := str(m["bump"].get("op", ""))
		if not d.get_effects(card.upgraded).any(func(e: Dictionary) -> bool: return _matches_bump(e, op)):
			return false
	for k in m.get("keywords_add", []):
		if k in d.get_keywords(card.upgraded):
			return false
	return true


static func cost(m: Dictionary, base: int) -> int:
	return maxi(base + int(m.get("cost", 0)), 0)


## A charged attack still has a base damage amount; installed damage mods
## affect that base, not the charge step or cap.
static func _matches_bump(e: Dictionary, op: String) -> bool:
	return e.get("op", "") == op or (e.get("op", "") == "cooldown" and str(e.get("effect", "damage")) == op)


static func effects(m: Dictionary, base: Array) -> Array:
	if m.is_empty():
		return base
	var out: Array = []
	var bump: Dictionary = m.get("bump", {})
	for e in base:
		if not bump.is_empty() and _matches_bump(e, str(bump.get("op", ""))):
			var b: Dictionary = e.duplicate()
			for k in bump:
				if k != "op":
					b[k] = int(b.get(k, 0)) + int(bump[k])
			out.append(b)
		else:
			out.append(e)
	out.append_array(m.get("effects_add", []))
	return out


static func keywords(m: Dictionary, base: Array) -> Array:
	if m.is_empty():
		return base
	var out: Array = base.filter(func(k: String) -> bool: return k not in m.get("keywords_remove", []))
	for k in m.get("keywords_add", []):
		if k not in out:
			out.append(k)
	return out


## Generated rules line for the mod, e.g. "Costs 1 less RAM. Also draw 1."
static func describe(m: Dictionary) -> String:
	var parts: Array[String] = []
	var dc := int(m.get("cost", 0))
	if dc != 0:
		parts.append("Costs %d %s RAM." % [absi(dc), "less" if dc < 0 else "more"])
	for k in m.get("keywords_add", []):
		parts.append("Gains %s." % Lexicon.keyword(str(k)))
	if not m.get("keywords_remove", []).is_empty():
		parts.append("Loses %s." % " and ".join(m["keywords_remove"].map(func(k: String) -> String: return Lexicon.keyword(k))))
	var bump: Dictionary = m.get("bump", {})
	if not bump.is_empty():
		var bits: Array[String] = []
		for k in bump:
			if k != "op":
				var what: String = {"hp": "HP"}.get(k, Lexicon.term(str(bump["op"])).replace("_", " "))
				bits.append("+%d %s" % [int(bump[k]), what])
		parts.append("%s%s." % ["Its daemon gets " if str(bump["op"]) == "summon" else "", ", ".join(bits)])
	for e in m.get("effects_add", []):
		parts.append("Also: " + Effects.describe(e))
	return " ".join(parts)


## Who can take it, e.g. "Exploits only".
static func restriction_text(m: Dictionary) -> String:
	var parts: Array[String] = []
	if m.has("types"):
		parts.append("/".join(m["types"].map(func(t: String) -> String: return Lexicon.type_name(t) + "s")))
	if m.has("target"):
		parts.append("targeted programs")
	if m.has("min_cost"):
		parts.append("cost %d+" % int(m["min_cost"]))
	if m.has("needs_keyword"):
		parts.append("with " + " or ".join(m["needs_keyword"].map(func(k: String) -> String: return Lexicon.keyword(k))))
	return "" if parts.is_empty() else "Fits " + ", ".join(parts) + "."


static func validate(m: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var where := "mod '%s'" % m.get("id", "")
	if str(m.get("rarity", "")) not in RARITIES:
		errs.append("%s: bad rarity '%s'" % [where, m.get("rarity", "")])
	for k in m:
		if k not in ["id", "name", "rarity"] and k not in CHANGES and k not in RESTRICTIONS:
			errs.append("%s: unknown field '%s'" % [where, k])
	for t in m.get("types", []):
		if t not in CardDef.TYPES:
			errs.append("%s: bad type '%s'" % [where, t])
	for k in m.get("keywords_add", []) + m.get("keywords_remove", []) + m.get("needs_keyword", []):
		if k not in CardDef.KEYWORDS:
			errs.append("%s: unknown keyword '%s'" % [where, k])
	for e in m.get("effects_add", []):
		errs.append_array(Effects.validate(e, where))
	if m.has("bump") and not Effects.OPS.has(str(m["bump"].get("op", ""))):
		errs.append("%s: bump of unknown op '%s'" % [where, m["bump"].get("op", "")])
	return errs
