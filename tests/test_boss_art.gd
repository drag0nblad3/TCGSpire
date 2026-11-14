extends TestCase

func test_encounter_bosses_have_animation_and_unique_art() -> void:
	var paths := {}
	for encounter in db.encounters.values():
		if encounter.get("kind", "") != "boss": continue
		for id in encounter["enemies"]:
			check(VirtualBossArt.supports(id), "boss animation missing: " + id)
			check(BossPresentation.PROFILES.has(id), "boss portrait missing: " + id)
			var texture: Texture2D = BossPresentation.PROFILES[id]["portrait"]
			check(texture.get_width() > 0 and texture.get_height() > 0, "portrait load failed: " + id)
			if paths.has(texture.resource_path):
				eq(paths[texture.resource_path], id, "different bosses share an illustration")
			paths[texture.resource_path] = id
	check(not VirtualBossArt.supports("future_unknown_boss"), "unknown bosses use static fallback")
