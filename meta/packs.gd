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


## Distinct card choices. kind = normal | elite | boss | shop (balance.reward).
## extra adds choices (perks); banned factions (the job's rivals) are never offered.
static func reward_choices(db: CardDB, rng: GameRng, kind: String = "normal", extra: int = 0, banned: Array = []) -> Array:
	var cfg: Dictionary = db.balance.get("reward", {})
	var weights: Dictionary = cfg.get("weights", {}).get(kind, {"common": 1})
	var count := int(cfg.get("shop_count", 5)) if kind == "shop" else int(cfg.get("choices", 3)) + extra
	var out: Array = []
	var guard := 0
	while out.size() < count and guard < 100:
		guard += 1
		var id := roll_card(db, rng, weights, banned)
		if id != "" and id not in out:
			out.append(id)
	return out


static func roll_card(db: CardDB, rng: GameRng, weights: Dictionary, banned: Array = []) -> String:
	# Drop rarities with no cards so a roll never comes up empty.
	var usable := {}
	for r in weights:
		if not _pool(db, r, banned).is_empty():
			usable[r] = weights[r]
	if usable.is_empty():
		return ""
	var rarity: String = rng.weighted(usable)
	return rng.pick(_pool(db, rarity, banned))


static func _pool(db: CardDB, rarity: String, banned: Array = []) -> Array:
	var ids := db.ids_where(func(c: CardDef) -> bool: return c.rarity == rarity and rarity not in ["starter", "curse"] and c.faction not in banned)
	ids.sort()
	return ids
