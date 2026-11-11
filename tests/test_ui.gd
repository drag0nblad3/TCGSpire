extends TestCase
## UI logic that can run headless: tap detection, intents, glossary, themes,
## and the combat screen's input flow (animations off via step_scale = 0).


func _press(pos: Vector2, down: bool) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = pos
	return ev


func test_tap_fires_once_per_tap() -> void:
	var t := Tap.new()
	eq(t.feed(_press(Vector2(10, 10), true)), "")
	# Android sends a touch AND an emulated mouse event for one finger: only one may count.
	var touch := InputEventScreenTouch.new()
	touch.pressed = false
	eq(t.feed(touch), "", "touch must be ignored")
	eq(t.feed(_press(Vector2(12, 11), false)), "tap")
	eq(t.feed(_press(Vector2(12, 11), false)), "", "release without press")


func test_drag_is_not_a_tap() -> void:
	var t := Tap.new()
	t.feed(_press(Vector2(10, 10), true))
	var mv := InputEventMouseMotion.new()
	mv.position = Vector2(10, 60)
	t.feed(mv)
	eq(t.feed(_press(Vector2(10, 60), false)), "", "scrolling selected a card")


func test_card_view_single_tap_emits_once() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var cv := CardView.new().setup(db.instance("jab"))
	root.add_child(cv)
	var count := [0]
	cv.pressed.connect(func(_v: CardView) -> void: count[0] += 1)
	cv._gui_input(_press(Vector2(20, 20), true))
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	cv._gui_input(touch)
	cv._gui_input(_press(Vector2(20, 20), false))
	eq(count[0], 1)
	cv.free()


func test_intents_classify_moves() -> void:
	var c := make_combat([], "mites")
	c.start()
	var en: Fighter = c.enemies[0]
	en.moves = [{"name": "X", "effects": [{"op": "damage", "amount": 4, "hits": 2}, {"op": "ward", "amount": 5},
		{"op": "apply", "status": "weaken", "stacks": 1}, {"op": "apply", "status": "might", "stacks": 2, "to": "self"}]}]
	en.move_idx = 0
	en.statuses = {"might": 1}
	var items := Intents.of(c, en)
	eq(items.map(func(i: Dictionary) -> String: return i["kind"]), ["attack", "ward", "debuff", "buff"])
	eq(items[0]["value"], 5, "might should be included")
	eq(items[0]["hits"], 2)
	eq(IntentIcon.label(items[0]), "5x2")


func test_glossary_explains_keywords_and_statuses() -> void:
	var found := false
	for id in db.cards:
		var inst := db.instance(id)
		for line in CardInspector.glossary(inst):
			check(not line.contains("?"), "%s: odd glossary line %s" % [id, line])
		if inst.def.get_keywords(false).has("exhaust"):
			found = found or CardInspector.glossary(inst).any(func(l: String) -> bool: return l.begins_with("Exhaust:"))
	check(found, "no exhaust explanation found")


func test_every_theme_applies() -> void:
	for id in Themes.ORDER:
		Palette.apply(id)
		eq(Palette.theme_id, id)
		check(Palette.w("title") != "", id + " has no title")
		for f in ["neutral", "ember", "tide", "bloom", "void"]:
			check(Palette.faction_name(f) != "", "%s: no name for %s" % [id, f])
		check(not Rules.sections(db).is_empty(), "rules empty")
	Palette.apply(Themes.DEFAULT)


func test_combat_screen_select_cancel_play() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var c := make_combat(["jab", "jab", "jab", "jab", "jab"], "mites")
	c.start()
	var cs := CombatScreen.new().setup(c, null)
	cs.step_scale = 0.0
	root.add_child(cs)
	if cs._hand_row == null:
		cs._ready()  # the test runner's root isn't "ready" yet, so _ready is deferred
	cs._on_card_pressed(null, 0)
	eq(cs._selected, 0, "targeted card with 2 enemies should wait for a target")
	cs._on_card_pressed(null, 0)
	eq(cs._selected, -1, "second tap should cancel")
	cs._on_card_pressed(null, 0)
	cs._on_enemy_pressed(null, 1)
	eq(c.hand.size(), 4)
	check(not cs.is_busy(), "still busy after playback")
	eq(cs._views[c.enemies[1].id].hp(), c.enemies[1].hp, "shown HP out of sync")
	cs._on_end_turn()
	eq(c.turn, 2)
	cs.free()
