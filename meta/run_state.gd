class_name RunState
extends RefCounted
## One roguelike run: deck, HP and progress. Built from the base deck plus a few
## cards the player picks from their collection. All randomness forks from the
## run seed, so a run can be replayed (and daily seeds shared).

var db: CardDB
var seed_value := 0
var rng: GameRng
var deck: Array = []
var hp := 0
var max_hp := 0
var floor_num := 0
var gold := 0
var combats_won := 0


## picks: card ids chosen from the player's collection (must own each one).
static func start(db_in: CardDB, profile: Profile, picks: Array, seed_in: int) -> RunState:
	var r := RunState.new()
	r.db = db_in
	r.seed_value = seed_in
	r.rng = GameRng.new(seed_in)
	r.max_hp = int(db_in.balance.get("player", {}).get("max_hp", 60))
	r.hp = r.max_hp
	r.deck = db_in.make_deck(db_in.balance.get("base_deck", []))
	var allowed := int(db_in.balance.get("starter_picks", 4))
	var used := {}
	for id in picks.slice(0, allowed):
		used[id] = int(used.get(id, 0)) + 1
		if used[id] > profile.collection.count(id):
			push_error("Run pick '%s' exceeds owned copies" % id)
			continue
		r.deck.append(db_in.instance(id))
	return r


## Default picks for a quick start: first owned non-starter cards.
static func default_picks(db_in: CardDB, profile: Profile) -> Array:
	var out: Array = []
	for id in profile.collection.owned_ids():
		var c := db_in.card(id)
		if c != null and c.rarity != "starter":
			out.append(id)
	return out.slice(0, int(db_in.balance.get("starter_picks", 4)))


func start_combat(encounter_id: String) -> Combat:
	floor_num += 1
	var c := Combat.create(db, deck, encounter_id, rng.fork("combat:%d" % floor_num), hp)
	c.player.max_hp = max_hp
	return c


func finish_combat(c: Combat) -> void:
	hp = c.player.hp
	if c.phase == Combat.Phase.WON:
		combats_won += 1
		gold += 10 + rng.fork("gold:%d" % floor_num).range_i(0, 10)


func reward_choices() -> Array:
	return Packs.reward_choices(db, rng.fork("reward:%d" % floor_num))


func add_card(id: String) -> void:
	deck.append(db.instance(id))
