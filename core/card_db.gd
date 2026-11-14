class_name CardDB
extends RefCounted
## Loads all game content from res://data. Content is JSON so it diffs cleanly
## and can be edited (or generated) without opening the editor.
##   data/cards/*.json    -> Array of card dicts (one card per line by convention)
##   data/enemies/*.json  -> Array of enemy dicts
##   data/encounters.json -> {id: {"enemies": [...], "tier": n}}
##   data/balance.json    -> tuning numbers (player stats, packs, dust, starter)

const DATA_ROOT := "res://data"

var cards: Dictionary = {}
var enemies: Dictionary = {}
var encounters: Dictionary = {}
var balance: Dictionary = {}
var talismans: Dictionary = {}
var events: Dictionary = {}
## Card mods (data/mods.json) and perks (data/perks.json), by id.
var mods: Dictionary = {}
var perks: Dictionary = {}
## Job factions (data/factions.json): client name, rivals, rep currency.
var factions: Dictionary = {}
## Contract bonus clauses (data/contracts.json) and Exploit log entries (data/exploits.json), by id.
var contracts: Dictionary = {}
var exploits: Dictionary = {}
## ICE database lore lines (data/ice_lore.json), by enemy id.
var ice_lore: Dictionary = {}
## Weekly challenge modifiers (data/weekly.json), by id.
var weekly: Dictionary = {}
var errors: Array[String] = []

static var _shared: CardDB


static func shared() -> CardDB:
	if _shared == null:
		_shared = load_from(DATA_ROOT)
		for e in _shared.errors:
			push_error("[data] " + e)
	return _shared


static func load_from(root: String) -> CardDB:
	var db := CardDB.new()
	for path in _json_files(root + "/cards"):
		for d in db._read_array(path):
			var c := CardDef.from_dict(d)
			if db.cards.has(c.id):
				db.errors.append("%s: duplicate card id '%s'" % [path, c.id])
			db.cards[c.id] = c
	for path in _json_files(root + "/enemies"):
		for d in db._read_array(path):
			var id := str(d.get("id", ""))
			if db.enemies.has(id):
				db.errors.append("%s: duplicate enemy id '%s'" % [path, id])
			db.enemies[id] = d
	for d in db._read_array(root + "/talismans.json"):
		db.talismans[str(d.get("id", ""))] = d
	for d in db._read_array(root + "/events.json"):
		db.events[str(d.get("id", ""))] = d
	for d in db._read_array(root + "/mods.json"):
		db.mods[str(d.get("id", ""))] = d
	for d in db._read_array(root + "/perks.json"):
		db.perks[str(d.get("id", ""))] = d
	for d in db._read_array(root + "/factions.json"):
		db.factions[str(d.get("id", ""))] = d
	for d in db._read_array(root + "/contracts.json"):
		db.contracts[str(d.get("id", ""))] = d
	for d in db._read_array(root + "/exploits.json"):
		db.exploits[str(d.get("id", ""))] = d
	for d in db._read_array(root + "/weekly.json"):
		db.weekly[str(d.get("id", ""))] = d
	db.encounters = db._read_dict(root + "/encounters.json")
	db.ice_lore = db._read_dict(root + "/ice_lore.json")
	db.balance = db._read_dict(root + "/balance.json")
	db.errors.append_array(db.validate())
	return db


func card(id: String) -> CardDef:
	return cards.get(id)


func instance(id: String, upgraded: bool = false, fw: int = 0) -> CardInstance:
	var d: CardDef = cards.get(id)
	if d == null:
		push_error("Unknown card '%s'" % id)
		return null
	var c := CardInstance.new(d, upgraded)
	if fw > 0:
		c.fw = fw
		c.fw_scale = firmware_scale()
	return c


## [1.0, level 1 mult, level 2 mult] from balance.firmware.scale.
func firmware_scale() -> Array:
	return [1.0] + balance.get("firmware", {}).get("scale", [1.25, 1.5])


func mod(id: String) -> Dictionary:
	return mods.get(id, {})


## Accepts "jab" or "jab+" (upgraded).
func make_deck(ids: Array) -> Array:
	var out: Array = []
	for raw in ids:
		var s := str(raw)
		var up := s.ends_with("+")
		var inst := instance(s.trim_suffix("+"), up)
		if inst != null:
			out.append(inst)
	return out


func ids_where(pred: Callable) -> Array:
	var out: Array = []
	for id in cards:
		if pred.call(cards[id]):
			out.append(id)
	return out


func validate() -> Array[String]:
	var errs: Array[String] = []
	for id in cards:
		errs.append_array(cards[id].validate())
	for id in enemies:
		var d: Dictionary = enemies[id]
		if d.get("moves", []).is_empty():
			errs.append("enemy '%s': no moves" % id)
		for mv in d.get("moves", []):
			for e in mv.get("effects", []):
				errs.append_array(Effects.validate(e, "enemy '%s' move '%s'" % [id, mv.get("name", "?")]))
	for id in encounters:
		for eid in encounters[id].get("enemies", []):
			if not enemies.has(eid):
				errs.append("encounter '%s': unknown enemy '%s'" % [id, eid])
	for id in talismans:
		errs.append_array(Talismans.validate(talismans[id]))
	for id in mods:
		errs.append_array(CardMods.validate(mods[id]))
		if not cards.values().any(func(c: CardDef) -> bool: return CardMods.can_apply(mods[id], CardInstance.new(c))):
			errs.append("mod '%s': fits no card" % id)
	for id in perks:
		errs.append_array(Perks.validate(perks[id]))
	for id in weekly:
		errs.append_array(Weekly.validate(weekly[id]))
	errs.append_array(Jobs.validate(self))
	for id in events:
		for ch in events[id].get("choices", []):
			for o in ch.get("outcomes", []):
				errs.append_array(RunOutcomes.validate(o, "event '%s'" % id))
				if o.has("card") and not cards.has(o["card"]):
					errs.append("event '%s': unknown card '%s'" % [id, o["card"]])
				if o.get("op", "") == "mod" and o.has("id") and not mods.has(str(o["id"])):
					errs.append("event '%s': unknown mod '%s'" % [id, o["id"]])
				if o.get("op", "") == "perk" and o.has("id") and not perks.has(str(o["id"])):
					errs.append("event '%s': unknown perk '%s'" % [id, o["id"]])
	for id in cards:
		for up in [false, true]:
			for e in cards[id].get_effects(up):
				if e.get("op", "") in ["add_card", "handshake"] and not cards.has(str(e.get("card", ""))):
					errs.append("card '%s': add_card of unknown card '%s'" % [id, e.get("card", "")])
	for id in enemies:
		for mv in enemies[id].get("moves", []):
			for e in mv.get("effects", []):
				if e.get("op", "") == "spawn" and not enemies.has(str(e.get("enemy", ""))):
					errs.append("enemy '%s': spawns unknown enemy '%s'" % [id, e.get("enemy", "")])
	var kinds := {}
	for id in encounters:
		kinds["%d:%s" % [int(encounters[id].get("act", 1)), encounters[id].get("kind", "normal")]] = true
	for act in range(1, int(balance.get("acts", 1)) + 1):
		for k in ["normal", "elite", "boss"]:
			if not kinds.has("%d:%s" % [act, k]):
				errs.append("encounters: act %d has no '%s' encounter" % [act, k])
	for key in ["base_deck"]:
		for cid in balance.get(key, []):
			if not cards.has(str(cid).trim_suffix("+")):
				errs.append("balance.%s: unknown card '%s'" % [key, cid])
	for cid in balance.get("starter_collection", {}):
		if not cards.has(cid):
			errs.append("balance.starter_collection: unknown card '%s'" % cid)
	return errs


static func _json_files(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			out.append(dir + "/" + f)
	out.sort()
	return out


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: missing" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _read_array(path: String) -> Array:
	var v: Variant = _read_json(path)
	if v is Array:
		return v
	if v != null:
		errors.append("%s: expected a JSON array" % path)
	return []


func _read_dict(path: String) -> Dictionary:
	var v: Variant = _read_json(path)
	if v is Dictionary:
		return v
	if v != null:
		errors.append("%s: expected a JSON object" % path)
	return {}
