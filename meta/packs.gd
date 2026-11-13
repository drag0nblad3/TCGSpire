class_name Packs
extends RefCounted
## Pack opening and card-reward rolls. Both use rarity weights from balance.json
## and never include starter cards. Packs are earned through play only.


## Pack kinds: "normal", "premium" and one crew pack per crew ("crew:ember", "crew:neutral" = Street).
## Each kind's settings are balance.pack with balance.pack_types[type] laid over it (see config()).
const NORMAL := "normal"
const PREMIUM := "premium"


## Every pack kind, in shelf order: premium, the crews (Street last), normal.
static func kinds() -> Array:
	var out: Array = [PREMIUM]
	for f in Lexicon.FACTION:
		if f != "neutral":
			out.append(crew_kind(f))
	out.append(crew_kind("neutral"))
	out.append(NORMAL)
	return out


static func crew_kind(faction: String) -> String:
	return "crew:" + faction


## The crew a pack kind is limited to ("" for normal and premium).
static func crew_of(kind: String) -> String:
	return kind.substr(5) if kind.begins_with("crew:") else ""


static func type_of(kind: String) -> String:
	return "crew" if kind.begins_with("crew:") else kind


static func is_kind(kind: String) -> bool:
	return kind in kinds()


## balance.pack with the kind's pack_types entry laid over it (top-level keys replace).
static func config(db: CardDB, kind: String = NORMAL) -> Dictionary:
	var cfg: Dictionary = db.balance.get("pack", {}).duplicate(true)
	var over: Dictionary = db.balance.get("pack_types", {}).get(type_of(kind), {})
	for k in over:
		cfg[k] = over[k]
	return cfg


## Player-facing name: "Data cache", "Burner cache", "Zero-day cache".
static func kind_name(db: CardDB, kind: String) -> String:
	var n := str(db.balance.get("pack_types", {}).get(type_of(kind), {}).get("name", "Data cache"))
	return n % Lexicon.faction(crew_of(kind)) if "%s" in n else n


## Returns [{"id": String, "foil": bool, "hot": bool}, ...]. The last card is the hot slot
## (config "hot_slot"). With a profile, the hot slot honours that kind's own pity timers
## (config "pity": a rare+ / mythic at least every N packs of this kind, counters in
## profile.pack_pity[kind]) and cards whose copy ladder is complete are rerolled once.
## Crew packs only hold cards of that crew (joint ops of the crew included).
static func open(db: CardDB, rng: GameRng, profile: Profile = null, kind: String = NORMAL) -> Array:
	var cfg := config(db, kind)
	var crew := crew_of(kind)
	var size := int(cfg.get("size", 5))
	var hot: Dictionary = cfg.get("hot_slot", {})
	var out: Array = []
	for i in size:
		var is_hot := i == size - 1 and not hot.is_empty()
		var weights: Dictionary = hot if is_hot else cfg.get("weights", {"common": 1})
		if is_hot and profile != null:
			weights = pity_weights(db, profile, hot, kind)
		var id := roll_card(db, rng, weights, [], [], crew)
		if profile != null and cfg.get("reroll_complete", false) and profile.copies_complete(db, id):
			id = roll_card(db, rng, {db.card(id).rarity: 1}, [], [], crew)
		out.append({"id": id, "foil": rng.chance(float(cfg.get("foil_chance", 0.0))), "hot": is_hot})
	if profile != null:
		_tick_pity(db, profile, out, kind)
	return out


## Hot slot weights after the kind's pity timers: forced mythic, forced rare+, or as configured.
static func pity_weights(db: CardDB, profile: Profile, hot: Dictionary, kind: String = NORMAL) -> Dictionary:
	var pity: Dictionary = config(db, kind).get("pity", {})
	if pity.has("mythic") and profile.pity_count(kind, "mythic") + 1 >= int(pity["mythic"]):
		return {"mythic": 1}
	if pity.has("rare") and profile.pity_count(kind, "rare") + 1 >= int(pity["rare"]):
		return {"rare": float(hot.get("rare", 1)), "mythic": float(hot.get("mythic", 0))}
	return hot


## Packs of this kind left until its pity timer guarantees a rarity (1 = the next pack).
## 0 = this kind has no timer for that rarity.
static func pity_left(db: CardDB, profile: Profile, rarity: String, kind: String = NORMAL) -> int:
	var pity: Dictionary = config(db, kind).get("pity", {})
	if not pity.has(rarity):
		return 0
	return maxi(1, int(pity[rarity]) - profile.pity_count(kind, rarity))


static func _tick_pity(db: CardDB, profile: Profile, cards: Array, kind: String) -> void:
	var rarities: Array = cards.map(func(c: Dictionary) -> String: return db.card(c["id"]).rarity)
	var counters: Dictionary = profile.pack_pity.get(kind, {"rare": 0, "mythic": 0})
	counters["rare"] = 0 if ("rare" in rarities or "mythic" in rarities) else int(counters.get("rare", 0)) + 1
	counters["mythic"] = 0 if "mythic" in rarities else int(counters.get("mythic", 0)) + 1
	profile.pack_pity[kind] = counters


## Chance (0..1) that one pack of this kind holds at least one card of `rarity` or better,
## ignoring pity. For the odds tables in Rules and the shelf.
static func odds_at_least(db: CardDB, kind: String, rarity: String) -> float:
	var order := ["common", "uncommon", "rare", "mythic"]
	var cfg := config(db, kind)
	var size := int(cfg.get("size", 4))
	var hot: Dictionary = cfg.get("hot_slot", {})
	var miss := 1.0
	for i in size:
		var w: Dictionary = hot if (i == size - 1 and not hot.is_empty()) else cfg.get("weights", {})
		var total := 0.0
		var good := 0.0
		for r in w:
			total += float(w[r])
			if order.find(r) >= order.find(rarity):
				good += float(w[r])
		miss *= 1.0 - (good / total if total > 0.0 else 0.0)
	return 1.0 - miss


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


## crew: only cards of that crew (CardDef.is_of), "" = any.
static func roll_card(db: CardDB, rng: GameRng, weights: Dictionary, banned: Array = [], excluded: Array = [], crew: String = "") -> String:
	# Drop rarities with no cards so a roll never comes up empty.
	var usable := {}
	for r in weights:
		if not _pool(db, r, banned, excluded, crew).is_empty():
			usable[r] = weights[r]
	if usable.is_empty():
		return ""
	var rarity: String = rng.weighted(usable)
	return rng.pick(_pool(db, rarity, banned, excluded, crew))


static func _pool(db: CardDB, rarity: String, banned: Array = [], excluded: Array = [], crew: String = "") -> Array:
	var ids := db.ids_where(func(c: CardDef) -> bool: return c.rarity == rarity and rarity not in ["starter", "curse"] and not c.banned_by(banned) \
		and c.id not in excluded and (crew == "" or c.is_of(crew)))
	ids.sort()
	return ids
