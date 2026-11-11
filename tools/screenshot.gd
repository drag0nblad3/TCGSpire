extends SceneTree
## Boots the real main scene, optionally auto-plays a few actions, and saves a
## PNG. Lets you review UI changes from the CLI without an emulator.
##   scripts/shot.sh [out=/tmp/shot.png] [frames=30] [plays=2]
## Under --headless it still runs as a smoke test (catches script errors) but
## writes no image; scripts/shot.sh uses xvfb for a real render.


func _initialize() -> void:
	var opts := {"out": "user://shot.png", "frames": "30", "plays": "0"}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2:
			opts[kv[0]] = kv[1]
	var main: Control = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	for i in 3:
		await process_frame
	# Tap the first N playable cards via the same API the UI uses.
	var screen = main.get("_screen")
	if screen is CombatScreen:
		for p in int(opts["plays"]):
			var c: Combat = screen.combat
			for i in c.hand.size():
				if c.can_play(i):
					screen._on_card_pressed(null, i)
					if screen._selected >= 0:
						screen._on_enemy_pressed(null, c.enemies.find(c.living(c.enemies)[0]))
					break
			await process_frame
			await process_frame
	for i in int(opts["frames"]):
		await process_frame
	if DisplayServer.get_name() != "headless":
		var img := root.get_texture().get_image()
		img.save_png(opts["out"])
		print("saved ", opts["out"], " ", img.get_size())
	else:
		print("smoke ok (headless, no image)")
	quit(0)
