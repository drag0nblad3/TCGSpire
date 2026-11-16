extends SceneTree
## Crew diagnostics: plays whole bot runs for one job and prints per act/kind fight stats
## (HP in, HP lost, turns, damage per turn from cards vs daemons, damage blocked) and
## the deck the bot brought to each act boss.
##   godot --headless --path . -s res://tools/diag_crew.gd -- job=chrome [n=200] [profile=veteran] [heat=3] [SAVE_IN env]

const DEFAULT_HEAT := {"new": 0, "experienced": 1, "veteran": 3, "max": 6}

var agg := {}
var boss_decks := {}
var enc_stats := {}
var boss_src := {}
var boss_n := 0


func _initialize() -> void:
	var opts := {"n": "200", "job": "chrome", "profile": "veteran", "heat": ""}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	var db := CardDB.load_from(CardDB.DATA_ROOT)
	# boss3=<encounter>: every act-3 Core is swapped for this one (a probe of one boss vs each crew's deck).
	if opts.has("boss3"):
		for id in db.encounters.keys():
			var en: Dictionary = db.encounters[id]
			if int(en.get("act", 0)) == 3 and str(en.get("kind", "")) == "boss":
				db.encounters[id] = db.encounters[opts["boss3"]]
	var which: String = opts["profile"]
	var profile := Profile.new_player(db)
	if OS.has_environment("SAVE_IN"):
		profile = Profile.from_dict(JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("SAVE_IN"))), db)
	elif which == "experienced":
		profile = ProfileBot.veteran(db, 10)
	elif which == "veteran":
		profile = ProfileBot.veteran(db, 39)
	elif which == "max":
		profile = ProfileBot.maxed(db)
	var heat := int(opts["heat"]) if opts["heat"] != "" else int(DEFAULT_HEAT.get(which, 0))
	RunBot.fight_hook = func(run: RunState, node: Dictionary, c: Combat) -> void: _record(db, run, node, c)
	var n := int(opts["n"])
	var wins := 0
	var stats := {}
	for i in n:
		var r := RunBot.play(db, profile, i, heat, opts["job"], [], stats)
		if r["won"]:
			wins += 1
	print("job %s profile %s heat %d runs %d win %.1f%%" % [opts["job"], which, heat, n, 100.0 * wins / n])
	var ks := agg.keys()
	ks.sort()
	for k in ks:
		var a: Dictionary = agg[k]
		var f := float(a["n"])
		var t := maxf(float(a["turns"]), 1.0)
		print("%-12s n %4d loss %5.1f%%  hp_in %5.1f/%5.1f  hp_lost %5.1f  turns %4.1f  dmg/turn %5.1f (incl. daemons) other %4.1f  taken/turn %5.1f blocked/turn %5.1f  daemon_hits_taken/turn %4.1f" % [
			k, a["n"], 100.0 * a["lost"] / f, a["hp_in"] / f, a["max_hp"] / f, a["hp_lost"] / f, t / f,
			(a["dmg_card"] + a["dmg_daemon"]) / t, a["dmg_other"] / t, a["taken"] / t, a["blocked"] / t, a["dhits"] / t])
	var fac := {}
	for id in stats:
		var d: CardDef = db.card(id)
		if d == null:
			continue
		var f: Dictionary = fac.get(d.faction, {"offered": 0, "picked": 0, "plays": 0})
		fac[d.faction] = f
		for k2 in ["offered", "picked", "plays"]:
			f[k2] += stats[id][k2]
	for f in fac:
		print("  faction %-8s offered %5d picked %4d (%4.1f%%) plays/run %5.1f" % [f, fac[f]["offered"], fac[f]["picked"], 100.0 * fac[f]["picked"] / maxf(fac[f]["offered"], 1.0), fac[f]["plays"] / float(n)])
	if not boss_src.is_empty():
		print("-- act-3 boss fights: damage to you by enemy, damage you dealt by enemy (per fight) --")
		for k in boss_src:
			print("  %-14s took %6.1f  dealt %6.1f" % [k, boss_src[k].get("took", 0.0) / maxf(boss_n, 1), boss_src[k].get("dealt", 0.0) / maxf(boss_n, 1)])
	print("-- per encounter (act>=2 bosses/elites) --")
	var es := enc_stats.keys()
	es.sort_custom(func(x: String, y: String) -> bool: return enc_stats[x]["n"] > enc_stats[y]["n"])
	for e in es:
		var s: Dictionary = enc_stats[e]
		if s["n"] < 8:
			continue
		print("  %-14s n %4d loss %5.1f%%  turns %4.1f  hp_in %5.1f  hp_lost %5.1f" % [e, s["n"], 100.0 * s["lost"] / s["n"], s["turns"] / float(s["n"]), s["hp_in"] / float(s["n"]), s["hp_lost"] / float(s["n"])])
	print("-- deck at each act boss: avg size, type mix, upgraded share, top cards --")
	for act in [1, 2, 3]:
		if not boss_decks.has(act):
			continue
		var b: Dictionary = boss_decks[act]
		var cnt := float(b["n"])
		var types: Dictionary = b["types"]
		var parts: Array[String] = []
		for ty in types:
			parts.append("%s %.1f" % [ty, types[ty] / cnt])
		var cards: Dictionary = b["cards"]
		var ids := cards.keys()
		ids.sort_custom(func(x: String, y: String) -> bool: return cards[x] > cards[y])
		var top: Array[String] = []
		for id in ids.slice(0, 14):
			top.append("%s %.2f" % [id, cards[id] / cnt])
		print("  act %d n %d size %.1f  %s  upgraded %.0f%%  implants %.1f" % [act, b["n"], b["size"] / cnt, " ".join(parts), 100.0 * b["up"] / maxf(b["size"], 1.0), b["imp"] / cnt])
		print("    " + ", ".join(top))
	quit(0)


func _record(db: CardDB, run: RunState, node: Dictionary, c: Combat) -> void:
	var key := "a%d %s" % [run.act, node["type"]]
	var a: Dictionary = agg.get(key, {"n": 0, "lost": 0, "hp_in": 0.0, "max_hp": 0.0, "hp_lost": 0.0, "turns": 0, "dmg_card": 0.0, "dmg_daemon": 0.0, "dmg_other": 0.0, "taken": 0.0, "blocked": 0.0, "dhits": 0.0})
	agg[key] = a
	var hp_in := 0
	var turns := 0
	var first := true
	for e in c.events:
		match e["t"]:
			"turn_start":
				turns += 1
			"damage":
				var tgt := str(e["target"])
				var src := str(e.get("source", ""))
				if tgt.begins_with("e"):
					var amt := float(e["amount"]) + float(e["blocked"])
					if src == "player":
						a["dmg_card"] += amt
					elif src.begins_with("u"):
						a["dmg_daemon"] += amt
					else:
						a["dmg_other"] += amt
				elif tgt == "player":
					if first:
						hp_in = int(e["hp"]) + int(e["amount"])
						first = false
					a["taken"] += float(e["amount"])
					a["blocked"] += float(e["blocked"])
				elif tgt.begins_with("u"):
					a["dhits"] += 1.0
	var won := c.phase == Combat.Phase.WON
	a["n"] += 1
	a["lost"] += 0 if won else 1
	a["turns"] += turns
	# HP before the fight: current HP plus HP lost this fight (from events).
	var lost := 0
	for e in c.events:
		if e["t"] == "damage" and str(e["target"]) == "player":
			lost += int(e["amount"])
		elif e["t"] == "lose_hp" and str(e.get("target", "")) == "player":
			lost += int(e.get("amount", 0))
	var hp_before := c.player.hp + lost
	a["hp_in"] += hp_before
	a["max_hp"] += c.player.max_hp
	a["hp_lost"] += lost
	if node["type"] in ["boss", "elite"] and run.act >= 2:
		var enc := str(node["encounter"])
		var s: Dictionary = enc_stats.get(enc, {"n": 0, "lost": 0, "turns": 0, "hp_in": 0, "hp_lost": 0})
		enc_stats[enc] = s
		s["n"] += 1
		s["lost"] += 0 if won else 1
		s["turns"] += turns
		s["hp_in"] += hp_before
		s["hp_lost"] += lost
	if node["type"] == "boss" and run.act == 3:
		boss_n += 1
		var ids := {}
		for en in c.enemies:
			ids[en.id] = en.def_id
		for e in c.events:
			if e["t"] != "damage":
				continue
			var tgt := str(e["target"])
			var src := str(e.get("source", ""))
			if tgt == "player" and ids.has(src):
				var d: Dictionary = boss_src.get(ids[src], {})
				boss_src[ids[src]] = d
				d["took"] = d.get("took", 0.0) + float(e["amount"])
			elif ids.has(tgt):
				var d2: Dictionary = boss_src.get(ids[tgt], {})
				boss_src[ids[tgt]] = d2
				d2["dealt"] = d2.get("dealt", 0.0) + float(e["amount"]) + float(e["blocked"])
	if node["type"] == "boss":
		var b: Dictionary = boss_decks.get(run.act, {"n": 0, "size": 0, "types": {}, "cards": {}, "up": 0, "imp": 0})
		boss_decks[run.act] = b
		b["n"] += 1
		b["imp"] += run.talismans.size()
		for ci in run.deck:
			var d: CardDef = ci.def
			b["size"] += 1
			if ci.upgraded:
				b["up"] += 1
			b["types"][d.type] = b["types"].get(d.type, 0) + 1
			b["cards"][d.id] = b["cards"].get(d.id, 0) + 1
			b["types"]["f_" + d.faction] = b["types"].get("f_" + d.faction, 0) + 1
