extends SceneTree
## Boots the real main scene, jumps to a screen, optionally auto-plays a few
## cards, and saves a PNG. Lets you review UI from the CLI without an emulator.
##   scripts/shot.sh [screen=hub|map|combat|reward|rest|shop|event|collection|picker|pack|end]
##                   [out=/tmp/shot.png] [frames=30] [plays=2] [seed=1] [theme=archive] [end_turn=1]
## Under --headless it still runs (smoke test for script errors) but writes no image.

const SCREENS := ["hub", "map", "combat", "reward", "rest", "shop", "event", "collection", "picker", "pack", "end", "inspect", "rules", "jobs", "rig", "perk", "tinker"]


func _initialize() -> void:
	var opts := {"out": "user://shot.png", "frames": "30", "plays": "0", "screen": "combat", "seed": "1", "theme": "", "end_turn": "0"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	var main: Control = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	# Use a throwaway profile so screenshots never touch the real save.
	main.persist = false
	main.profile = Profile.new_player(main.db)
	main.profile.packs_unopened = 2
	main.profile.collection.dust = 120
	if opts["theme"] != "":
		main.apply_theme(opts["theme"])
	var screens: Array = SCREENS if opts["screen"] == "all" else [opts["screen"]]
	for scr in screens:
		_go(main, scr, int(opts["seed"]))
		for i in 3:
			await process_frame
		if scr == "combat":
			for p in int(opts["plays"]):
				var cs = main.get("_screen")
				var c: Combat = cs.combat
				for i in c.hand.size():
					if c.can_play(i):
						cs._on_card_pressed(null, i)
						if cs._selected >= 0:
							cs._on_enemy_pressed(null, c.enemies.find(c.living(c.enemies)[0]))
						break
				await _idle(cs)
			if opts["end_turn"] == "1":
				main.get("_screen")._on_end_turn()
				await _idle(main.get("_screen"))
		for i in int(opts["frames"]):
			await process_frame
		if DisplayServer.get_name() != "headless":
			var out: String = opts["out"] if screens.size() == 1 else opts["out"].replace(".png", "_%s.png" % scr)
			root.get_texture().get_image().save_png(out)
			print("saved ", out)
		else:
			print("smoke ok: ", scr)
	quit(0)


## Waits for combat animations to finish (capped at ~10s).
func _idle(cs) -> void:
	for i in 600:
		await process_frame
		if not cs.is_busy():
			return


func _go(main: Control, scr: String, seed_in: int) -> void:
	var db: CardDB = main.db
	if scr not in ["hub", "collection", "picker", "pack", "inspect", "rules", "jobs", "rig"]:
		var p: Profile = main.profile
		main.run = RunState.start(db, p, RunState.default_picks(db, p), seed_in)
		main.run.add_talisman("oak_token")
		main.run.add_talisman("ember_charm")
	match scr:
		"hub":
			main.show_hub()
		"inspect":
			main.show_hub()
			CardInspector.show_for(main, db.instance("flare_volley"))
		"rules":
			for n in main.get_tree().root.get_children():
				if n is CardInspector:
					n.queue_free()
			main.show_hub()
			Rules.open(main)
		"collection":
			main.show_hub()
			main.get("_screen").collection_pressed.emit()
		"picker":
			main._show_picker(0, "ember")
		"jobs":
			main._show_jobs(0)
		"rig":
			main.profile.rep = {"ember": 60, "tide": 25, "bloom": 90, "void": 10}
			main.profile.rig = {"chassis": 1}
			main.show_hub()
			main.get("_screen").rig_pressed.emit()
		"perk":
			main.run.add_perk("nanite_mesh")
			main.run.install_mod(main.run.mod_targets("overclocked")[0], "overclocked")
			main._show_perk_pick(main.run.perk_choices(3, GameRng.new(seed_in)))
		"tinker":
			main.run.install_mod(main.run.mod_targets("hardened_payload")[0], "hardened_payload")
			main._pick_mod_target("cached", func(_i: int) -> void: pass)
		"pack":
			main._show_pack()
		"map":
			main.show_map()
		"combat":
			main._start_combat({"type": "fight", "encounter": "wisp_court"})
		"reward":
			main._show_reward(["+15 gold", "Found Bone Dice"], ["bone_dice"], main.run.reward_choices("elite"))
		"rest":
			main._show_rest()
		"shop":
			main.run.gold = 200
			main._show_shop(main.run.make_shop())
		"event":
			main._show_event(db.events["wandering_merchant"])
		"end":
			main.run.floor_num = 9
			main.run.combats_won = 6
			main.run.over = true
			main._end_run()
