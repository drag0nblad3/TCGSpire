extends TestCase


func test_every_card_has_distinct_in_bounds_art() -> void:
	var regions := CardArt.regions()
	# The Interrupt programs draw the procedural fallback until their art sheet is made.
	var awaiting_art := ["flashover", "slack_water", "antibody", "null_route", "failover", "bad_signal", "line_cut"]
	for id in db.cards:
		check(regions.has(id) or id in awaiting_art, "card has illustration: " + id)
	for id in regions:
		check(db.cards.has(id), "art for unknown card: " + id)
	var used := {}
	for id in regions:
		var texture := CardArt.texture_for(id) as AtlasTexture
		check(texture != null, "missing illustration: " + id)
		if texture == null:
			continue
		var atlas_bounds := Rect2(Vector2.ZERO, texture.atlas.get_size())
		check(atlas_bounds.encloses(texture.region), "art outside atlas: " + id)
		eq(texture.region.size, Vector2(448, 168), "card art aspect ratio")
		var key := str(texture.atlas.resource_path) + str(texture.region.position)
		check(not used.has(key), "duplicate illustration: " + id)
		used[key] = true
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
