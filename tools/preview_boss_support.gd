extends SceneTree
## Production-rendered review of boss support bodies and hatchable card art.
class Gallery extends Control:
	var clock := 0.0
	var db: CardDB
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1120, 740), Color("0a0e1b"))
		draw_string(ThemeDB.fallback_font, Vector2(20, 30), "TCGSPIRE / BOSS BODIES + SUPPORT", HORIZONTAL_ALIGNMENT_LEFT, -1, 23, Color.WHITE)
		var i := 0
		for id in BossSupportArt.PROFILES:
			var origin := Vector2((i % 4) * 280, (i / 4) * 330 + 50)
			BossSupportArt.draw(self, id, origin + Vector2(140, 140), Vector2(250, 250), clock, 0.0, true)
			draw_string(ThemeDB.fallback_font, origin + Vector2(4, 290), db.enemies[id]["name"], HORIZONTAL_ALIGNMENT_CENTER, 272, 18, Color.WHITE)
			i += 1
		draw_texture_rect(CardArt.texture_for("spore_pod"), Rect2(848, 450, 264, 99), false)
		draw_string(ThemeDB.fallback_font, Vector2(848, 670), "Spore Pod / hatchable program", HORIZONTAL_ALIGNMENT_CENTER, 264, 17, Color.WHITE)

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1120, 740)
	var gallery := Gallery.new()
	gallery.db = CardDB.load_from("res://data")
	root.add_child(gallery)
	DirAccess.make_dir_recursive_absolute("/tmp/boss-support-review")
	for frame in 36:
		gallery.clock = frame / 12.0
		gallery.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/boss-support-review/frame-%03d.png" % frame)
	print("Rendered 36 boss support animation frames")
	quit()
