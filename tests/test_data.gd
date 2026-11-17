extends TestCase
## Content sanity: every JSON file parses, every card/enemy validates.


func test_data_has_no_errors() -> void:
	for e in db.errors:
		failures.append(e)


func test_implants_have_no_penalties() -> void:
	for id in db.talismans:
		var t: Dictionary = db.talismans[id]
		for o in t.get("pickup", []):
			var op := str(o.get("op", ""))
			check(op != "lose_hp", "%s loses HP" % id)
			check(not (op in ["max_hp", "gold"] and float(o.get("amount", 0)) < 0), "%s takes %s" % [id, op])
			if op == "add_card" and db.cards.has(str(o.get("card", ""))):
				check(db.cards[str(o["card"])].rarity != "curse", "%s adds a curse" % id)
			check(str(o.get("rarity", "")) != "curse", "%s adds a curse" % id)
		for k in t.get("mods", {}):
			check(float(t["mods"][k]) >= 0, "%s lowers %s" % [id, k])
		for k in t.get("daemon", {}):
			check(float(t["daemon"][k]) >= (1.0 if k == "hp_mult" else 0.0), "%s weakens daemons" % id)


func test_no_free_damage_cantrips() -> void:
	# Tyler's rule: no 0 RAM card that deals or adds damage and draws to replace itself without Wipe or another real cost.
	for id in db.cards:
		var c: CardDef = db.cards[id]
		if c.type == "unit":
			continue
		for up in [false, true]:
			var card := CardInstance.new(c, up)
			check(not CardMods.free_damage_cantrip(c.get_effects(up), c.get_keywords(up), card.base_cost() if not card.is_x() else 1), "%s%s is a free damage cantrip" % [id, "+" if up else ""])
			for m in db.mods:
				if CardMods.can_apply(db.mod(m), card):
					var effs: Array = c.get_effects(up) + db.mod(m).get("effects_add", [])
					var kws: Array = c.get_keywords(up) + db.mod(m).get("keywords_add", [])
					check(not CardMods.free_damage_cantrip(effs, kws, CardMods.cost(db.mod(m), card.base_cost()) if not card.is_x() else 1), "%s%s + %s is a free damage cantrip" % [id, "+" if up else "", m])


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
	var want := {"common": 10, "uncommon": 10, "rare": 6, "mythic": 2}
	# Street carries one extra uncommon: Backlash, the "When you lose HP" daemon.
	var extra := {"neutral": {"uncommon": 1}}
	for f in Lexicon.FACTION:
		for r in want:
			var n := db.ids_where(func(c: CardDef) -> bool: return c.faction == f and c.faction2 == "" and c.rarity == r).size()
			eq(n, want[r] + int(extra.get(f, {}).get(r, 0)), "%s %s cards" % [f, r])
