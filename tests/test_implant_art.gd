extends TestCase

func test_every_implant_has_unique_art_and_motion() -> void:
	var manifest := ImplantArt.regions()
	eq(manifest.size(), db.talismans.size())
	var used := {}
	for id in db.talismans:
		check(manifest.has(id), "missing " + id)
		var entry: Dictionary = manifest.get(id, {})
		var key := str(entry.get("atlas")) + str(entry.get("region"))
		check(not used.has(key), "duplicate art " + id)
		used[key] = true
		check(ImplantArt.texture_for(id) != null, "missing texture " + id)
		check(ImplantArt.texture_for(id, true) != null, "missing activation art " + id)
		check(entry.get("motion") in ["spark", "slide", "pulse", "ring", "vent", "scan", "signal"], "motion " + id)

func test_progress_is_emitted_only_for_qualifying_cards() -> void:
	var c := Combat.create(db, db.make_deck(["jab"]), "mites", GameRng.new(10), -1, {"talismans": ["flint_shard"]})
	c.start()
	var tracker := ImplantTracker.new()
	var before := c.events.size()
	Talismans.fire(c, "card_played", {"card": db.instance("brace")})
	eq(c.events.size(), before, "nonattack does not charge Spark Plug")
	for i in 2:
		Talismans.fire(c, "card_played", {"card": db.instance("jab")})
	for event in c.events.slice(before):
		tracker.consume(event)
	eq(tracker.badge(db.talismans["flint_shard"]), "2/3")
	# Resolve another activation without presenting it: UI must still show 2/3.
	before = c.events.size()
	Talismans.fire(c, "card_played", {"card": db.instance("jab")})
	eq(tracker.badge(db.talismans["flint_shard"]), "2/3")
	for event in c.events.slice(before):
		tracker.consume(event)
	eq(tracker.badge(db.talismans["flint_shard"]), "0/3")
	eq(tracker.counts.get("flint_shard", 0), 1)

func test_tracker_startup_and_daemon_gates() -> void:
	var tracker := ImplantTracker.new()
	eq(tracker.badge(db.talismans["oak_token"]), "READY")
	tracker.consume({"t": "talisman", "id": "oak_token"})
	eq(tracker.badge(db.talismans["oak_token"]), "USED")
	eq(tracker.badge(db.talismans["pressure_valve"]), "OFF")
	tracker.consume({"t": "summon", "target": "unit_1"})
	tracker.consume({"t": "summon", "target": "unit_2"})
	eq(tracker.badge(db.talismans["pressure_valve"]), "ON")
	tracker.consume({"t": "expire", "target": "unit_1"})
	eq(tracker.badge(db.talismans["pressure_valve"]), "ON")
	tracker.consume({"t": "death", "target": "unit_2"})
	eq(tracker.badge(db.talismans["pressure_valve"]), "OFF")

func test_current_thresholds_and_passives() -> void:
	var tracker := ImplantTracker.new()
	eq(tracker.badge(db.talismans["quill_of_fate"]), "0/8")
	eq(tracker.badge(db.talismans["seed_pouch"]), "0/3")
	eq(tracker.badge(db.talismans["heart_of_tides"]), "ON")
	eq(tracker.badge(db.talismans["copper_ring"]), "TAKEN")

func test_map_tracking_and_save_defaults() -> void:
	var profile := Profile.new_player(db)
	var run := RunState.start(db, profile, RunState.default_picks(db, profile), 77)
	run.add_talisman("skip_tracer")
	run.implant_recent.clear()
	Talismans.fire_run(run, "jump")
	eq(run.implant_activations.get("skip_tracer", 0), 1)
	check("skip_tracer" in run.implant_recent, "jump marks animation")
	var data := run.to_dict()
	var restored := RunState.from_dict(db, data)
	eq(restored.implant_activations, run.implant_activations)
	data.erase("implant_activations")
	var legacy := RunState.from_dict(db, data)
	eq(legacy.implant_activations, {})
	var path := "user://test_implant_legacy.save"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(var_to_str({"version": 1, "run": data, "resume": {"screen": "map"}}))
	file.close()
	check(not RunSave.load_run(db, path).is_empty(), "version 1 remains loadable")
	RunSave.clear(path)

func test_view_animation_stops_and_preserves_rules() -> void:
	var view := TalismanView.new().setup("flint_shard", db)
	view.activate()
	check(view.is_processing(), "activation starts processing")
	view._process(0.8)
	check(not view.is_processing(), "idle does not animate")
	check("3" in TalismanView.text(db, "flint_shard"), "uses generated rule text")
	view.free()
