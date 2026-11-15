extends TestCase

func test_idle_motion_is_bounded_and_varies_for_every_profile() -> void:
	for id in EnemyPortraits.ROSTER:
		var effect: String = EnemyPortraits.ROSTER[id][2]
		var head := Vector2(110, 30)
		check(EnemyPortraits.idle_point(head, effect, 0.0).distance_to(EnemyPortraits.idle_point(head, effect, 0.7)) > 0.1, "static enemy: " + id)
		for step in 60:
			for point in [Vector2.ZERO, Vector2(220, 0), Vector2(0, 170), Vector2(220, 170), head]:
				var posed := EnemyPortraits.idle_point(point, effect, step * 0.1)
				check(posed.is_finite() and posed.distance_to(point) < 10.0, "motion exceeds portrait margin: " + id)
			var foot := Vector2(110, 170)
			eq(EnemyPortraits.idle_point(foot, effect, step * 0.1), foot, "foot anchor")

func test_non_boss_roster_has_unique_neon_cells_and_elite_layers() -> void:
	var used := {}
	for id in db.enemies:
		if BossPresentation.PROFILES.has(id): continue
		if BossSupportArt.PROFILES.has(id): continue
		check(EnemyPortraits.ROSTER.has(id), "unmapped enemy: " + id)
		if not EnemyPortraits.ROSTER.has(id): continue
		var p: Array = EnemyPortraits.ROSTER[id]
		var texture: Texture2D = EnemyPortraits.ATLASES[p[0]]
		var cols := 5 if p[0] == "neutral" else 3
		var cell := EnemyPortraits.CELL * 2.0
		var region := Rect2(Vector2(int(p[1]) % cols, int(p[1]) / cols) * cell, cell)
		check(Rect2(Vector2.ZERO, texture.get_size()).encloses(region), "out of bounds: " + id)
		check(texture.get_image().get_region(Rect2i(region)).get_used_rect().has_area(), "empty base: " + id)
		var key := "%s:%s" % [p[0], p[1]]
		check(not used.has(key), "duplicate enemy art: " + id)
		used[key] = true
	for faction in EnemyPortraits.ATLASES:
		var image: Image = EnemyPortraits.ATLASES[faction].get_image()
		check(image.detect_alpha() != Image.ALPHA_NONE, "atlas must be transparent: " + faction)
		var cells := 27 if faction == "neutral" else 9
		var cols := 5 if faction == "neutral" else 3
		for slot in [cells - 2, cells - 1]:
			var area := Rect2i((slot % cols) * 440, (slot / cols) * 340, 440, 340)
			check(image.get_region(area).get_used_rect().has_area(), "elite layer missing: " + faction)
