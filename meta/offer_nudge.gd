class_name OfferNudge
## Hidden weighting for in-run offers (card rewards, rerolls, shops, implant drops).
## Rarity odds never change: once a rarity is rolled, the card or implant is drawn
## from that tier with these weights instead of evenly. Every weight is at least 1,
## and the product is capped (balance.nudge.cap). Packs never use it.
##
## Cards: the missing Handshake partner of a card in the deck (partner), programs
## that answer this act's boss rules (boss) and ones that share a theme the deck is
## building (strategy). At most half of one offer, rounded up (offer_share), may be
## weighted picks; the rest roll at plain odds. Implants: ones that fit the
## deck (fit: daemon, Loop or status engines it already runs) and boss answers.

## Boss rule -> card tags that answer it.
const BOSS_ANSWERS := {
	"guarded": ["aoe", "status:burn"],
	"pool": ["aoe"],
	"shielded_by": ["aoe"],
	"twin": ["aoe"],
	"bond": ["aoe"],
	"jam": ["interrupt", "status:brittle"],
}

## Implant flags that boost one status.
const FLAG_STATUS := {"burn_no_decay": "burn", "regen_slow_decay": "regen"}


## Tags of one effect list (walks nested effects: handshake, daemon rules, ...).
static func effect_tags(v: Variant, out: Dictionary) -> void:
	if v is Array:
		for x in v:
			effect_tags(x, out)
	elif v is Dictionary:
		var d: Dictionary = v
		var op := str(d.get("op", ""))
		if op == "damage" and str(d.get("to", "")) == "all_enemies":
			out["aoe"] = true
		elif op == "apply" and d.has("status"):
			out["status:" + str(d["status"])] = true
		elif op == "interrupt":
			out["interrupt"] = true
		elif op == "summon" or op == "rally":
			out["daemon"] = true
		if d.has("loop"):
			out["loop"] = true
		for k in d:
			if d[k] is Array or d[k] is Dictionary:
				effect_tags(d[k], out)


static func card_tags(c: CardDef) -> Dictionary:
	var out := {}
	effect_tags(c.effects, out)
	effect_tags(c.on_dump, out)
	if c.type == "unit":
		out["daemon"] = true
	return out


## Partner card ids named by this card's Handshake effects.
static func partners(c: CardDef) -> Array:
	var out: Array = []
	_find_handshakes(c.effects, out)
	return out


static func _find_handshakes(v: Variant, out: Array) -> void:
	if v is Array:
		for x in v:
			_find_handshakes(x, out)
	elif v is Dictionary:
		if str(v.get("op", "")) == "handshake" and str(v.get("card", "")) != "":
			out.append(str(v["card"]))
		for k in v:
			if v[k] is Array or v[k] is Dictionary:
				_find_handshakes(v[k], out)


## What an implant leans on (tags the deck must have) and what it adds (for boss answers).
static func talisman_needs(t: Dictionary) -> Dictionary:
	var out := {}
	for tr in t.get("triggers", []):
		var on := str(tr.get("on", ""))
		if str(tr.get("card_type", "")) == "unit" or on == "daemon_closed":
			out["daemon"] = true
		if on == "loop":
			out["loop"] = true
	if t.has("daemon") or bool(t.get("flags_while_daemon", false)) or t.get("mods", {}).has("board_slots"):
		out["daemon"] = true
	var flags: Dictionary = t.get("flags", {})
	if flags.has("loop_bonus"):
		out["loop"] = true
	for f in flags:
		if FLAG_STATUS.has(f):
			out["status:" + FLAG_STATUS[f]] = true
	# An implant that applies a status leans on decks already building it.
	var adds := {}
	effect_tags(t.get("triggers", []), adds)
	for k in adds:
		if str(k).begins_with("status:"):
			out[k] = true
	return out


## {tag: number of deck cards with it} (one count per copy).
static func deck_tags(run: RunState) -> Dictionary:
	var out := {}
	for ci in run.deck:
		for k in card_tags(ci.def):
			out[k] = int(out.get(k, 0)) + 1
	return out


## Card tags that answer this act's boss (empty until the map exists).
static func boss_wants(run: RunState) -> Dictionary:
	var out := {}
	if run.map == null or run.map.nodes.is_empty():
		return out
	var boss: Dictionary = run.map.nodes.back()
	var enc: Dictionary = run.db.encounters.get(str(boss.get("encounter", "")), {})
	for eid in enc.get("enemies", []):
		var rules: Dictionary = run.db.enemies.get(eid, {}).get("rules", {})
		for r in rules:
			for tag in BOSS_ANSWERS.get(r, []):
				out[tag] = true
		var taken: Dictionary = rules.get("taken", {})
		for kind in taken:
			if float(taken[kind]) > 1.0:
				out["attack" if kind == "attack" else "status:" + str(kind)] = true
	return out


static func _cfg(db: CardDB) -> Dictionary:
	return db.balance.get("nudge", {})


## Weight per card id for this run's offers; null Callable when nudging is off.
static func card_weigher(run: RunState) -> Callable:
	var cfg := _cfg(run.db)
	if cfg.is_empty():
		return Callable()
	var in_deck := {}
	for ci in run.deck:
		in_deck[ci.def.id] = true
	var wants := boss_wants(run)
	var themes := strategy_themes(run)
	var db := run.db
	var memo := {}
	return func(id: String) -> float:
		if memo.has(id):
			return memo[id]
		var c := db.card(id)
		if c == null:
			return 1.0
		var w := 1.0
		if not in_deck.has(id) and partners(c).any(func(p: String) -> bool: return in_deck.has(p)):
			w *= float(cfg.get("partner", 1.0))
		if c.type == "attack" and wants.has("attack"):
			w *= float(cfg.get("boss", 1.0))
		else:
			var tags := card_tags(c)
			if tags.keys().any(func(k: String) -> bool: return wants.has(k)):
				w *= float(cfg.get("boss", 1.0))
		if not themes.is_empty() and card_tags(c).keys().any(func(k: String) -> bool: return themes.has(k)):
			w *= float(cfg.get("strategy", 1.0))
		memo[id] = minf(w, float(cfg.get("cap", 3.0)))
		return memo[id]


## Themes the deck is building: a status, daemons or Loop on enough non-starter cards.
static func strategy_themes(run: RunState) -> Dictionary:
	var counts := {}
	for ci in run.deck:
		if ci.def.rarity in ["starter", "curse"]:
			continue
		for k in card_tags(ci.def):
			if str(k).begins_with("status:") or k in ["daemon", "loop"]:
				counts[k] = int(counts.get(k, 0)) + 1
	var out := {}
	var need := int(_cfg(run.db).get("strategy_min_cards", 3))
	for k in counts:
		if int(counts[k]) >= need:
			out[k] = true
	return out


## Most picks of one offer that may come from weighting: half the slots, rounded up.
static func limit(db: CardDB, slots: int) -> int:
	return ceili(slots * float(_cfg(db).get("offer_share", 0.5)))


## True when this id would be weighted above plain odds.
static func boosted(weigh: Callable, id: String) -> bool:
	return weigh.is_valid() and float(weigh.call(id)) > 1.0 + 0.0001


static func talisman_weight(run: RunState, id: String, have: Dictionary = {}, wants: Dictionary = {}) -> float:
	var cfg := _cfg(run.db)
	if cfg.is_empty():
		return 1.0
	var t: Dictionary = run.db.talismans.get(id, {})
	var w := 1.0
	var need_min := int(cfg.get("fit_min_cards", 3))
	var needs := talisman_needs(t)
	if needs.keys().any(func(k: String) -> bool: return int(have.get(k, 0)) >= need_min):
		w *= float(cfg.get("implant_fit", 1.0))
	var adds := {}
	effect_tags(t.get("triggers", []), adds)
	if adds.keys().any(func(k: String) -> bool: return wants.has(k)):
		w *= float(cfg.get("implant_boss", 1.0))
	return minf(w, float(cfg.get("cap", 3.0)))


## Picks from a sorted pool: evenly when every weight is 1 (same RNG use as before).
static func pick(rng: GameRng, pool: Array, weigh: Callable) -> Variant:
	if pool.is_empty():
		return ""
	if not weigh.is_valid():
		return rng.pick(pool)
	var weights := {}
	var flat := true
	for id in pool:
		var w := float(weigh.call(id))
		weights[id] = w
		flat = flat and is_equal_approx(w, 1.0)
	return rng.pick(pool) if flat else rng.weighted(weights)
