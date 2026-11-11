class_name CardInstance
extends RefCounted
## One physical card in a deck/pile. Many instances can share a CardDef.
## A run can upgrade it (+) and install one mod (CardMods) on it.

var def: CardDef
var upgraded := false
## Cosmetic only (foil frame etc.). Never affects rules.
var foil := false
## Installed mod (a dict from data/mods.json), or {} for none.
var mod: Dictionary = {}


func _init(d: CardDef, up: bool = false) -> void:
	def = d
	upgraded = up


func base_cost() -> int:
	return def.get_cost(upgraded)


func cost() -> int:
	return CardMods.cost(mod, base_cost()) if not mod.is_empty() else base_cost()


func effects() -> Array:
	return CardMods.effects(mod, def.get_effects(upgraded))


func keywords() -> Array:
	return CardMods.keywords(mod, def.get_keywords(upgraded))


func has_keyword(k: String) -> bool:
	return k in keywords()


func mod_id() -> String:
	return str(mod.get("id", ""))


func mod_name() -> String:
	return str(mod.get("name", ""))


func display_name() -> String:
	return def.name + ("+" if upgraded else "")


func text() -> String:
	if mod.is_empty():
		return def.get_text(upgraded)
	if def.get_text(upgraded) != "" and (upgraded and def.upgrade.has("text") or not upgraded and def.text_override != ""):
		return def.get_text(upgraded) + " " + CardMods.describe(mod)
	var parts: Array[String] = []
	for e in effects():
		parts.append(Effects.describe(e))
	for k in keywords():
		parts.append(Lexicon.keyword(str(k)) + ".")
	return " ".join(parts)


func key() -> String:
	return def.id + ("+" if upgraded else "")


## Copy with the same upgrade and mod (for previews).
func copy() -> CardInstance:
	var c := CardInstance.new(def, upgraded)
	c.foil = foil
	c.mod = mod
	return c
