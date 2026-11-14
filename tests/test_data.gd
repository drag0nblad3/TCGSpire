extends TestCase
## Content sanity: every JSON file parses, every card/enemy validates.


func test_data_has_no_errors() -> void:
	for e in db.errors:
		failures.append(e)


func test_every_card_has_text() -> void:
	for id in db.cards:
		var c: CardDef = db.cards[id]
		for up in [false, true]:
			var txt := c.get_text(up)
			check(txt != "" and not "?" in txt, "%s%s has bad text '%s'" % [id, "+" if up else "", txt])


func test_packable_rarities_exist() -> void:
	for r in ["common", "uncommon", "rare"]:
		check(not Packs._pool(db, r).is_empty(), "no %s cards" % r)


func test_every_crew_has_the_same_rarity_spread() -> void:
	var want := {"common": 8, "uncommon": 9, "rare": 5, "mythic": 2}
	for f in Lexicon.FACTION:
		for r in want:
			var n := db.ids_where(func(c: CardDef) -> bool: return c.faction == f and c.faction2 == "" and c.rarity == r).size()
			eq(n, want[r], "%s %s cards" % [f, r])
