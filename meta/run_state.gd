class_name RunState
extends RefCounted
## One roguelike run: deck, HP, gold, talismans, map position and heat level.
## Built from the base deck plus a few cards the player picks from their
## collection. All randomness forks from the run seed, so a run replays exactly.

var db: CardDB
var seed_value := 0
var rng: GameRng
var deck: Array = []
var hp := 0
var max_hp := 0
var gold := 0
var floor_num := 0
var heat := 0
var talismans: Array = []
var map: RunMap
var node_id := -1
var path: Array = []
var combats_won := 0
var elites_won := 0
var boss_won := false
var over := false
var card_plays: Dictionary = {}
var remove_cost := 0
var outcome_counter := 0
## Talisman ids this player hasn't unlocked yet (excluded from rolls).
var locked_talismans: Array = []


## picks: card ids chosen from the player's collection (must own each one).
static func start(db_in: CardDB, profile: Profile, picks: Array, seed_in: int, heat_in: int = 0) -> RunState:
	var r := RunState.new()
	r.db = db_in
	r.seed_value = seed_in
	r.rng = GameRng.new(seed_in)
	r.heat = heat_in
	r.max_hp = int(db_in.balance.get("player", {}).get("max_hp", 60)) + int(r.heat_mod("max_hp", 0))
	r.hp = r.max_hp
	r.gold = int(db_in.balance.get("start_gold", 50))
	r.remove_cost = int(db_in.balance.get("shop", {}).get("remove_base", 50))
	r.deck = db_in.make_deck(db_in.balance.get("base_deck", []))
	var allowed := profile.starter_picks(db_in)
	var used := {}
	for id in picks.slice(0, allowed):
		used[id] = int(used.get(id, 0)) + 1
		if used[id] > profile.collection.count(id):
			push_error("Run pick '%s' exceeds owned copies" % id)
			continue
		r.deck.append(db_in.instance(id))
	var curse := str(r.heat_mod("start_curse", ""))
	if curse != "":
		r.deck.append(db_in.instance(curse))
	for tid in db_in.talismans:
		if int(db_in.talismans[tid].get("unlock_level", 1)) > profile.level():
			r.locked_talismans.append(tid)
	r.map = RunMap.generate(db_in, r.rng.fork("map"))
	var start_t := str(db_in.balance.get("start_talisman", ""))
	if start_t != "":
		r.add_talisman(start_t)
	return r


## Default picks for a quick start: first owned non-starter cards.
static func default_picks(db_in: CardDB, profile: Profile) -> Array:
	var out: Array = []
	for id in profile.collection.owned_ids():
		var c := db_in.card(id)
		if c != null and c.rarity != "starter":
			out.append(id)
	return out.slice(0, profile.starter_picks(db_in))


# --- heat ---------------------------------------------------------------------

## Combined value of a heat modifier across all active heat levels.
## Numbers add (multipliers stored as +0.1 = +10%); strings take the last value.
func heat_mod(key: String, default: Variant) -> Variant:
	var levels: Array = db.balance.get("heat", [])
	var v: Variant = default
	for i in mini(heat, levels.size()):
		var mods: Dictionary = levels[i].get("mods", {})
		if mods.has(key):
			v = (float(v) + float(mods[key])) if (default is int or default is float) else mods[key]
	return v


func combat_opts() -> Dictionary:
	return {
		"max_hp": max_hp,
		"talismans": talismans,
		"enemy_hp_mult": 1.0 + float(heat_mod("enemy_hp_pct", 0.0)),
		"enemy_might": int(heat_mod("enemy_might", 0)),
	}


# --- map ----------------------------------------------------------------------

func available_nodes() -> Array:
	if over:
		return []
	if node_id < 0:
		return map.start_nodes()
	return map.node(node_id)["next"].duplicate()


func current_node() -> Dictionary:
	return {} if node_id < 0 else map.node(node_id)


func enter(id: int) -> Dictionary:
	if id not in available_nodes():
		push_error("Node %d not reachable" % id)
		return {}
	node_id = id
	path.append(id)
	var node := map.node(id)
	floor_num = int(node["row"]) + 1
	return node


# --- combat -------------------------------------------------------------------

func start_combat(encounter_id: String) -> Combat:
	var c := Combat.create(db, deck, encounter_id, rng.fork("combat:%d" % floor_num), hp, combat_opts())
	return c


## Returns rewards: {"gold": int, "cards": [ids], "talisman": id or ""}.
func finish_combat(c: Combat) -> Dictionary:
	hp = c.player.hp
	for id in c.play_counts():
		card_plays[id] = int(card_plays.get(id, 0)) + c.play_counts()[id]
	var rewards := {"gold": 0, "cards": [], "talisman": ""}
	if c.phase != Combat.Phase.WON:
		over = true
		return rewards
	combats_won += 1
	var kind := str(db.encounters.get(c.encounter_id, {}).get("kind", "normal"))
	var g: Array = db.balance.get("gold", {}).get(kind, [10, 20])
	rewards["gold"] = rng.fork("gold:%d" % floor_num).range_i(int(g[0]), int(g[1]))
	gold += rewards["gold"]
	rewards["cards"] = reward_choices(kind)
	if kind == "elite":
		elites_won += 1
		rewards["talisman"] = roll_talisman("", rng.fork("elite_t:%d" % floor_num))
	if kind == "boss":
		boss_won = true
		over = true
	return rewards


func reward_choices(kind: String = "normal") -> Array:
	return Packs.reward_choices(db, rng.fork("reward:%d" % floor_num), kind)


func add_card(id: String) -> void:
	deck.append(db.instance(id))


# --- talismans ----------------------------------------------------------------

func add_talisman(id: String) -> void:
	if id == "" or id in talismans or not db.talismans.has(id):
		return
	talismans.append(id)
	for o in db.talismans[id].get("pickup", []):
		RunOutcomes.apply(self, o)


## rarity "" = weighted roll from balance.talisman_weights.
func roll_talisman(rarity: String, r: GameRng) -> String:
	if rarity == "":
		rarity = str(r.weighted(db.balance.get("talisman_weights", {"common": 1})))
	var pool: Array = []
	for id in db.talismans:
		var t: Dictionary = db.talismans[id]
		if t.get("rarity", "") == rarity and id not in talismans and id not in locked_talismans:
			pool.append(id)
	pool.sort()
	if pool.is_empty() and rarity != "common":
		return roll_talisman("common", r)
	return str(r.pick(pool)) if not pool.is_empty() else ""


# --- rest / shop / events -----------------------------------------------------

func rest_heal() -> int:
	var pct := float(db.balance.get("rest_heal_pct", 0.3)) * (1.0 + float(heat_mod("rest_heal_pct", 0.0)))
	var before := hp
	hp = mini(max_hp, hp + int(max_hp * pct))
	return hp - before


func upgrade_card(deck_idx: int) -> bool:
	if deck_idx < 0 or deck_idx >= deck.size():
		return false
	var card: CardInstance = deck[deck_idx]
	if card.upgraded or card.def.rarity == "curse":
		return false
	card.upgraded = true
	return true


## {"cards": [{"id", "price"}], "talismans": [{"id", "price"}], "remove": price}
func make_shop() -> Dictionary:
	var cfg: Dictionary = db.balance.get("shop", {})
	var r := rng.fork("shop:%d" % floor_num)
	var prices: Dictionary = cfg.get("card_price", {})
	var cards: Array = []
	for id in Packs.reward_choices(db, r, "shop"):
		var c := db.card(id)
		cards.append({"id": id, "price": int(prices.get(c.rarity, 50)) + r.range_i(-5, 5)})
	var tal: Array = []
	for i in 2:
		var tid := roll_talisman("", r)
		if tid != "" and tid not in tal.map(func(x: Dictionary) -> String: return x["id"]):
			var tp: Dictionary = cfg.get("talisman_price", {})
			tal.append({"id": tid, "price": int(tp.get(db.talismans[tid]["rarity"], 150))})
	return {"cards": cards, "talismans": tal, "remove": remove_cost}


func buy(item: Dictionary, is_talisman: bool) -> bool:
	if gold < int(item["price"]) or item.get("sold", false):
		return false
	gold -= int(item["price"])
	item["sold"] = true
	if is_talisman:
		add_talisman(item["id"])
	else:
		add_card(item["id"])
	return true


func remove_card(deck_idx: int) -> bool:
	if gold < remove_cost or deck_idx < 0 or deck_idx >= deck.size():
		return false
	gold -= remove_cost
	deck.remove_at(deck_idx)
	remove_cost += int(db.balance.get("shop", {}).get("remove_step", 25))
	return true


func pick_event() -> Dictionary:
	var ids := db.events.keys()
	ids.sort()
	var id: String = rng.fork("event:%d" % floor_num).pick(ids)
	return db.events[id]


func can_choose(choice: Dictionary) -> bool:
	var req: Dictionary = choice.get("requires", {})
	return gold >= int(req.get("gold", 0)) and hp > int(req.get("hp", 0))


## Applies an event choice. Returns log lines for the UI.
func choose(choice: Dictionary) -> Array:
	var lines: Array = []
	if not can_choose(choice):
		return lines
	for o in choice.get("outcomes", []):
		var line := RunOutcomes.apply(self, o)
		if line != "":
			lines.append(line)
	return lines


func summary() -> String:
	return "floor %d hp %d/%d gold %d deck %d talismans %s" % [floor_num, hp, max_hp, gold, deck.size(), ",".join(talismans)]
