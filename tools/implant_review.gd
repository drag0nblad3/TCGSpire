extends SceneTree
## Render art/status review pages and a deterministic activation flipbook.
func _initialize() -> void:
	call_deferred("_render")

func _render() -> void:
	var mode := "0"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("page="):
			mode = arg.trim_prefix("page=")
	var motion := mode == "motion"
	root.content_scale_size = Vector2i(1000, 800) if motion else Vector2i(1200, 1480)
	root.size = root.content_scale_size
	var db := CardDB.shared()
	var host := ColorRect.new()
	host.color = Palette.PANEL_BG
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	var outer := VBoxContainer.new()
	outer.position = Vector2(20, 20)
	outer.size = Vector2(root.size) - Vector2(40, 40)
	outer.add_theme_constant_override("separation", 18)
	host.add_child(outer)
	outer.add_child(UiKit.label("TCGSPIRE · IMPLANT HARDWARE", 28, Palette.TEXT))
	outer.add_child(UiKit.label("Activation motion studies" if motion else "Merged rules · artwork and live status", 18, Palette.TEXT_DIM))
	var grid := GridContainer.new()
	grid.columns = 3 if motion else 5
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 18)
	outer.add_child(grid)
	var tracker := ImplantTracker.new()
	tracker.progress = {"flint_shard:0": 2, "quill_of_fate:0": 6, "seed_pouch:0": 1, "spool_buffer:0": 2}
	tracker.counts = {"oak_token": 1, "ember_charm": 1, "first_light": 1, "echo_shell": 1}
	var ids: Array = ["flint_shard", "tide_pendant", "iron_will", "heartbeat_monitor", "ember_brazier", "crash_reporter"] if motion else db.talismans.keys().slice(int(mode) * 25, int(mode) * 25 + 25)
	var views: Array[TalismanView] = []
	for id in ids:
		var box := UiKit.vbox(5)
		box.custom_minimum_size = Vector2(310, 290) if motion else Vector2(220, 252)
		grid.add_child(box)
		var view := TalismanView.new().setup(id, db, true)
		view.custom_minimum_size = Vector2(200, 216) if motion else Vector2(184, 200)
		view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		view.tracker = tracker
		box.add_child(view)
		box.add_child(UiKit.label(str(db.talismans[id]["name"]), 17))
		if motion:
			box.add_child(UiKit.label(str(ImplantArt.regions()[id]["motion"]).capitalize(), 14, Palette.TEXT_DIM))
		views.append(view)
	await process_frame
	await process_frame
	for frame in (18 if motion else 1):
		if motion:
			for view in views:
				view._flash = 0.72 * maxf(0.0, 1.0 - float(frame) / 14.0)
				view.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var path := "/tmp/implant-motion-%02d.png" % frame if motion else "res://docs/implants-review-%s.png" % mode
		root.get_texture().get_image().save_png(path)
	print("saved implant review ", mode)
	quit()
