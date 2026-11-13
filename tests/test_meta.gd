extends TestCase

const TMP := "user://test_profile.json"


func test_new_player_gets_starter_collection() -> void:
	var p := Profile.new_player(db)
	check(p.collection.count("kindle") >= 1, "kindle missing")


func test_disenchant_keeps_last_copy() -> void:
	var col := Collection.new()
	col.add("kindle", 2)
	check(col.disenchant("kindle", db), "first disenchant")
	check(not col.disenchant("kindle", db), "last copy disenchanted")
	eq(col.dust, 5)


func test_craft_spends_dust() -> void:
	var col := Collection.new()
	col.dust = 45
	check(col.craft("kindle", db), "craft")
	eq(col.dust, 5)
	check(not col.craft("blaze_heart", db), "rare without dust")


func test_pack_is_deterministic_and_skips_starters() -> void:
	var a := Packs.open(db, GameRng.new(11))
	eq(a, Packs.open(db, GameRng.new(11)))
	eq(a.size(), int(db.balance["pack"]["size"]))
	for c in a:
		check(db.card(c["id"]).rarity != "starter", "starter in pack")


func test_pack_hot_slot_is_uncommon_or_better() -> void:
	for seed in 40:
		var cards := Packs.open(db, GameRng.new(seed))
		check(cards.back()["hot"], "last card is the hot slot")
		check(db.card(cards.back()["id"]).rarity in ["uncommon", "rare", "mythic"], "hot slot rarity")


func test_pack_pity_guarantees_rare_and_mythic() -> void:
	var p := Profile.new_player(db)
	p.packs_unopened = 200
	var since_rare := 0
	var since_mythic := 0
	var pity: Dictionary = db.balance["pack"]["pity"]
	for i in 200:
		var rarities: Array = p.open_pack(db, GameRng.new(i)).map(func(c: Dictionary) -> String: return db.card(c["id"]).rarity)
		since_rare = 0 if ("rare" in rarities or "mythic" in rarities) else since_rare + 1
		since_mythic = 0 if "mythic" in rarities else since_mythic + 1
		check(since_rare < int(pity["rare"]), "rare pity broke at pack %d" % i)
		check(since_mythic < int(pity["mythic"]), "mythic pity broke at pack %d" % i)
	eq(int(p.pack_pity["rare"]), since_rare, "pity counter tracks")


func test_pack_flags_new_cards_and_unlocks() -> void:
	var p := Profile.new()
	p.packs_unopened = 1
	var cards := p.open_pack(db, GameRng.new(3))
	for c in cards:
		check(c.has("new") and c.has("count") and c.has("unlocked"), "pack card flags")
	var first: Dictionary = cards[0]
	check(first["new"], "an empty collection makes every first copy new")


func test_complete_ladders_are_rerolled() -> void:
	# Own the full ladder of half the commons: those slots reroll once, so fewer
	# complete commons show up than without the profile.
	var p := Profile.new()
	var commons := db.ids_where(func(c: CardDef) -> bool: return c.rarity == "common")
	commons.sort()
	for i in commons.size() / 2:
		p.collection.add(commons[i], Profile.deck_limit(db))
		p.firmware[commons[i]] = Profile.firmware_max(db)
	check(p.copies_complete(db, "jab") == false, "starters have no ladder")
	var hits := 0
	for i in 200:
		for c in Packs.open(db, GameRng.new(i), p):
			if p.copies_complete(db, c["id"]):
				hits += 1
	var plain := 0
	for i in 200:
		for c in Packs.open(db, GameRng.new(i)):
			if p.copies_complete(db, c["id"]):
				plain += 1
	check(hits < plain * 0.75, "rerolls cut complete pulls (%d vs %d)" % [hits, plain])


func test_daily_pack_paid_on_attempt_once() -> void:
	var p := Profile.new()
	eq(Records.begin_daily(db, p, "2026-11-13"), int(db.balance["daily"]["packs"]))
	eq(p.packs_unopened, int(db.balance["daily"]["packs"]))
	eq(Records.begin_daily(db, p, "2026-11-13"), 0, "one attempt a day")


func test_elite_shards_fuse_into_packs() -> void:
	var p := Profile.new()
	var per := Profile.shards_per_pack(db)
	p.add_shards(db, per + 1)
	eq(p.packs_unopened, 1)
	eq(p.pack_shards, 1)
	var q := Profile.from_dict(p.to_dict())
	eq(q.pack_shards, 1, "shards saved")


func test_ready_to_flash_lists_cards_with_copies_and_rep() -> void:
	var p := Profile.new()
	var need := int(Profile.copy_ladder(db, "kindle")[0])
	p.collection.add("kindle", Profile.deck_limit(db) + need)
	check("kindle" not in p.ready_to_flash(db), "needs rep too")
	p.rep["ember"] = 999
	check("kindle" in p.ready_to_flash(db), "ready")
	check(p.copy_badge(db, "kindle").ends_with("ready"), "badge says ready")


func test_profile_save_roundtrip() -> void:
	var p := Profile.new_player(db)
	p.collection.dust = 123
	p.packs_unopened = 2
	eq(p.save(TMP), OK, "save")
	var q := Profile.load_or_new(db, TMP)
	eq(q.collection.dust, 123)
	eq(q.packs_unopened, 2)
	eq(q.collection.counts, p.collection.counts)
	DirAccess.remove_absolute(TMP)


func test_run_uses_base_deck_plus_picks() -> void:
	var p := Profile.new_player(db)
	var picks := RunState.default_picks(db, p)
	var run := RunState.start(db, p, picks, 1)
	eq(run.deck.size(), db.balance["base_deck"].size() + picks.size())


func test_run_rejects_unowned_pick() -> void:
	var p := Profile.new_player(db)
	var run := RunState.start(db, p, ["leviathan_call"], 1)
	eq(run.deck.size(), db.balance["base_deck"].size())
