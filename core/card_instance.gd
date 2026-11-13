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
## Loop: times this copy has run in the current fight (Combat resets it). Each run
## grows every effect marked "loop": n by n (Effects.LOOP_KEY names the number).
var loops := 0

## Numbers firmware scales, per op. Draw/RAM/copies stay as they are.
const FW_KEYS := {
	"damage": ["amount"], "ward": ["amount"], "heal": ["amount"], "apply": ["stacks"],
	"rally": ["amount"],
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
	return CardMods.effects(mod, looped(scaled(def.get_effects(upgraded), fw_mult()), loops))


## True if any of this card's effects grow with Loop.
func has_loop() -> bool:
	for e in def.get_effects(upgraded):
		if e.has("loop"):
			return true
	return false


## Effects with each Loop number grown by its "loop" step x times.
static func looped(effs: Array, times: int) -> Array:
	if times <= 0:
		return effs
	var out: Array = []
	for e in effs:
		if e.has("loop") and Effects.LOOP_KEY.has(str(e.get("op", ""))):
			var d: Dictionary = e.duplicate()
			var k: String = Effects.LOOP_KEY[str(d["op"])]
			var base: Variant = d.get(k, 1 if k in ["hp", "stacks", "mult"] else 0)
			if base is float:
				d[k] = float(base) + float(d["loop"]) * times
			else:
				d[k] = int(base) + int(d["loop"]) * times
			out.append(d)
		else:
			out.append(e)
	return out


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
	return def.name + (" v%d" % fw if fw > 0 else "") + ("+" if upgraded else "")


## Upgrade ladder: firmware v1, v2, then the card's designed (+) upgrade.
## deck_maxed: every upgradable card in the deck is at v2 (the (+) step waits for it).
func can_level_up(deck_maxed: bool) -> bool:
	if def.rarity == "curse" or upgraded:
		return false
	if fw < fw_scale.size() - 1:
		return true
	return deck_maxed and not def.upgrade.is_empty()


func level_up() -> void:
	if fw < fw_scale.size() - 1:
		fw += 1
	else:
		upgraded = true


## What the next level_up() changes, in words.
func level_up_text() -> String:
	if fw < fw_scale.size() - 1:
		return "To v%d: numbers +%d%% over the base card." % [fw + 1, roundi((float(fw_scale[fw + 1]) - 1.0) * 100)]
	return "Recompile (+): " + def.upgrade_summary()


func text() -> String:
	if loops > 0 and def.get_text(upgraded) != "" and has_loop():
		return _generated_text()
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
	c.loops = loops
	return c
