class_name Weekly
extends RefCounted
## Weekly challenge: one job per week (Monday to Sunday, device date), the same for
## everyone, at balance.weekly.heat with balance.weekly.mods rule modifiers rolled from
## data/weekly.json. You load programs from your own library, but firmware and rig
## upgrades stay off: every card plays at base level and no bought rig rank applies.
## Tries are unlimited; the first clear each week pays balance.weekly.packs.
##
## A modifier is perk-shaped: "mods" (Perks.MODS keys, added to RunState.perk_mod),
## "heat" (HEAT_KEYS, stacked on top of the run's heat), "triggers" (combat triggers,
## like a subroutine), "pickup" (RunOutcomes at run start) and a hand-written "text".
##
## Profile.weekly = {"week": monday, "tries": n, "cleared": bool, "best": score, "clears": lifetime}.

const HEAT_KEYS := ["enemy_hp_pct", "enemy_dmg_pct", "enemy_might", "rest_heal_pct", "max_hp"]
const DAY := 86400


## The Monday that starts the week holding `date` ("2026-11-13" -> "2026-11-09").
static func week_of(date: String) -> String:
	var unix := Time.get_unix_time_from_datetime_string(date + "T12:00:00")
	return Time.get_date_string_from_unix_time(unix - _weekday(unix) * DAY)


## Days until the next challenge opens (1 on Sunday, 7 on Monday).
static func days_left(date: String) -> int:
	return 7 - _weekday(Time.get_unix_time_from_datetime_string(date + "T12:00:00"))


## 0 = Monday ... 6 = Sunday.
static func _weekday(unix: int) -> int:
	return (int(Time.get_datetime_dict_from_unix_time(unix)["weekday"]) + 6) % 7


static func this_week() -> String:
	return week_of(Records.today())


## Everyone gets the same challenge for a week: {"week", "seed", "job", "targets", "heat", "mods"}.
static func challenge(db: CardDB, week: String) -> Dictionary:
	var seed_in := absi(hash("weekly:" + week)) % 2000000000
	var rng := GameRng.new(seed_in)
	var board := Jobs.board(db)
	var job: String = board[rng.fork("job").range_i(0, board.size() - 1)]
	var cfg: Dictionary = db.balance.get("weekly", {})
	var heat := int(cfg.get("heat", 2))
	var ids: Array = db.weekly.keys()
	ids.sort()
	rng.fork("mods").shuffle(ids)
	return {"week": week, "seed": seed_in, "job": job, "heat": heat,
		"mods": ids.slice(0, mini(int(cfg.get("mods", 3)), ids.size())),
		"targets": Jobs.targets(db, job, Jobs.extra_targets(db, heat), rng.fork("targets"))}


## This week's record, or a fresh one when the stored week has passed.
static func state(p: Profile, week: String) -> Dictionary:
	if str(p.weekly.get("week", "")) == week:
		return p.weekly
	return {"week": week, "tries": 0, "cleared": false, "best": 0, "clears": int(p.weekly.get("clears", 0))}


## Starts a try: counts it on the profile. Returns the run (picks are the player's own).
static func begin(db: CardDB, p: Profile, w: Dictionary, picks: Array, seed_in: int = -1) -> RunState:
	var st := state(p, w["week"])
	st["tries"] = int(st.get("tries", 0)) + 1
	p.weekly = st
	var run := RunState.start(db, p, picks, int(w["seed"]) if seed_in < 0 else seed_in, int(w["heat"]), w["job"], w["targets"], w)
	run.clauses = []
	return run


## Folds a finished weekly run into the profile: best score, first-clear pack.
static func finish_run(db: CardDB, p: Profile, run: RunState) -> Array:
	var lines: Array = []
	if run.weekly == "":
		return lines
	if str(p.weekly.get("week", "")) != run.weekly:
		lines.append("That week's challenge has closed, so this run isn't scored.")
		return lines
	var s := Records.score(run)
	p.weekly["best"] = maxi(int(p.weekly.get("best", 0)), s)
	lines.append("Weekly challenge score: %d (best this week %d)" % [s, int(p.weekly["best"])])
	if run.boss_won and not bool(p.weekly.get("cleared", false)):
		p.weekly["cleared"] = true
		p.weekly["clears"] = int(p.weekly.get("clears", 0)) + 1
		var packs := int(db.balance.get("weekly", {}).get("packs", 0))
		p.add_packs(Packs.NORMAL, packs)
		if packs > 0:
			lines.append("Weekly challenge cleared: +%d %s" % [packs, "pack" if packs == 1 else "packs"])
	return lines


## Modifier dicts for a list of ids (unknown ids are skipped).
static func mods_of(db: CardDB, ids: Array) -> Array:
	return ids.filter(func(id: String) -> bool: return db.weekly.has(id)).map(func(id: String) -> Dictionary: return db.weekly[id])


## "Overclocked Grid: +1 RAM each turn, but you draw 1 fewer program."
static func describe(db: CardDB, id: String) -> String:
	var m: Dictionary = db.weekly.get(id, {})
	return "%s: %s" % [m.get("name", id), m.get("text", "")]


static func validate(m: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var where := "weekly modifier '%s'" % m.get("id", "")
	if str(m.get("name", "")) == "" or str(m.get("text", "")) == "":
		errs.append("%s: needs a name and text" % where)
	for k in m:
		if k not in ["id", "name", "text", "mods", "heat", "triggers", "pickup"]:
			errs.append("%s: unknown key '%s'" % [where, k])
	for k in m.get("mods", {}):
		if not Perks.MODS.has(k):
			errs.append("%s: unknown mod '%s'" % [where, k])
	for k in m.get("heat", {}):
		if k not in HEAT_KEYS:
			errs.append("%s: unknown heat key '%s'" % [where, k])
	for trig in m.get("triggers", []):
		if trig.get("on", "") not in Talismans.TRIGGERS:
			errs.append("%s: bad trigger '%s'" % [where, trig.get("on", "")])
		for e in trig.get("effects", []):
			errs.append_array(Effects.validate(e, where))
	for o in m.get("pickup", []):
		errs.append_array(RunOutcomes.validate(o, where))
	return errs
