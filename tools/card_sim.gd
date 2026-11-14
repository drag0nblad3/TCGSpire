extends SceneTree
## Per-card balance sim. For every pack card, the run bot plays N seeded runs
## with 2 copies forced into its starter picks (replacing its weakest picks) on
## the card's own crew job (Street cards rotate jobs), paired by seed with the
## same job's baseline runs. A card's score is the average change in floor
## reached (and win %) against those paired baseline runs.
## The baseline runs also log what the bot is offered, picks and plays.
##   godot --headless --path . -s res://tools/card_sim.gd -- [n=60] [profile=new] [heat] [cards=a,b] [shard=0/4] out=dir
##   ... -- merge=dir [top=15]   (reads every shard file in dir and prints the report)
## Use scripts/card_sim.sh, which runs the shards in parallel and merges.

const DEFAULT_HEAT := {"new": 0, "experienced": 1, "veteran": 3, "max": 6}
const BASE := "__base__"


func _initialize() -> void:
	var opts := {"n": "60", "profile": "new", "heat": "", "cards": "", "shard": "0/1", "out": "", "merge": "", "top": "15"}
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
	if opts["merge"] != "":
		_merge(db, opts["merge"], int(opts["top"]))
		quit(0)
		return
	var heat: int = int(opts["heat"]) if opts["heat"] != "" else int(DEFAULT_HEAT.get(opts["profile"], 0))
	var profile := _profile(db, opts["profile"])
	var n := int(opts["n"])
	var sh: PackedStringArray = str(opts["shard"]).split("/")
	var k := int(sh[0])
	var m := int(sh[1])
	var items: Array = [BASE] + _cards(db, opts["cards"])
	var jobs := Jobs.board(db)
	var out := {"n": n, "heat": heat, "profile": opts["profile"], "jobs": jobs, "items": {}}
	for i in items.size():
		if i % m != k:
			continue
		var id: String = items[i]
		out["items"][id] = _base(db, profile, n, heat, jobs) if id == BASE else _forced(db, profile, n, heat, jobs, id)
	var f := FileAccess.open("%s/shard_%d.json" % [opts["out"], k], FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	quit(0)


func _profile(db: CardDB, which: String) -> Profile:
	match which:
		"experienced":
			return ProfileBot.veteran(db, 10)
		"veteran":
			return ProfileBot.veteran(db, 39)
		"max":
			return ProfileBot.maxed(db)
	return Profile.new_player(db)


## Every card a pack can hold (no starters, curses).
func _cards(db: CardDB, filter: String) -> Array:
	var out: Array = []
	for id in db.cards:
		var c := db.card(id)
		if c.rarity in ["starter", "curse"]:
			continue
		if filter != "" and id not in filter.split(","):
			continue
		out.append(id)
	out.sort()
	return out


func _job_for(db: CardDB, jobs: Array, id: String, i: int) -> String:
	var f := db.card(id).faction
	return f if f in jobs else jobs[i % jobs.size()]


func _base(db: CardDB, profile: Profile, n: int, heat: int, jobs: Array) -> Dictionary:
	var stats := {}
	var by_job := {}
	var decks := {}  # id -> [runs ending with it in the deck, of those won, floors]
	for job in jobs:
		var floors: Array = []
		var wins: Array = []
		for i in n:
			var r := RunBot.play(db, profile, i, heat, job, [], stats)
			floors.append(r["floor"])
			wins.append(1 if r["won"] else 0)
			var seen := {}
			for card in r["run"].deck:
				seen[card.def.id] = true
			for id in seen:
				var d: Array = decks.get(id, [0, 0, 0])
				d[0] += 1
				d[1] += 1 if r["won"] else 0
				d[2] += r["floor"]
				decks[id] = d
		by_job[job] = {"floors": floors, "wins": wins}
	return {"by_job": by_job, "stats": stats, "decks": decks}


func _forced(db: CardDB, profile: Profile, n: int, heat: int, jobs: Array, id: String) -> Dictionary:
	var floors: Array = []
	var wins: Array = []
	var job_of: Array = []
	var stats := {}
	# Lend the profile 2 copies of the card for these runs only.
	var own := profile.collection
	profile.collection = Collection.from_dict(own.to_dict())
	profile.collection.add(id, maxi(2 - own.count(id), 0))
	for i in n:
		var job := _job_for(db, jobs, id, i)
		var r := RunBot.play(db, profile, i, heat, job, [id, id], stats)
		floors.append(r["floor"])
		wins.append(1 if r["won"] else 0)
		job_of.append(job)
	profile.collection = own
	var s: Dictionary = stats.get(id, {"plays": 0, "dmg": 0, "ward": 0})
	return {"floors": floors, "wins": wins, "jobs": job_of, "plays": s["plays"], "dmg": s["dmg"], "ward": s["ward"]}


func _merge(db: CardDB, dir: String, top: int) -> void:
	var items := {}
	var meta := {}
	for fname in DirAccess.get_files_at(dir):
		if not fname.begins_with("shard_"):
			continue
		var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/%s" % [dir, fname]))
		meta = d
		items.merge(d["items"])
	if not items.has(BASE):
		print("no baseline shard in ", dir)
		return
	var base: Dictionary = items[BASE]
	var n := int(meta["n"])
	var bj: Dictionary = base["by_job"]
	var tot_f := 0.0
	var tot_w := 0.0
	for job in bj:
		for x in bj[job]["floors"]:
			tot_f += float(x)
		for x in bj[job]["wins"]:
			tot_w += float(x)
	var runs := float(n * bj.size())
	print("[%s heat %d] %d runs per card, paired with %d baseline runs: avg floor %.1f, win %.1f%%" % [
		meta["profile"], int(meta["heat"]), n, int(runs), tot_f / runs, 100.0 * tot_w / runs])
	var rows: Array = []
	var obs: Dictionary = base["stats"]
	var decks: Dictionary = base["decks"]
	for id in items:
		if id == BASE:
			continue
		var it: Dictionary = items[id]
		var diffs: Array = []
		var dw := 0.0
		for i in it["floors"].size():
			var b: Dictionary = bj[it["jobs"][i]]
			diffs.append(float(it["floors"][i]) - float(b["floors"][i]))
			dw += float(it["wins"][i]) - float(b["wins"][i])
		var mean := 0.0
		for x in diffs:
			mean += x
		mean /= diffs.size()
		var var_sum := 0.0
		for x in diffs:
			var_sum += (x - mean) * (x - mean)
		var se := sqrt(var_sum / maxf(diffs.size() - 1, 1) / diffs.size())
		var o: Dictionary = obs.get(id, {"offered": 0, "picked": 0})
		var c := db.card(id)
		var plays := float(it["plays"])
		rows.append({"id": id, "c": c, "d": mean, "se": se, "dw": 100.0 * dw / diffs.size(),
			"ppr": plays / diffs.size(), "dpp": float(it["dmg"]) / maxf(plays, 1), "wpp": float(it["ward"]) / maxf(plays, 1),
			"pick": "%d/%d" % [o["picked"], o["offered"]], "deck": int(decks.get(id, [0])[0])})
	# Each crew's cards replace that job's weakest picks, so compare a card with
	# its own crew: rel = d_floor minus the crew's median d_floor.
	var by_crew := {}
	for r in rows:
		var crew: String = r["c"].faction
		if not by_crew.has(crew):
			by_crew[crew] = []
		by_crew[crew].append(r["d"])
	var med := {}
	var crew_parts: Array[String] = []
	for crew in by_crew:
		var v: Array = by_crew[crew]
		v.sort()
		med[crew] = v[v.size() / 2]
		crew_parts.append("%s %+.2f" % [crew, med[crew]])
	print("crew median d_floor: ", ", ".join(crew_parts))
	for r in rows:
		r["rel"] = r["d"] - med[r["c"].faction]
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["rel"] > b["rel"])
	print("columns: rel (d_floor vs crew median) d_floor (+-se) d_win%  plays/run  dmg/play fw/play  bot picks/offers  baseline runs ending with it")
	print("-- strongest")
	for r in rows.slice(0, top):
		print(_row(r))
	print("-- weakest")
	for r in rows.slice(maxi(rows.size() - top, 0)):
		print(_row(r))
	print("-- groups (avg rel)")
	for group in ["rarity", "cost", "type"]:
		var acc := {}
		for r in rows:
			var c: CardDef = r["c"]
			var key := str(c.rarity if group == "rarity" else (c.cost if group == "cost" else c.type))
			var a: Array = acc.get(key, [0.0, 0])
			a[0] += r["rel"]
			a[1] += 1
			acc[key] = a
		var parts: Array[String] = []
		for key in acc:
			parts.append("%s %+.2f (%d)" % [key, acc[key][0] / acc[key][1], acc[key][1]])
		print("  %s: %s" % [group, ", ".join(parts)])
	var f := FileAccess.open("%s/report.tsv" % dir, FileAccess.WRITE)
	f.store_line("id\tfaction\trarity\ttype\tcost\trel\td_floor\tse\td_win\tplays_per_run\tdmg_per_play\tfw_per_play\tbot_picks\tbase_deck_runs")
	for r in rows:
		var c: CardDef = r["c"]
		f.store_line("%s\t%s\t%s\t%s\t%d\t%.2f\t%.2f\t%.2f\t%.1f\t%.2f\t%.1f\t%.1f\t%s\t%d" % [r["id"], c.faction, c.rarity, c.type, c.cost, r["rel"], r["d"], r["se"], r["dw"], r["ppr"], r["dpp"], r["wpp"], r["pick"], r["deck"]])
	f.close()
	print("full table: %s/report.tsv" % dir)


func _row(r: Dictionary) -> String:
	var c: CardDef = r["c"]
	return "%-16s %-7s %-8s %-6s %d  %+5.2f  %+5.2f (+-%.2f)  %+5.1f%%  %4.1f  %4.1f %4.1f  %s  %d" % [
		r["id"], c.faction, c.rarity, c.type, c.cost, r["rel"], r["d"], r["se"], r["dw"], r["ppr"], r["dpp"], r["wpp"], r["pick"], r["deck"]]
