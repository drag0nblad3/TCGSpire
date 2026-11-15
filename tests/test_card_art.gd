extends TestCase

## The Interrupt programs and the card abilities wave (data/cards/abilities.json) draw the
## procedural fallback until their art is made.
const AWAITING_ART := ["flashover", "slack_water", "antibody", "null_route", "failover", "bad_signal", "line_cut",
	"script_kiddie", "black_hat", "clear_cache", "deep_clean", "full_send", "undelete", "pilot_light", "wildfire", "zero_day_window", "burn_the_logs", "thermal_runaway", "sandbag_wall", "seawall", "swap_file", "bulkhead", "rewind_buffer", "spore_pod", "bloomhost", "cuttings", "shed_skin", "mother_culture", "echo_probe", "echo_array", "cold_boot", "null_sink", "blind_drop", "scrap_drone", "war_drone", "drone_reel", "mass_deploy", "watchdog_boot", "index_scan", "white_noise", "backlog", "signal_jam"]


func test_every_card_has_distinct_in_bounds_art() -> void:
	var regions := CardArt.regions()
	var awaiting_art := AWAITING_ART
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
		if definition.type != "unit" or definition.id in AWAITING_ART:
			continue
		var effect: Dictionary = definition.effects[0]
		if effect.get("op", "") != "summon":
			continue
		var source := CardArt.daemon_card(effect["name"], db)
		check(source != null, "missing daemon source: " + effect["name"])
		if source != null:
			check(CardArt.texture_for(source.id) != null, "daemon texture resolves")
	check(CardArt.daemon_card("Unknown future daemon", db) == null, "unknown daemon fallback")
