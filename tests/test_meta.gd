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
	eq(a.size(), 5)
	for c in a:
		check(db.card(c["id"]).rarity != "starter", "starter in pack")


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
