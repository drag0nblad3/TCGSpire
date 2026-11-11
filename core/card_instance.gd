class_name CardInstance
extends RefCounted
## One physical card in a deck/pile. Many instances can share a CardDef.

var def: CardDef
var upgraded := false
## Cosmetic only (foil frame etc.). Never affects rules.
var foil := false


func _init(d: CardDef, up: bool = false) -> void:
	def = d
	upgraded = up


func cost() -> int:
	return def.get_cost(upgraded)


func effects() -> Array:
	return def.get_effects(upgraded)


func has_keyword(k: String) -> bool:
	return k in def.get_keywords(upgraded)


func display_name() -> String:
	return def.name + ("+" if upgraded else "")


func text() -> String:
	return def.get_text(upgraded)


func key() -> String:
	return def.id + ("+" if upgraded else "")
