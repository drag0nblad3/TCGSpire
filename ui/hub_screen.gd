class_name HubScreen
extends Control
## Home screen between runs: level, stats, heat choice, collection and packs.

signal start_pressed(heat: int)
signal collection_pressed
signal packs_pressed
signal theme_pressed
signal rig_pressed

var db: CardDB
var profile: Profile
var heat := 0
var _heat_label: Label
var _heat_desc: Label


func setup(db_in: CardDB, p: Profile) -> HubScreen:
	db = db_in
	profile = p
	heat = p.max_heat
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parts := UiKit.screen(22)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(170, 170)
	logo.draw.connect(func() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		Sigil.draw(logo, logo.size / 2, 70.0, "tcg-spire-logo", Palette.ENERGY, t)
		logo.queue_redraw())
	v.add_child(logo)
	if Palette.FRAME == "circuit":
		v.add_child(GlitchTitle.new().setup(Palette.w("title"), 38))
	else:
		v.add_child(UiKit.label(Palette.w("title"), 40, Palette.TEXT))
	if Palette.w("tagline") != "":
		v.add_child(UiKit.label(Palette.w("tagline"), 15, Palette.TEXT_DIM, true))
	var lvl := profile.level()
	var have := profile.xp - Profile.xp_for_level(lvl)
	var need := Profile.xp_for_level(lvl + 1) - Profile.xp_for_level(lvl)
	v.add_child(UiKit.label(("Level %d (max)" % lvl) if lvl >= Profile.LEVEL_CAP else ("Level %d   ·   XP %d / %d" % [lvl, have, need]), 18, Palette.ENERGY))
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(400, 14)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.max_value = need
	bar.value = have
	v.add_child(bar)
	var s := profile.stats
	v.add_child(UiKit.label("Runs %d   Wins %d   Best floor %d   Cards %d   %s %d" % [
		int(s.get("runs", 0)), int(s.get("wins", 0)), int(s.get("best_floor", 0)),
		profile.collection.owned_ids().size(), Palette.w("dust"), profile.collection.dust], 15, Palette.TEXT_DIM))
	var reps := UiKit.flow(12)
	for f in Jobs.board(db):
		var rep := UiKit.hbox(5)
		rep.add_child(Symbols.badge(f, 28))
		rep.add_child(UiKit.label("%s %d" % [Jobs.rep_name(db, f), profile.rep_of(f)], 14, Palette.faction(f)))
		reps.add_child(rep)
	v.add_child(reps)

	var heat_row := UiKit.hbox(16)
	heat_row.add_child(UiKit.button("<", func() -> void: _set_heat(heat - 1), Vector2(56, 48)))
	_heat_label = UiKit.label("", 22, Palette.HP)
	_heat_label.custom_minimum_size.x = 140
	heat_row.add_child(_heat_label)
	heat_row.add_child(UiKit.button(">", func() -> void: _set_heat(heat + 1), Vector2(56, 48)))
	v.add_child(heat_row)
	_heat_desc = UiKit.label("", 14, Palette.TEXT_DIM, true)
	v.add_child(_heat_desc)
	_set_heat(heat)

	v.add_child(UiKit.button("Take a job", func() -> void: start_pressed.emit(heat), Vector2(300, 72), 24))
	v.add_child(UiKit.button("Program library", func() -> void: collection_pressed.emit(), Vector2(300, 60)))
	var pk := UiKit.button("Open %s (%d)" % [Palette.w("packs").to_lower(), profile.packs_unopened], func() -> void: packs_pressed.emit(), Vector2(300, 60))
	pk.disabled = profile.packs_unopened <= 0
	v.add_child(pk)
	v.add_child(UiKit.button("Rig upgrades", func() -> void: rig_pressed.emit(), Vector2(300, 60)))
	var row := UiKit.hbox(12)
	row.add_child(UiKit.button("How to play", func() -> void: Rules.open(self), Vector2(200, 52), 16))
	row.add_child(UiKit.button("Look: %s" % Themes.ALL[Palette.theme_id]["name"], func() -> void: theme_pressed.emit(), Vector2(300, 52), 16))
	v.add_child(row)


func _set_heat(h: int) -> void:
	heat = clampi(h, 0, mini(profile.max_heat, db.balance.get("heat", []).size()))
	_heat_label.text = "Heat %d" % heat
	var levels: Array = db.balance.get("heat", [])
	var lines: Array[String] = []
	for i in heat:
		lines.append(str(levels[i]["desc"]))
	_heat_desc.text = "No modifiers." if lines.is_empty() else " ".join(lines)
	if heat == profile.max_heat and heat < levels.size():
		_heat_desc.text += "\nBreach the final Core to unlock Heat %d." % (heat + 1)
