extends TestCase

func test_boss_support_bodies_have_unique_transparent_animated_art() -> void:
	var paths := {}
	for id in BossSupportArt.PROFILES:
		check(db.enemies.has(id), "unknown support body: " + id)
		check(VirtualBossArt.supports(id), "support animation missing: " + id)
		var texture: Texture2D = BossSupportArt.PROFILES[id][0]
		var image := texture.get_image()
		eq(image.get_size(), Vector2i(512, 400), "support asset dimensions")
		check(image.detect_alpha() != Image.ALPHA_NONE, "support background must be transparent")
		check(image.get_used_rect().has_area(), "empty support art")
		check(not paths.has(texture.resource_path), "support bodies need distinct art")
		paths[texture.resource_path] = true
		for point in [Vector2i.ZERO, Vector2i(511, 0), Vector2i(0, 399), Vector2i(511, 399)]:
			eq(image.get_pixelv(point).a, 0.0, "transparent margin")

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
