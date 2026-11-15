extends TestCase

func test_encounter_bosses_have_animation_and_unique_art() -> void:
	var paths := {}
	for encounter in db.encounters.values():
		if encounter.get("kind", "") != "boss": continue
		# Escorts, pylons and extra bodies use sentry portraits; every Core fight needs at least one illustrated boss.
		var leads: Array = encounter["enemies"].filter(func(id: String) -> bool: return BossPresentation.PROFILES.has(id))
		check(not leads.is_empty(), "boss fight without a boss portrait: " + str(encounter["enemies"]))
		for id in leads:
			check(VirtualBossArt.supports(id), "boss animation missing: " + id)
			check(BossPresentation.PROFILES.has(id), "boss portrait missing: " + id)
			var texture: Texture2D = BossPresentation.PROFILES[id]["portrait"]
			check(texture.get_width() > 0 and texture.get_height() > 0, "portrait load failed: " + id)
			if paths.has(texture.resource_path):
				eq(paths[texture.resource_path], id, "different bosses share an illustration")
			paths[texture.resource_path] = id
	check(not VirtualBossArt.supports("future_unknown_boss"), "unknown bosses use static fallback")
