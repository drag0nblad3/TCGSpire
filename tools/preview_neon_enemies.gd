extends SceneTree
## Render all bases and elite composites through the production renderer.
class Gallery extends Control:
	var faction := "ember"
	var clock := 0.7
	var ids: Array = []
	var names := {}
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1120, 860), Color("0a0e1b"))
		draw_string(ThemeDB.fallback_font, Vector2(20, 30), "TCGSPIRE / " + faction.to_upper() + " / NORMAL + ELITE", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
		for i in ids.size():
			var id: String = ids[i]
			var x := float(i % 4) * 280.0
			var y := float(i / 4) * 380.0 + 50.0
			EnemyPortraits.draw(self, Vector2(x + 140, y + 85), Vector2(245, 160), EnemyPortraits.ROSTER[id], clock, false)
			EnemyPortraits.draw(self, Vector2(x + 140, y + 260), Vector2(245, 160), EnemyPortraits.ROSTER[id], clock, true)
			draw_string(ThemeDB.fallback_font, Vector2(x + 4, y + 355), names.get(id, id), HORIZONTAL_ALIGNMENT_CENTER, 272, 15, Color.WHITE)

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1120, 860)
	var db := CardDB.load_from("res://data")
	var gallery := Gallery.new()
	root.add_child(gallery)
	DirAccess.make_dir_recursive_absolute("/tmp/neon-review")
	for id in db.enemies: gallery.names[id] = db.enemies[id]["name"]
	for faction in EnemyPortraits.ATLASES:
		var ids: Array = []
		for id in EnemyPortraits.ROSTER:
			if EnemyPortraits.ROSTER[id][0] == faction: ids.append(id)
		for page in ceili(ids.size() / 8.0):
			gallery.faction = faction
			gallery.ids = ids.slice(page * 8, (page + 1) * 8)
			gallery.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("/tmp/neon-review/%s-%d.png" % [faction, page])
	print("Rendered all 67 normal and elite enemy composites")
	quit()
