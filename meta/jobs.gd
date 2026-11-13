class_name Jobs
extends RefCounted
## Faction jobs. Every run is a job for a client faction (data/factions.json),
## run against target crews: the client's rival, plus more at high heat
## (heat mod "extra_targets"). There is always exactly one client.
##   - at least balance.jobs.client_share of your custom picks must be the client's,
##   - targets are banned: not pickable and never offered during the run,
##   - targets' enemies (encounters with that "faction") fill the map,
##   - finishing (or dying on) the job pays rep in the client's currency,
##     more for each extra target.
## Rep buys that faction's rig upgrades and flashes its cards to firmware.
## job "" = freelance (tests, sims): no rules, no rep.


static func board(db: CardDB) -> Array:
	var out: Array = db.factions.keys()
	out.sort()
	return out


static func info(db: CardDB, faction: String) -> Dictionary:
	return db.factions.get(faction, {})


static func banned(db: CardDB, faction: String) -> Array:
	return info(db, faction).get("rivals", []).duplicate()


## Crews this job runs against: rivals first, then `extra` more picked from the
## remaining crews (never the client).
static func targets(db: CardDB, faction: String, extra: int, rng: GameRng) -> Array:
	var out := banned(db, faction)
	var rest: Array = board(db).filter(func(f: String) -> bool: return f != faction and f not in out)
	for i in mini(extra, rest.size()):
		var f: String = rng.pick(rest)
		rest.erase(f)
		out.append(f)
	return out


## Extra targets at this heat (sum of the heat levels' "extra_targets").
static func extra_targets(db: CardDB, heat: int) -> int:
	var n := 0
	var levels: Array = db.balance.get("heat", [])
	for i in mini(heat, levels.size()):
		n += int(levels[i].get("mods", {}).get("extra_targets", 0))
	return n


## One job per crew, with its targets for this heat. Stable for a given rng seed.
static func offers(db: CardDB, heat: int, rng: GameRng) -> Array:
	var out: Array = []
	for f in board(db):
		out.append({"client": f, "targets": targets(db, f, extra_targets(db, heat), rng.fork("job:" + f))})
	return out


static func required(db: CardDB, faction: String, picks_allowed: int) -> int:
	if faction == "":
		return 0
	return ceili(picks_allowed * float(db.balance.get("jobs", {}).get("client_share", 0.5)))


## "" when the picks satisfy the job, else what's wrong (for the picker UI).
static func check(db: CardDB, faction: String, picks: Array, picks_allowed: int, targets_in: Array = []) -> String:
	if faction == "":
		return ""
	var ban := targets_in if not targets_in.is_empty() else banned(db, faction)
	var theirs := 0
	for id in picks:
		var c := db.card(str(id))
		if c == null:
			continue
		if c.banned_by(ban):
			return "%s programs are banned on this job." % Lexicon.faction(c.faction if c.faction in ban else c.faction2)
		if c.is_of(faction):
			theirs += 1
	var need := required(db, faction, picks_allowed)
	if theirs < need:
		return "Load %d more %s program%s (%d of %d)." % [need - theirs, Lexicon.faction(faction), "" if need - theirs == 1 else "s", theirs, need]
	return ""


static func rep_name(db: CardDB, faction: String) -> String:
	return str(info(db, faction).get("rep", Lexicon.faction(faction) + " rep"))


## Rep paid at the end of a run (even a failed one pays for the floors cleared).
static func rep_reward(db: CardDB, run: RunState) -> int:
	if run.job == "":
		return 0
	var cfg: Dictionary = db.balance.get("jobs", {})
	var n := run.floor_num * int(cfg.get("rep_per_floor", 2)) + run.elites_won * int(cfg.get("rep_per_elite", 6)) \
		+ run.acts_cleared * int(cfg.get("rep_per_act", 15)) + (int(cfg.get("rep_boss", 30)) if run.boss_won else 0)
	var extra := maxi(run.banned.size() - banned(db, run.job).size(), 0)
	return int(n * (1.0 + 0.1 * run.heat) * (1.0 + float(cfg.get("rep_per_extra_target", 0.25)) * extra) * (1.0 + run.perk_mod("rep_pct")) * float(cfg.get("rep_mult", 1.0)))


## What a job pays, worked out with the same formulas as the end of a run.
## "packs"/"xp"/"rep": a full clear (every Core breached) with no black sentries;
## "elite_rep"/"elite_xp": about what each black sentry crashed adds; "per_core": packs per Core.
## "pack_list": the pack kinds of a full clear (crew packs are the client's).
## "full_run": premium packs for finishing the job.
## `extra` = target crews beyond the client's rival (Jobs.extra_targets at this heat).
static func payout_preview(db: CardDB, profile: Profile, job: String, heat: int, extra: int = -1) -> Dictionary:
	var r := RunState.new()
	r.db = db
	r.job = job
	r.heat = heat
	r.rig = profile.rig.duplicate()
	r.banned = banned(db, job).duplicate()
	for i in (extra_targets(db, heat) if extra < 0 else extra):
		r.banned.append("extra_target_%d" % i)
	var acts := int(db.balance.get("acts", 3))
	r.acts_cleared = acts
	r.boss_won = true
	r.floor_num = acts * (int(db.balance.get("map", {}).get("rows", 12)) + 1)
	var out := {"packs": Profile.run_packs(db, r), "pack_list": Profile.run_pack_list(db, r),
		"full_run": int(db.balance.get("run_rewards", {}).get("packs_full_run", 0)), "xp": Profile.run_xp(db, r), "rep": rep_reward(db, r),
		"per_core": int(db.balance.get("run_rewards", {}).get("packs_per_boss", 1)),
		"shards_per_elite": int(db.balance.get("run_rewards", {}).get("shards_per_elite", 0)),
		"shards_per_pack": Profile.shards_per_pack(db)}
	r.elites_won = 3
	out["elite_rep"] = roundi((rep_reward(db, r) - int(out["rep"])) / 3.0)
	out["elite_xp"] = roundi((Profile.run_xp(db, r) - int(out["xp"])) / 3.0)
	return out


static func validate(db: CardDB) -> Array[String]:
	var errs: Array[String] = []
	var card_factions := {}
	for id in db.cards:
		var cd: CardDef = db.cards[id]
		card_factions[cd.faction] = true
		if cd.faction2 != "":
			if not db.factions.has(cd.faction) or not db.factions.has(cd.faction2) or cd.faction2 == cd.faction:
				errs.append("card '%s': joint op needs two different crews" % id)
			elif cd.faction2 in db.factions[cd.faction].get("rivals", []) or cd.faction in db.factions[cd.faction2].get("rivals", []):
				errs.append("card '%s': joint op between rivals" % id)
	for f in db.factions:
		if not card_factions.has(f):
			errs.append("faction '%s': no cards" % f)
		for r in db.factions[f].get("rivals", []):
			if not db.factions.has(r) or r == f:
				errs.append("faction '%s': bad rival '%s'" % [f, r])
	for id in db.encounters:
		var ef := str(db.encounters[id].get("faction", ""))
		if ef != "" and not db.factions.has(ef):
			errs.append("encounter '%s': unknown faction '%s'" % [id, ef])
	for f in db.factions:
		for act in range(1, int(db.balance.get("acts", 1)) + 1):
			for k in ["normal", "elite"]:
				if not db.encounters.values().any(func(e: Dictionary) -> bool:
						return e.get("faction", "") == f and int(e.get("act", 1)) == act and e.get("kind", "") == k):
					errs.append("faction '%s': no act %d %s encounter" % [f, act, k])
	for id in db.perks:
		var p: Dictionary = db.perks[id]
		if p.get("scope", "") == "rig" and not db.factions.has(str(p.get("faction", ""))):
			errs.append("perk '%s': rig perks need a job faction" % id)
	return errs
