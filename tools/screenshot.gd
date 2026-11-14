extends SceneTree
## Boots the real main scene, jumps to a screen, optionally auto-plays a few
## cards, and saves a PNG. Lets you review UI from the CLI without an emulator.
##   scripts/shot.sh [screen=hub|map|combat|reward|rest|shop|event|collection|picker|pack|end]
##                   [out=/tmp/shot.png] [frames=30] [plays=2] [seed=1] [theme=archive] [end_turn=1] [give=sparring_dummy,drone_swarm]
## Under --headless it still runs (smoke test for script errors) but writes no image.

const SCREENS := ["hub", "map", "combat", "reward", "rest", "shop", "event", "collection", "picker", "pack", "pack_open", "pack_shelf", "pack_premium", "pack_crew", "end", "inspect", "rules", "jobs", "rig", "perk", "tinker", "crew", "firmware", "recompile", "menu", "settings", "resume", "records", "exploits", "ice", "deep", "daily", "signal_result", "weekly", "weekly_map", "login", "tutorial", "coach", "map_walls", "map_jump", "foil"]


func _initialize() -> void:
	var opts := {"out": "user://shot.png", "frames": "30", "plays": "0", "screen": "combat", "seed": "1", "theme": "", "end_turn": "0", "give": ""}
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
		_go(main, scr, int(opts["seed"]), str(opts.get("card", "flare_volley")))
		for i in 3:
			await process_frame
		if scr == "combat" and opts["give"] != "":
			# give=id,id: hand-place those programs and run them (e.g. to show daemons).
			var gs = main.get("_screen")
			var gc: Combat = gs.combat
			for id in str(opts["give"]).split(","):
				var inst: CardInstance = main.db.instance(id)
				if inst != null:
					gc.hand.append(inst)
					gc.energy += inst.cost()
					gs._on_card_pressed(null, gc.hand.size() - 1)
					await _idle(gs)
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


## A map with a vault low enough to show on the first screen.
func _vault_map(db: CardDB, seed_in: int) -> RunMap:
	for s in range(seed_in, seed_in + 200):
		var m := RunMap.generate(db, GameRng.new(s))
		for n in m.nodes:
			if n["type"] == "vault" and int(n["row"]) <= 7:
				return m
	return RunMap.generate(db, GameRng.new(seed_in))


## Waits for combat animations to finish (capped at ~10s).
func _idle(cs) -> void:
	for i in 600:
		await process_frame
		if not cs.is_busy():
			return


func _go(main: Control, scr: String, seed_in: int, inspect_card: String = "flare_volley") -> void:
	var db: CardDB = main.db
	if scr not in ["hub", "collection", "picker", "pack", "pack_open", "pack_shelf", "pack_premium", "pack_crew", "inspect", "rules", "jobs", "rig", "firmware", "resume", "records", "exploits", "ice", "tutorial", "coach", "foil", "weekly", "weekly_map", "login"]:
		var p: Profile = main.profile
		main.run = RunState.start(db, p, RunState.default_picks(db, p), seed_in)
		main.run.add_talisman("oak_token")
		main.run.add_talisman("ember_charm")
	match scr:
		"hub":
			main.show_hub()
		"tutorial":
			main.start_tutorial()
		"coach":
			main._start_tutorial_fight()
		"inspect":
			main.show_hub()
			CardInspector.show_for(main, db.instance(inspect_card))
		"rules":
			for n in main.get_tree().root.get_children():
				if n is CardInspector:
					n.queue_free()
			main.show_hub()
			Rules.open(main)
		"collection":
			# A couple of NEW cards and some extra copies, so ribbons and pips show.
			for id in ["spore_burst", "drone_swarm", "rivet_gun"]:
				if main.db.card(id) != null:
					main.profile.collection.add(id, 1 if not main.profile.collection.owns(id) else 2)
					main.profile.unseen[id] = true
			for id in ["sprout", "thornhide"]:
				if main.db.card(id) != null:
					main.profile.collection.add(id, 3)
			main.show_hub()
			main.get("_screen").collection_pressed.emit()
		"foil":
			# Every other owned card is a glitch foil, so foils sit next to plain cards.
			var k := 0
			for id in main.profile.collection.counts.keys():
				if k % 2 == 0:
					main.profile.collection.foils[id] = 1
				k += 1
			main.show_hub()
			main.get("_screen").collection_pressed.emit()
		"picker":
			main._show_picker(0, "ember")
		"jobs":
			main.profile.max_heat = 6
			main._show_jobs(6)
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
		"pack_shelf":
			# One of every kind on the shelf (premium, the seven crews, normal).
			for k in Packs.kinds():
				main.profile.add_packs(k, 1)
			main.profile.add_packs(Packs.crew_kind("ember"), 2)
			main._show_pack_shelf()
		"pack_premium":
			main.profile.add_packs(Packs.PREMIUM, 1)
			main.reveal_packs_now = true
			main._show_pack(Packs.PREMIUM)
		"pack_crew":
			main.profile.add_packs(Packs.crew_kind("bloom"), 2)
			main.reveal_packs_now = true
			main._show_pack(Packs.crew_kind("bloom"))
		"pack_open":
			# Four copies of every common (2 deck + 2 extras), so pulls show pips and unlocks.
			for id in main.db.ids_where(func(c: CardDef) -> bool: return c.rarity == "common"):
				main.profile.collection.add(id, maxi(0, 4 - main.profile.collection.count(id)))
			main.reveal_packs_now = true
			main._show_pack()
		"map":
			main.show_map()
		"map_walls":
			# No jump upgrade yet: walls, ghosted cut links and a sealed vault.
			main.run.map = _vault_map(main.db, seed_in)
			main.show_map()
		"map_jump":
			# Packet Hop + Ghost Routing (3 jumps, 1 spent): standing below a vault.
			main.run.map = _vault_map(main.db, seed_in)
			main.run.perks.append("packet_hop")
			main.run.rig["ghost_routing"] = 1
			main.run.jumps_used = 1
			var m: RunMap = main.run.map
			for n in m.nodes:
				if n["type"] != "vault":
					continue
				for src in m.rows[int(n["row"]) - 1]:
					if m.node(src)["type"] != "vault" and n["id"] in m.jump_targets(src):
						var chain: Array = [src]
						while int(m.node(chain[0])["row"]) > 0:
							var below: int = chain[0]
							for s2 in m.rows[int(m.node(below)["row"]) - 1]:
								if below in m.node(s2)["next"]:
									chain.push_front(s2)
									break
						main.run.path = chain
						main.run.node_id = src
						main.run.floor_num = chain.size()
						break
				if main.run.node_id >= 0:
					break
			main.show_map()
		"menu":
			main._start_combat({"type": "fight", "encounter": "wisp_court"})
			main._resume = {"screen": "node"}
			main._open_menu()
		"settings":
			main.show_map()
			main._open_settings()
		"records":
			main.profile.binders = {"ember:common": true}
			main.profile.collection.foils = {"kindle": 1, "shriek": 1}
			main._show(RecordsScreen.new().setup(db, main.profile, "binders"))
		"exploits":
			main.profile.stats["wins"] = 1
			main.profile.stats["best_max_burn"] = 34
			Records.check_exploits(db, main.profile)
			main._show(RecordsScreen.new().setup(db, main.profile, "exploits"))
		"ice":
			main.profile.ice = {"cinder_mite": {"seen": 7, "crashed": 15, "lost": 1}, "hollow_wisp": {"seen": 2, "crashed": 3, "lost": 0},
				"shard_golem": {"seen": 3, "crashed": 2, "lost": 1}, "hollow_monarch": {"seen": 4, "crashed": 2, "lost": 2}, "ember_imp": {"seen": 1, "crashed": 1, "lost": 0}}
			main._show(RecordsScreen.new().setup(db, main.profile, "ice"))
		"deep":
			main.run.boss_won = true
			main.run.deep_ok = true
			main.run.deep_pending = true
			main.show_map()
		"daily":
			main._start_daily()
		"weekly":
			main._show_weekly()
		"weekly_map":
			var w := Weekly.challenge(db, Weekly.this_week())
			main.run = Weekly.begin(db, main.profile, w, RunState.default_picks(db, main.profile, w["job"], w["targets"]))
			main.show_map()
		"login":
			# Three days into the track, today's bonus already claimed.
			main.profile.login = {"last": "2000-01-01", "day": 2}
			main._claim_login()
		"resume":
			main._show(HubScreen.new().setup(db, main.profile, "Layer 2 · Node 17 · HP 40/60"))
		"combat":
			main.run.enter(main.run.available_nodes()[0])  # floor 1: shows the soft-entry hint
			main._start_combat({"type": "fight", "encounter": "wisp_court"})
		"crew":
			main.run = RunState.start(db, main.profile, RunState.default_picks(db, main.profile, "noise"), seed_in, 0, "noise")
			main._start_combat({"type": "boss", "encounter": "chrome_a1b"})
		"recompile":
			main._show_rest()
			main.add_child(DeckOverlay.new().setup("Choose a program to recompile", main.run.deck, "Cancel", func(_i: int) -> void: pass, true, true))
		"firmware":
			main.profile.collection.add("drone_swarm", 1)
			main.profile.firmware = {"drone_swarm": 2}
			main.profile.firmware_mods = {"drone_swarm": "swarm_hook"}
			main.profile.mastery["drone_swarm"] = 35
			main.profile.rep = {"chrome": 120}
			main.show_hub()
			main.get("_screen").collection_pressed.emit()
			main.get("_screen")._show_detail("drone_swarm")
		"reward":
			main._show_reward(["+15 gold", "Found Bone Dice"], ["bone_dice"], main.run.reward_choices("elite"))
		"signal_result":
			# A Signal that paid a random mod, an upgrade, an implant and a subroutine, with the header info open.
			main.run.clauses = db.contracts.keys().slice(0, 2)
			main.run.add_perk("scavenger")
			var before: Dictionary = main._run_snapshot()
			var lines: Array = [RunOutcomes.apply(main.run, {"op": "mod", "amount": 1}), RunOutcomes.apply(main.run, {"op": "upgrade", "amount": 1})]
			main.run.add_talisman("bone_dice")
			main.run.add_perk("nanite_mesh")
			main._show_message("Black-market bundle", lines, main._run_gains(before))
			var header: RunHeader = main._screen.find_children("*", "RunHeader", true, false)[0]
			header.toggle_info("perks", RunHeader.perk_text(main.run))
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
