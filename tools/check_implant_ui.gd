extends SceneTree
func _initialize() -> void:
	call_deferred("_check")
func _check() -> void:
	var main: Control = load("res://ui/main.tscn").instantiate()
	main.persist = false
	root.add_child(main)
	await process_frame
	main.profile = Profile.new_player(main.db)
	main.run = RunState.start(main.db, main.profile, RunState.default_picks(main.db, main.profile), 12)
	main.run.talismans = ["oak_token", "flint_shard", "seed_pouch", "quill_of_fate", "pressure_valve", "grafted_host", "tide_pendant", "spool_buffer", "heartbeat_monitor", "crash_reporter", "everbloom", "iron_will"]
	main._start_combat({"type": "fight", "encounter": "mites"})
	await process_frame
	await process_frame
	var screen: CombatScreen = main._screen
	assert(screen._implant_views.size() == 12)
	assert(screen._implant_views["oak_token"].status() == "USED")
	assert(screen._implant_views["pressure_valve"].status() == "OFF")
	assert(screen._implant_views["seed_pouch"].status() == "1/3")
	assert(screen.get_combined_minimum_size().x <= 720, "implant strip must not widen combat")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/implants-combat.png")
	screen._implant_views["flint_shard"].inspect()
	await process_frame
	await process_frame
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://docs/implant-inspector.png")
	if is_instance_valid(GameMusic.instance):
		GameMusic.instance.configure({"music_muted": true})
	await create_timer(0.2).timeout
	print("OK: implant startup states, overflow strip and inspector")
	quit()
