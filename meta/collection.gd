class_name Collection
extends RefCounted
## Cards the player owns between runs, plus crafting dust. Foils are tracked
## separately and are purely cosmetic.

var counts: Dictionary = {}
var foils: Dictionary = {}
var dust := 0


func count(id: String) -> int:
	return int(counts.get(id, 0))


func owns(id: String) -> bool:
	return count(id) > 0


func add(id: String, n: int = 1, foil: bool = false) -> void:
	counts[id] = count(id) + n
	if foil:
		foils[id] = int(foils.get(id, 0)) + n


func owned_ids() -> Array:
	var ids := counts.keys().filter(func(k: String) -> bool: return count(k) > 0)
	ids.sort()
	return ids


## Turns one spare copy into dust. The last copy can't be disenchanted.
func disenchant(id: String, db: CardDB) -> bool:
	var c := db.card(id)
	if c == null or count(id) <= 1 or c.rarity == "starter":
		return false
	counts[id] = count(id) - 1
	if int(foils.get(id, 0)) > count(id):
		foils[id] = count(id)
	dust += int(db.balance.get("dust", {}).get("disenchant", {}).get(c.rarity, 0))
	return true


## Turns a spare glitch foil copy into dust (balance.dust.foil_mult times a normal copy).
## Needs a foil and another copy left over.
func disenchant_foil(id: String, db: CardDB) -> bool:
	var c := db.card(id)
	if c == null or count(id) <= 1 or int(foils.get(id, 0)) <= 0 or c.rarity == "starter":
		return false
	counts[id] = count(id) - 1
	foils[id] = int(foils[id]) - 1
	if int(foils[id]) <= 0:
		foils.erase(id)
	dust += foil_value(id, db)
	return true


static func foil_value(id: String, db: CardDB) -> int:
	var c := db.card(id)
	var d: Dictionary = db.balance.get("dust", {})
	return int(d.get("disenchant", {}).get(c.rarity, 0)) * int(d.get("foil_mult", 4)) if c != null else 0


func craft_cost(id: String, db: CardDB) -> int:
	var c := db.card(id)
	if c == null or c.rarity == "starter":
		return -1
	return int(db.balance.get("dust", {}).get("craft", {}).get(c.rarity, -1))


func craft(id: String, db: CardDB) -> bool:
	var cost := craft_cost(id, db)
	if cost < 0 or dust < cost:
		return false
	dust -= cost
	add(id)
	return true


func to_dict() -> Dictionary:
	return {"counts": counts.duplicate(), "foils": foils.duplicate(), "dust": dust}


static func from_dict(d: Dictionary) -> Collection:
	var c := Collection.new()
	for k in d.get("counts", {}):
		c.counts[k] = int(d["counts"][k])
	for k in d.get("foils", {}):
		c.foils[k] = int(d["foils"][k])
	c.dust = int(d.get("dust", 0))
	return c
