extends SceneTree
## Reproducible preview of the same renderer used by FighterView.
class Gallery extends Control:
	var clock := 0.0
	var page := 0
	var names := {}
	var ids: Array = VirtualBossArt.ANIMATED + VirtualBossArt.PROFILES.keys()
	const NAMES := ["KILN MOTHER", "UNDERTOW PRIME BROKER", "CHIEF SURGEON", "CELL ZERO PRIME", "HIVE OVERSEER", "DJ FEEDBACK"]
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 960, 680), Color("080b16"))
		for i in 6:
			var id: String = ids[page * 6 + i]
			var profile: Dictionary = BossPresentation.PROFILES[id]
			var rect := Rect2((i % 3) * 320 + 10, (i / 3) * 340 + 12, 300, 280)
			var accent := Palette.faction(profile["faction"])
			var action := maxf(0.0, 1.0 - absf(clock - 2.0) * 2.0)
			VirtualBossArt.draw(self, profile["portrait"], rect, id, clock, action, Color.WHITE, accent)
			draw_string(ThemeDB.fallback_font, Vector2(rect.position.x, rect.end.y + 22), str(names.get(id, id)).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 300, 15, Color.WHITE)
			draw_string(ThemeDB.fallback_font, Vector2(rect.position.x, rect.end.y + 41), "MOVE BURST" if action > 0.0 else "IDLE", HORIZONTAL_ALIGNMENT_CENTER, 300, 12, accent)

func _initialize() -> void:
	call_deferred("capture")

func capture() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_factor = 1.0
	root.size = Vector2i(960, 680)
	var gallery := Gallery.new()
	root.add_child(gallery)
	var db := CardDB.load_from("res://data")
	for id in db.enemies: gallery.names[id] = db.enemies[id]["name"]
	DirAccess.make_dir_recursive_absolute("/tmp/tcg-boss-frames")
	for i in 80:
		gallery.page = i / 20
		gallery.clock = (i % 20) / 5.0
		gallery.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/tcg-boss-frames/%03d.png" % i)
	print("saved 80 boss animation frames")
	quit()
