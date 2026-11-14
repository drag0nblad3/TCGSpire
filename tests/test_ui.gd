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
	en.dmg_mult = 1.0
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
			found = found or CardInspector.glossary(inst).any(func(l: String) -> bool: return l.begins_with(Lexicon.keyword("exhaust") + ":"))
	check(found, "no exhaust explanation found")


func test_glossaries_show_rule_names_once() -> void:
	var locked := "Locked: Can't be run. It just clogs your hand."
	var exposed := "Takes 50% more attack damage. Loses 1 stack at end of turn."
	check(locked in CardInspector.glossary(db.instance("doubt")), "Locked card glossary")
	check("Exposed: " + exposed in CardInspector.glossary(db.instance("searing_brand")), "Exposed card glossary")
	var rules := {}
	for section in Rules.sections(db):
		rules[section[0]] = section[2]
	check(["Exposed", exposed] in rules["Statuses"], "Exposed in the rules reference")
	check(["Locked", locked.trim_prefix("Locked: ")] in rules["Keywords"], "Locked in the rules reference")


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


func test_rules_reference_structure() -> void:
	var secs := Rules.sections(db)
	var heads := Rules.headings(db)
	for h in ["Turn flow", "Program types", "Keywords", "Statuses", "Enemy intents", "Firewall and daemons", "Collecting", "Firmware"]:
		check(h in heads, "missing rules section " + h)
	for sec in secs:
		check(sec[1] in Rules.GROUPS, "unknown group for " + sec[0])
		check(not (sec[2] as Array).is_empty(), "empty section " + sec[0])
		for e in sec[2]:
			check(e is String or (e is Array and e.size() == 2), "bad entry in " + sec[0])
	# Every status and keyword is documented by its player-facing name.
	var terms: Array = []
	for sec in secs:
		for e in sec[2]:
			if e is Array:
				terms.append(e[0])
	for k in Statuses.DEFS:
		check(Lexicon.status(k) in terms, "status not in rules: " + k)
	for k in CardDef.KEYWORD_DESC:
		check(Lexicon.keyword(k) in terms, "keyword not in rules: " + k)
	for t in CardDef.TYPE_DESC:
		check(not CardDef.TYPE_DESC[t].contains("hit the front enemy"), "stale daemon text")


func test_tutorial_fight_is_teachable() -> void:
	var c := Tutorial.make_combat(db)
	var types: Array = c.hand.map(func(ci: CardInstance) -> String: return ci.def.type)
	check("attack" in types, "opening hand needs an Exploit")
	check(c.hand.any(func(ci: CardInstance) -> bool: return ci.def.id == "brace"), "opening hand needs Brace")
	eq(Tutorial.STEPS.size(), Tutorial.STEPS.size())
	for i in Tutorial.STEPS.size():
		check(not Tutorial.step_text(db, i).contains("%"), "step text %d" % i)
	var since := c.events.size()
	check(not Tutorial.step_done(1, c, since), "attack step done too early")
	var atk := types.find("attack")
	c.play_card(atk, 0)
	check(Tutorial.step_done(1, c, since), "attack step should finish after an Exploit")
	var b := c.hand.find(c.hand.filter(func(ci: CardInstance) -> bool: return ci.def.id == "brace")[0])
	c.play_card(b, -1)
	check(Tutorial.step_done(2, c, since), "ward step should finish after Brace")
	c.end_turn()
	check(Tutorial.step_done(3, c, since), "turn step should finish on turn 2")


func test_tutorial_coach_follows_screen() -> void:
	var root: Window = (Engine.get_main_loop() as SceneTree).root
	var c := Tutorial.make_combat(db)
	var cs := CombatScreen.new().setup(c, null)
	cs.step_scale = 0.0
	root.add_child(cs)
	if cs._hand_row == null:
		cs._ready()
	var coach := Tutorial.new().setup(cs)
	cs.add_child(coach)
	if coach._text == null:
		coach._ready()
	eq(coach.step, 0)
	coach._advance()
	eq(coach.step, 1)
	var atk := -1
	for i in c.hand.size():
		if c.hand[i].def.type == "attack":
			atk = i
			break
	cs._on_card_pressed(null, atk)
	cs._on_enemy_pressed(null, 0)
	eq(coach.step, 2, "coach should move on after an Exploit")
	cs._on_end_turn()
	check(coach.step >= 4, "coach should reach the daemon tip on turn 2")
	cs.free()


func test_hub_offers_tutorial_to_new_players() -> void:
	var p := Profile.new_player(db)
	var hub := HubScreen.new().setup(db, p)
	check(hub.first_time(), "new profile should see the tutorial")
	p.settings["tutorial_done"] = true
	check(not hub.first_time(), "done tutorial should hide the prompt")
	hub.free()


func test_upgrade_diff_marks_changed_numbers() -> void:
	eq(CardView.diff_text("Deal 6 damage.", "Deal 8 damage."), "Deal 6→8 damage.", "changed number shows old→new")
	eq(CardView.diff_text("Deal 4 damage. Apply 3 Virus.", "Deal 5 damage. Apply 3 Virus."), "Deal 4→5 damage. Apply 3 Virus.", "unchanged numbers stay plain")
	eq(CardView.diff_text("Deal 6 damage.", "Deal 6 damage. Draw 1 card."), "Deal 6 damage. Draw 1 card.", "new wording falls back to the new text")
	eq(CardView.diff_text("Gain 5 Firewall.", "Gain 5 Firewall."), "Gain 5 Firewall.", "no change, no arrow")
