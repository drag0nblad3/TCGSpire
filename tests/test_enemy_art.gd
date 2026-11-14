extends TestCase

func test_non_boss_roster_has_unique_neon_cells_and_elite_layers() -> void:
	var used := {}
	for id in db.enemies:
		if BossPresentation.PROFILES.has(id): continue
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
