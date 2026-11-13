extends SceneTree
## Balance sim: the bot plays N seeded combats and prints one summary line per
## encounter. Use it to check a balance change instead of playtesting by hand.
##   godot --headless --path . -s res://tools/sim.gd -- [n=200] [deck=a,b,c] [enc=mites,golem]
##   ... -- mode=run [n=100] [heat=0] [job=ember|all]   (whole runs: win rate, floor reached, top killers;
##          job=all rotates through every faction job; profile=new|experienced|veteran|max picks the save:
##          experienced = after 10 bot runs spending what they earned, veteran = after 39, max = every upgrade;
##          acts=1 adds per-act lines: share of runs reaching / dying in the act, turns per fight by kind)
## Default deck = base deck + default starter picks.


func _initialize() -> void:
	var opts := {"n": "", "deck": "", "enc": "", "mode": "fight", "heat": "0", "job": "", "profile": "new", "acts": "0"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	var db := CardDB.load_from(CardDB.DATA_ROOT)
	if not db.errors.is_empty():
		for e in db.errors:
			print("DATA ERROR ", e)
		quit(1)
		return
	if opts["mode"] == "run":
		_sim_runs(db, int(opts["n"]) if opts["n"] != "" else 100, int(opts["heat"]), opts["job"], opts["profile"], opts["acts"] == "1")
		quit(0)
		return
	var deck_ids: Array = []
	if opts["deck"] != "":
		deck_ids = Array(opts["deck"].split(","))
	else:
		deck_ids = db.balance["base_deck"] + RunState.default_picks(db, Profile.new_player(db))
	var encs: Array = Array(opts["enc"].split(",")) if opts["enc"] != "" else db.encounters.keys()
	var n := int(opts["n"]) if opts["n"] != "" else 200
	print("deck(%d): %s" % [deck_ids.size(), ",".join(deck_ids)])
	for enc in encs:
		var wins := 0
		var turns := 0
		var hp_left := 0
		var timeouts := 0
		for i in n:
			var c := Combat.create(db, db.make_deck(deck_ids), enc, GameRng.new(i))
			var r := Bot.run_combat(c)
			if r["won"]:
				wins += 1
				hp_left += r["hp"]
			turns += r["turns"]
			if r["timeout"]:
				timeouts += 1
		print("%-12s win %5.1f%%  turns %4.1f  hp_left(won) %4.1f  timeouts %d" % [
			enc, 100.0 * wins / n, float(turns) / n, float(hp_left) / maxi(wins, 1), timeouts])
	quit(0)


func _sim_runs(db: CardDB, n: int, heat: int, job: String = "", which: String = "new", acts: bool = false) -> void:
	var jobs := Jobs.board(db)
	var profile := Profile.new_player(db)
	if which == "experienced":
		profile = ProfileBot.veteran(db, 10)
	elif which == "veteran":
		profile = ProfileBot.veteran(db, 39)
	elif which == "max":
		profile = ProfileBot.maxed(db)
	if which != "new":
		print("profile %s: %s" % [which, ProfileBot.summary(db, profile)])
	var wins := 0
	var floors := 0
	var stuck := 0
	var killers := {}
	var act1 := 0
	var act2 := 0
	var per_act := {}  # act -> {"reached", "died", kind -> [turns...]}
	for i in n:
		var r := RunBot.play(db, profile, i, heat, jobs[i % jobs.size()] if job == "all" else job)
		for f in r["fights"]:
			var a: Dictionary = per_act.get(f["act"], {"reached": 0, "died": 0})
			per_act[f["act"]] = a
			if not a.has(f["kind"]):
				a[f["kind"]] = []
			a[f["kind"]].append(int(f["turns"]))
			if not f["won"]:
				a["died"] += 1
		for k in range(1, r["run"].act + 1):
			var a2: Dictionary = per_act.get(k, {"reached": 0, "died": 0})
			per_act[k] = a2
			a2["reached"] += 1
		if r["run"].acts_cleared >= 1:
			act1 += 1
		if r["run"].acts_cleared >= 2:
			act2 += 1
		if r["won"]:
			wins += 1
		floors += r["floor"]
		if r["stuck"]:
			stuck += 1
		if r["died_to"] != "":
			killers[r["died_to"]] = int(killers.get(r["died_to"], 0)) + 1
	var top := killers.keys()
	top.sort_custom(func(a: String, b: String) -> bool: return killers[a] > killers[b])
	var parts: Array[String] = []
	for k in top.slice(0, 5):
		parts.append("%s %d" % [k, killers[k]])
	print("[%s] runs %d heat %d  act1 %5.1f%%  act2 %5.1f%%  win %5.1f%%  avg floor %4.1f  stuck %d  killers: %s" % [which, n, heat, 100.0 * act1 / n, 100.0 * act2 / n, 100.0 * wins / n, float(floors) / n, stuck, ", ".join(parts)])
	if not acts:
		return
	var ks := per_act.keys()
	ks.sort()
	for k in ks:
		var a: Dictionary = per_act[k]
		var line := "  act %d  reached %5.1f%%  died here %5.1f%% of runs (%5.1f%% of those reaching)" % [
			k, 100.0 * a["reached"] / n, 100.0 * a["died"] / n, 100.0 * a["died"] / maxi(a["reached"], 1)]
		for kind in ["fight", "elite", "boss"]:
			var t: Array = a.get(kind, [])
			if t.is_empty():
				continue
			t.sort()
			var sum := 0
			for x in t:
				sum += int(x)
			line += "  %s %d: avg %.1f med %d p90 %d" % [kind, t.size(), float(sum) / t.size(), t[t.size() / 2], t[mini(t.size() - 1, int(t.size() * 0.9))]]
		print(line)
