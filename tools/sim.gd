extends SceneTree
## Balance sim: the bot plays N seeded combats and prints one summary line per
## encounter. Use it to check a balance change instead of playtesting by hand.
##   godot --headless --path . -s res://tools/sim.gd -- [n=200] [deck=a,b,c] [enc=mites,golem]
## Default deck = base deck + default starter picks.


func _initialize() -> void:
	var opts := {"n": "200", "deck": "", "enc": ""}
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
	var deck_ids: Array = []
	if opts["deck"] != "":
		deck_ids = Array(opts["deck"].split(","))
	else:
		deck_ids = db.balance["base_deck"] + RunState.default_picks(db, Profile.new_player(db))
	var encs: Array = Array(opts["enc"].split(",")) if opts["enc"] != "" else db.encounters.keys()
	var n := int(opts["n"])
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
