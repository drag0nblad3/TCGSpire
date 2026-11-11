class_name Packs
extends RefCounted
## Pack opening and card-reward rolls. Both use rarity weights from balance.json
## and never include starter cards. Packs are earned through play only.


## Returns [{"id": String, "foil": bool}, ...]
static func open(db: CardDB, rng: GameRng) -> Array:
	var cfg: Dictionary = db.balance.get("pack", {})
	var out: Array = []
	for i in int(cfg.get("size", 5)):
		var id := roll_card(db, rng, cfg.get("weights", {"common": 1}))
		out.append({"id": id, "foil": rng.chance(float(cfg.get("foil_chance", 0.0)))})
	return out


## Distinct card choices after a combat.
static func reward_choices(db: CardDB, rng: GameRng) -> Array:
	var cfg: Dictionary = db.balance.get("reward", {})
	var out: Array = []
	var guard := 0
	while out.size() < int(cfg.get("choices", 3)) and guard < 100:
		guard += 1
		var id := roll_card(db, rng, cfg.get("weights", {"common": 1}))
		if id != "" and id not in out:
			out.append(id)
	return out


static func roll_card(db: CardDB, rng: GameRng, weights: Dictionary) -> String:
	# Drop rarities with no cards so a roll never comes up empty.
	var usable := {}
	for r in weights:
		if not _pool(db, r).is_empty():
			usable[r] = weights[r]
	if usable.is_empty():
		return ""
	var rarity: String = rng.weighted(usable)
	return rng.pick(_pool(db, rarity))


static func _pool(db: CardDB, rarity: String) -> Array:
	var ids := db.ids_where(func(c: CardDef) -> bool: return c.rarity == rarity and rarity != "starter")
	ids.sort()
	return ids
