extends TestCase


func test_every_card_has_distinct_in_bounds_art() -> void:
	var regions := CardArt.regions()
	eq(regions.size(), db.cards.size(), "art coverage must match card database")
	var used := {}
	var atlas_bounds := Rect2(Vector2.ZERO, CardArt.ATLAS.get_size())
	for id in db.cards:
		var texture := CardArt.texture_for(id) as AtlasTexture
		check(texture != null, "missing illustration: " + id)
		if texture == null:
			continue
		check(atlas_bounds.encloses(texture.region), "art outside atlas: " + id)
		eq(texture.region.size, Vector2(448, 168), "card art aspect ratio")
		check(not used.has(texture.region.position), "duplicate illustration: " + id)
		used[texture.region.position] = true
		check(texture == CardArt.texture_for(id), "art cache reused: " + id)
	check(CardArt.texture_for("unknown_future_card") == null, "future cards retain fallback")


func test_primary_daemon_summons_have_portraits() -> void:
	for definition: CardDef in db.cards.values():
		if definition.type != "unit":
			continue
		var effect: Dictionary = definition.effects[0]
		if effect.get("op", "") != "summon":
			continue
		var source := CardArt.daemon_card(effect["name"], db)
		check(source != null, "missing daemon source: " + effect["name"])
		if source != null:
			check(CardArt.texture_for(source.id) != null, "daemon texture resolves")
	check(CardArt.daemon_card("Unknown future daemon", db) == null, "unknown daemon fallback")
