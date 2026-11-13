class_name Records
extends RefCounted
## Long-term goals between runs. Pure rules, no Nodes.
##   tally      -> per-run counters read from each fight's event log (RunState.tally)
##   contracts  -> bonus clauses rolled onto each job (data/contracts.json): meet one, earn extra rep
##   exploits   -> the Exploit log: lifetime achievements with a line of lore (data/exploits.json)
##   binders    -> per crew: own every common, every uncommon, then the full set (balance.binders)
##   daily      -> one seeded breach per calendar day: same job, heat and seed for everyone
## Rewards are cosmetic or currency (dust, rep, card backs, titles), never raw power.

## Counters a fight adds to RunState.tally. "max_*" keep the best value, the rest add up.
const TALLY := ["clean_fights", "fast_cores", "daemons", "max_burn", "max_ward", "big_hit", "kills", "cards_played"]
const BINDER_TIERS := ["common", "uncommon", "full"]
const TIER_NAMES := {"common": "Commons", "uncommon": "Uncommons", "full": "Full set"}
## Card backs: "default", "glitch" (Exploit log), or a crew id (that crew's full binder).
const BACK_GLITCH := "glitch"


# --- per-run tally ----------------------------------------------------------------

## Reads a finished fight's event log into the run's tally.
static func tally_combat(run: RunState, c: Combat) -> void:
	var t := run.tally
	var lost := 0
	var burn := 0
	var ward := 0
	var hit := 0
	for e in c.events:
		match str(e["t"]):
			"damage":
				var target := str(e.get("target", ""))
				if target == "player" and int(e.get("amount", 0)) > 0:
					lost += int(e["amount"])
				elif target.begins_with("e") and str(e.get("source", "")) == "player" and str(e.get("kind", "")) == "attack":
					hit = maxi(hit, int(e.get("amount", 0)) + int(e.get("blocked", 0)))
			"status":
				if str(e.get("status", "")) == "burn" and str(e.get("target", "")).begins_with("e"):
					burn = maxi(burn, int(e.get("total", 0)))
			"ward":
				if str(e.get("target", "")) == "player":
					ward = maxi(ward, int(e.get("ward", 0)))
			"summon":
				t["daemons"] = int(t.get("daemons", 0)) + 1
			"death":
				if str(e.get("target", "")).begins_with("e"):
					t["kills"] = int(t.get("kills", 0)) + 1
			"play":
				t["cards_played"] = int(t.get("cards_played", 0)) + 1
	t["max_burn"] = maxi(int(t.get("max_burn", 0)), burn)
	t["max_ward"] = maxi(int(t.get("max_ward", 0)), ward)
	t["big_hit"] = maxi(int(t.get("big_hit", 0)), hit)
	if c.phase == Combat.Phase.WON:
		if lost == 0:
			t["clean_fights"] = int(t.get("clean_fights", 0)) + 1
		var kind := str(run.db.encounters.get(c.encounter_id, {}).get("kind", ""))
		if kind == "boss" and c.turn <= 6:
			t["fast_cores"] = int(t.get("fast_cores", 0)) + 1


## A run's tally plus the counters RunState already keeps.
static func run_stat(run: RunState, stat: String) -> int:
	match stat:
		"elites":
			return run.elites_won
		"deck_size":
			return run.deck.size()
		"floor":
			return run.floor_num
	return int(run.tally.get(stat, 0))


# --- contracts (job bonus clauses) ---------------------------------------------------

## Clause ids for one job offer. Stable for the same rng.
static func roll_clauses(db: CardDB, rng: GameRng) -> Array:
	var pool: Array = db.contracts.keys()
	pool.sort()
	var out: Array = []
	for i in mini(int(db.balance.get("contracts", {}).get("per_job", 2)), pool.size()):
		var id: String = rng.pick(pool)
		pool.erase(id)
		out.append(id)
	return out


static func clause_met(db: CardDB, run: RunState, id: String) -> bool:
	var cl: Dictionary = db.contracts.get(id, {})
	if cl.is_empty():
		return false
	if cl.get("needs_act", false) and run.acts_cleared < 1:
		return false
	var v := run_stat(run, str(cl.get("stat", "")))
	if cl.has("at_most"):
		return v <= int(cl["at_most"])
	return v >= int(cl.get("at_least", 1))


## Rep a met clause pays at this heat.
static func clause_rep(db: CardDB, id: String, heat: int) -> int:
	var base := int(db.contracts.get(id, {}).get("rep", 0))
	return int(base * (1.0 + 0.1 * heat) * float(db.balance.get("contracts", {}).get("rep_mult", 1.0)))


## "Ghost protocol (+25 rep): Win 3 fights without losing any HP."
static func clause_text(db: CardDB, id: String, heat: int = 0) -> String:
	var cl: Dictionary = db.contracts.get(id, {})
	return "%s (+%d): %s" % [cl.get("name", id), clause_rep(db, id, heat), cl.get("text", "")]


# --- daily breach --------------------------------------------------------------------

## Today's key, e.g. "2026-11-13" (the device's local date).
static func today() -> String:
	return Time.get_date_string_from_system()


## Everyone gets the same breach for a date: {"date", "seed", "job", "targets", "heat"}.
static func daily(db: CardDB, date: String) -> Dictionary:
	var seed_in := absi(hash("daily:" + date)) % 2000000000
	var rng := GameRng.new(seed_in)
	var board := Jobs.board(db)
	var job: String = board[rng.range_i(0, board.size() - 1)]
	var heat := int(db.balance.get("daily", {}).get("heat", 1))
	return {"date": date, "seed": seed_in, "job": job, "heat": heat,
		"targets": Jobs.targets(db, job, Jobs.extra_targets(db, heat), rng.fork("targets"))}


## Daily score: nodes, sentries, layers, the final Core, and a little for clean fights.
static func score(run: RunState) -> int:
	return run.floor_num * 10 + run.elites_won * 25 + run.acts_cleared * 100 + (250 if run.boss_won else 0) \
		+ int(run.tally.get("clean_fights", 0)) * 5


# --- binders ---------------------------------------------------------------------------

## Card ids that fill a crew's binder tier ("full" = every rarity).
static func binder_ids(db: CardDB, faction: String, tier: String) -> Array:
	return db.ids_where(func(c: CardDef) -> bool:
		return c.faction == faction and c.rarity not in ["starter", "curse"] and (tier == "full" or c.rarity == tier))


## [{"tier", "name", "have", "need", "done", "claimed"}] for one crew.
static func binder(db: CardDB, p: Profile, faction: String) -> Array:
	var out: Array = []
	for tier in BINDER_TIERS:
		var ids := binder_ids(db, faction, tier)
		var have := ids.filter(func(id: String) -> bool: return p.collection.owns(id)).size()
		out.append({"tier": tier, "name": TIER_NAMES[tier], "have": have, "need": ids.size(),
			"done": have >= ids.size() and ids.size() > 0, "claimed": p.binders.has("%s:%s" % [faction, tier])})
	return out


## Grants every finished binder page not yet claimed. Returns lines for a toast.
static func claim_binders(db: CardDB, p: Profile) -> Array:
	var lines: Array = []
	var cfg: Dictionary = db.balance.get("binders", {})
	for f in Jobs.board(db) + ["neutral"]:
		for page in binder(db, p, f):
			if not page["done"] or page["claimed"]:
				continue
			var key := "%s:%s" % [f, page["tier"]]
			p.binders[key] = true
			var r: Dictionary = cfg.get(page["tier"], {})
			var got: Array[String] = []
			if int(r.get("dust", 0)) > 0:
				p.collection.dust += int(r["dust"])
				got.append("+%d dust" % int(r["dust"]))
			if r.get("card_back", false):
				got.append("%s card back" % Lexicon.faction(f))
			if r.get("title", false):
				got.append("title \"%s\"" % title_for(f))
			lines.append("Binder: %s %s complete (%s)" % [Lexicon.faction(f), page["name"].to_lower(), ", ".join(got)])
	return lines


static func title_for(faction: String) -> String:
	return "%s Archivist" % Lexicon.faction(faction)


## Card backs and titles this profile has unlocked.
static func card_backs(p: Profile) -> Array:
	var out: Array = ["default"]
	if p.exploits.size() >= 5:
		out.append(BACK_GLITCH)
	for key in p.binders:
		if str(key).ends_with(":full"):
			out.append(str(key).split(":")[0])
	return out


static func titles(p: Profile) -> Array:
	var out: Array = [""]
	for key in p.binders:
		if str(key).ends_with(":full"):
			out.append(title_for(str(key).split(":")[0]))
	for id in p.exploits:
		out.append(str(id))
	return out


# --- exploit log ------------------------------------------------------------------------

## Lifetime value of an exploit stat: run bests live in Profile.stats under "best_<stat>".
static func life_stat(db: CardDB, p: Profile, stat: String) -> int:
	match stat:
		"foils":
			var n := 0
			for id in p.collection.foils:
				n += int(p.collection.foils[id])
			return n
		"binder_pages":
			return p.binders.size()
		"crews_worked":
			return Jobs.board(db).filter(func(f: String) -> bool: return int(p.stats.get("jobs_" + f, 0)) > 0).size()
		"wins", "packs_opened", "best_floor", "daily_runs", "clauses_met", "best_win_heat":
			return int(p.stats.get(stat, 0))
	return int(p.stats.get("best_" + stat, 0))


## Unlocks every exploit now earned. Returns lines.
static func check_exploits(db: CardDB, p: Profile) -> Array:
	var lines: Array = []
	var ids: Array = db.exploits.keys()
	ids.sort()
	for id in ids:
		if p.exploits.has(id):
			continue
		var x: Dictionary = db.exploits[id]
		if life_stat(db, p, str(x.get("stat", ""))) >= int(x.get("at_least", 1)):
			p.exploits[id] = true
			lines.append("Exploit logged: %s" % x.get("name", id))
	return lines


## Folds a finished run into lifetime stats, pays met clauses and records the daily.
## Called by Profile.finish_run. Returns lines.
static func finish_run(db: CardDB, p: Profile, run: RunState) -> Array:
	var lines: Array = []
	for k in TALLY:
		p.stats["best_" + k] = maxi(int(p.stats.get("best_" + k, 0)), int(run.tally.get(k, 0)))
	if run.boss_won:
		p.stats["best_win_heat"] = maxi(int(p.stats.get("best_win_heat", 0)), run.heat)
	if run.job != "":
		p.stats["jobs_" + run.job] = int(p.stats.get("jobs_" + run.job, 0)) + 1
		for id in run.clauses:
			if clause_met(db, run, id):
				var rep := clause_rep(db, id, run.heat)
				p.rep[run.job] = p.rep_of(run.job) + rep
				p.stats["clauses_met"] = int(p.stats.get("clauses_met", 0)) + 1
				lines.append("Clause met: %s (+%d %s)" % [db.contracts[id]["name"], rep, Jobs.rep_name(db, run.job)])
	if run.daily != "":
		var s := score(run)
		p.stats["daily_runs"] = int(p.stats.get("daily_runs", 0)) + 1
		p.daily["last"] = run.daily
		var best: Dictionary = p.daily.get("scores", {})
		best[run.daily] = maxi(int(best.get(run.daily, 0)), s)
		p.daily["scores"] = best
		p.daily["best"] = maxi(int(p.daily.get("best", 0)), s)
		lines.append("Daily breach score: %d (best ever %d)" % [s, int(p.daily["best"])])
		var packs := int(db.balance.get("daily", {}).get("packs", 0))
		if packs > 0:
			p.packs_unopened += packs
			lines.append("Daily breach pay: +%d pack%s" % [packs, "" if packs == 1 else "s"])
	return lines


static func validate(db: CardDB) -> Array[String]:
	var errs: Array[String] = []
	var run_stats := TALLY + ["elites", "deck_size", "floor"]
	for id in db.contracts:
		var cl: Dictionary = db.contracts[id]
		if str(cl.get("stat", "")) not in run_stats:
			errs.append("contract '%s': unknown stat '%s'" % [id, cl.get("stat", "")])
		if str(cl.get("name", "")) == "" or str(cl.get("text", "")) == "":
			errs.append("contract '%s': needs name and text" % id)
	var life := ["foils", "binder_pages", "crews_worked", "wins", "packs_opened", "best_floor", "daily_runs", "clauses_met", "best_win_heat"]
	for id in db.exploits:
		var x: Dictionary = db.exploits[id]
		if str(x.get("stat", "")) not in life + TALLY:
			errs.append("exploit '%s': unknown stat '%s'" % [id, x.get("stat", "")])
		if str(x.get("lore", "")) == "":
			errs.append("exploit '%s': needs lore" % id)
	return errs
