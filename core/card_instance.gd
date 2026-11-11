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
## Firmware level (0-2): scales the card's numbers (balance.firmware.scale).
var fw := 0
## Set by whoever builds firmware cards (CardDB.firmware_scale), index = level.
var fw_scale: Array = [1.0]

## Numbers firmware scales, per op. Draw/RAM/copies stay as they are.
const FW_KEYS := {
	"damage": ["amount"], "ward": ["amount"], "heal": ["amount"], "apply": ["stacks"],
	"summon": ["atk", "hp"], "grow": ["atk", "hp"], "rally": ["amount"],
	"damage_per_ward": ["mult"], "damage_per_status": ["base", "mult"],
}


func _init(d: CardDef, up: bool = false) -> void:
	def = d
	upgraded = up


func base_cost() -> int:
	return def.get_cost(upgraded)


func cost() -> int:
	return CardMods.cost(mod, base_cost()) if not mod.is_empty() else base_cost()


func effects() -> Array:
	return CardMods.effects(mod, scaled(def.get_effects(upgraded), fw_mult()))


func fw_mult() -> float:
	return float(fw_scale[mini(fw, fw_scale.size() - 1)]) if fw > 0 else 1.0


## Effects with their numbers scaled by m (rounded half up; never below the original).
static func scaled(effs: Array, m: float) -> Array:
	if is_equal_approx(m, 1.0):
		return effs
	var out: Array = []
	for e in effs:
		var d: Dictionary = e.duplicate()
		for k in FW_KEYS.get(str(d.get("op", "")), []):
			if d.has(k) and (d[k] is int or d[k] is float) and float(d[k]) > 0.0:
				var v: float = float(d[k]) * m
				d[k] = v if k == "mult" else maxi(int(floor(v + 0.5)), int(d[k]))
		out.append(d)
	return out


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
	if mod.is_empty() and fw == 0:
		return def.get_text(upgraded)
	if fw > 0:
		return _generated_text()
	if mod.is_empty():
		return def.get_text(upgraded)
	if def.get_text(upgraded) != "" and (upgraded and def.upgrade.has("text") or not upgraded and def.text_override != ""):
		return def.get_text(upgraded) + " " + CardMods.describe(mod)
	return _generated_text()


func _generated_text() -> String:
	var parts: Array[String] = []
	for e in effects():
		parts.append(Effects.describe(e))
	for k in keywords():
		parts.append(Lexicon.keyword(str(k)) + ".")
	return " ".join(parts)


func key() -> String:
	return def.id + ("+" if upgraded else "") + ("#%d" % fw if fw > 0 else "")


## Copy with the same upgrade and mod (for previews).
func copy() -> CardInstance:
	var c := CardInstance.new(def, upgraded)
	c.foil = foil
	c.mod = mod
	c.fw = fw
	c.fw_scale = fw_scale
	return c
