class_name Packs
extends RefCounted
## Pack opening and card-reward rolls. Both use rarity weights from balance.json
## and never include starter cards. Packs are earned through play only.


## Returns [{"id": String, "foil": bool, "hot": bool}, ...]. The last card is the hot slot
## (balance.pack.hot_slot: uncommon or better). With a profile, the hot slot honours the pity
## timers (balance.pack.pity: a rare+ / mythic at least every N packs, counters in
## profile.pack_pity) and cards whose copy ladder is complete are rerolled once.
static func open(db: CardDB, rng: GameRng, profile: Profile = null) -> Array:
	var cfg: Dictionary = db.balance.get("pack", {})
	var size := int(cfg.get("size", 5))
	var hot: Dictionary = cfg.get("hot_slot", {})
	var out: Array = []
	for i in size:
		var is_hot := i == size - 1 and not hot.is_empty()
		var weights: Dictionary = hot if is_hot else cfg.get("weights", {"common": 1})
		if is_hot and profile != null:
			weights = pity_weights(db, profile, hot)
		var id := roll_card(db, rng, weights)
		if profile != null and cfg.get("reroll_complete", false) and profile.copies_complete(db, id):
			id = roll_card(db, rng, {db.card(id).rarity: 1})
		out.append({"id": id, "foil": rng.chance(float(cfg.get("foil_chance", 0.0))), "hot": is_hot})
	if profile != null:
		_tick_pity(db, profile, out)
	return out


## Hot slot weights after the pity timers: forced mythic, forced rare+, or as configured.
static func pity_weights(db: CardDB, profile: Profile, hot: Dictionary) -> Dictionary:
	var pity: Dictionary = db.balance.get("pack", {}).get("pity", {})
	if pity.has("mythic") and int(profile.pack_pity.get("mythic", 0)) + 1 >= int(pity["mythic"]):
		return {"mythic": 1}
	if pity.has("rare") and int(profile.pack_pity.get("rare", 0)) + 1 >= int(pity["rare"]):
		return {"rare": float(hot.get("rare", 1)), "mythic": float(hot.get("mythic", 0))}
	return hot


## Packs left until the pity timer guarantees a rarity (1 = the next pack).
static func pity_left(db: CardDB, profile: Profile, rarity: String) -> int:
	var pity: Dictionary = db.balance.get("pack", {}).get("pity", {})
	return maxi(1, int(pity.get(rarity, 0)) - int(profile.pack_pity.get(rarity, 0)))


static func _tick_pity(db: CardDB, profile: Profile, cards: Array) -> void:
	var rarities: Array = cards.map(func(c: Dictionary) -> String: return db.card(c["id"]).rarity)
	profile.pack_pity["rare"] = 0 if ("rare" in rarities or "mythic" in rarities) else int(profile.pack_pity.get("rare", 0)) + 1
	profile.pack_pity["mythic"] = 0 if "mythic" in rarities else int(profile.pack_pity.get("mythic", 0)) + 1


## Distinct card choices. kind = normal | elite | boss | shop (balance.reward).
## extra adds choices (perks); banned factions (the job's rivals) are never offered.
static func reward_choices(db: CardDB, rng: GameRng, kind: String = "normal", extra: int = 0, banned: Array = [], excluded: Array = []) -> Array:
	var cfg: Dictionary = db.balance.get("reward", {})
	var weights: Dictionary = cfg.get("weights", {}).get(kind, {"common": 1})
	var count := int(cfg.get("shop_count", 5)) if kind == "shop" else int(cfg.get("choices", 3)) + extra
	var out: Array = []
	var guard := 0
	while out.size() < count and guard < 100:
		guard += 1
		var id := roll_card(db, rng, weights, banned, excluded)
		if id != "" and id not in out:
			out.append(id)
	return out


static func roll_card(db: CardDB, rng: GameRng, weights: Dictionary, banned: Array = [], excluded: Array = []) -> String:
	# Drop rarities with no cards so a roll never comes up empty.
	var usable := {}
	for r in weights:
		if not _pool(db, r, banned, excluded).is_empty():
			usable[r] = weights[r]
	if usable.is_empty():
		return ""
	var rarity: String = rng.weighted(usable)
	return rng.pick(_pool(db, rarity, banned, excluded))


static func _pool(db: CardDB, rarity: String, banned: Array = [], excluded: Array = []) -> Array:
	var ids := db.ids_where(func(c: CardDef) -> bool: return c.rarity == rarity and rarity not in ["starter", "curse"] and not c.banned_by(banned) and c.id not in excluded)
	ids.sort()
	return ids
