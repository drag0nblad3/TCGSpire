extends SceneTree
## Controlled real-UI preview of transient effects; never loads or writes a real save.
func _initialize() -> void:
	var main: Control = load("res://ui/main.tscn").instantiate()
	main.persist = false
	root.add_child(main)
	await process_frame
	main.profile = Profile.new_player(main.db)
	main.run = RunState.start(main.db, main.profile, RunState.default_picks(main.db, main.profile), 7)
	main._start_combat({"type": "fight", "encounter": "wisp_court"})
	var cs: CombatScreen = main._screen
	cs.combat.hand = main.db.make_deck(["kindle", "brace", "drone_swarm", "sprout", "spark_wisp"])
	for pair in [["Drone", 2, 4], ["Cell", 2, 6], ["Glitch", 2, 4]]:
		var unit := Fighter.make("review_" + pair[0], pair[0], pair[2])
		unit.atk = pair[1]
		cs.combat.units.append(unit)
	cs._selected = 0
	cs._rebuild()
	for i in 20:
		await process_frame
	var enemies := cs._enemies_row.get_children()
	Input.warp_mouse(enemies[1].global_position + enemies[1].size * 0.5)
	for i in 6:
		await process_frame
	root.get_texture().get_image().save_png("/tmp/tcg-polish-target.png")
	for i in 24:
		var phase := float(i) / 24.0
		enemies[0].firewall_flash = 1.0 - phase
		enemies[1].flash = 1.0 - phase
		enemies[2].virus_flash = 1.0 - phase
		cs._action_label.text = "Firewall ripple  ·  HP impact  ·  Virus traces"
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/tcg-polish-fx-%02d.png" % i)
	main._show_reward(["Recovered rare programs"], [], ["pyre", "carrier_drone", "singularity"])
	for i in 3:
		await process_frame
	var cards: Array[CardView] = []
	_collect(main._screen, cards)
	for cv in cards:
		if cv._reveal_tween != null:
			cv._reveal_tween.kill()
	for i in 24:
		for cv in cards:
			cv.reveal_progress = float(i) / 23.0
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/tmp/tcg-polish-reward-%02d.png" % i)
	quit()

func _collect(node: Node, cards: Array[CardView]) -> void:
	if node is CardView:
		cards.append(node)
	for child in node.get_children():
		_collect(child, cards)
