class_name Jobs
extends RefCounted
## Faction jobs. Every run is a job for a client faction (data/factions.json):
##   - at least balance.jobs.client_share of your custom picks must be theirs,
##   - their rivals are banned: not pickable and never offered during the run,
##   - finishing (or dying on) the job pays rep in the client's currency.
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


static func required(db: CardDB, faction: String, picks_allowed: int) -> int:
	if faction == "":
		return 0
	return ceili(picks_allowed * float(db.balance.get("jobs", {}).get("client_share", 0.5)))


## "" when the picks satisfy the job, else what's wrong (for the picker UI).
static func check(db: CardDB, faction: String, picks: Array, picks_allowed: int) -> String:
	if faction == "":
		return ""
	var ban := banned(db, faction)
	var theirs := 0
	for id in picks:
		var c := db.card(str(id))
		if c == null:
			continue
		if c.faction in ban:
			return "%s programs are banned on this job." % Lexicon.faction(c.faction)
		if c.faction == faction:
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
	return int(n * (1.0 + 0.1 * run.heat))


static func validate(db: CardDB) -> Array[String]:
	var errs: Array[String] = []
	var card_factions := {}
	for id in db.cards:
		card_factions[db.cards[id].faction] = true
	for f in db.factions:
		if not card_factions.has(f):
			errs.append("faction '%s': no cards" % f)
		for r in db.factions[f].get("rivals", []):
			if not db.factions.has(r) or r == f:
				errs.append("faction '%s': bad rival '%s'" % [f, r])
	for id in db.perks:
		var p: Dictionary = db.perks[id]
		if p.get("scope", "") == "rig" and not db.factions.has(str(p.get("faction", ""))):
			errs.append("perk '%s': rig perks need a job faction" % id)
	return errs
