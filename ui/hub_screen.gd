class_name HubScreen
extends Control
## Home screen between runs: level, stats, heat choice, collection and packs.

signal start_pressed(heat: int)
signal collection_pressed
signal packs_pressed
signal menu_pressed
signal resume_pressed
signal abandon_pressed
signal rig_pressed
signal daily_pressed
signal records_pressed
signal tutorial_pressed

var db: CardDB
var profile: Profile
var heat := 0
## Summary of a saved run in progress ("" = none): shows Resume/Abandon instead of a new job.
var saved_run := ""
var _heat_label: Label
var _heat_desc: Label


func setup(db_in: CardDB, p: Profile, saved: String = "") -> HubScreen:
	db = db_in
	profile = p
	saved_run = saved
	heat = p.max_heat
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parts := UiKit.screen(14)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(140, 140)
	logo.draw.connect(func() -> void:
		var t := Time.get_ticks_msec() / 1000.0
		Sigil.draw(logo, logo.size / 2, 58.0, "tcg-spire-logo", Palette.ENERGY, t)
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
	var title := str(profile.settings.get("title", ""))
	if title != "":
		v.add_child(UiKit.label(_title_name(title), 16, Palette.UPGRADED))
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
	v.add_child(UiKit.label("Rep: each crew pays its own on its jobs. Spend it on rig upgrades and firmware.", 13, Palette.TEXT_DIM, true))

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

	if saved_run != "":
		v.add_child(UiKit.button("Resume run\n%s" % saved_run, func() -> void: resume_pressed.emit(), Vector2(300, 84), 20))
		v.add_child(UiKit.button("Abandon run", func() -> void: abandon_pressed.emit(), Vector2(300, 48), 16))
	else:
		if first_time():
			var tut := UiKit.button("New here? Play the tutorial", func() -> void: tutorial_pressed.emit(), Vector2(300, 64), 18)
			tut.add_theme_color_override("font_color", Palette.UPGRADED)
			v.add_child(tut)
		v.add_child(UiKit.button("Take a job\nStart a new run", func() -> void: start_pressed.emit(heat), Vector2(300, 88), 22))
	if saved_run == "":
		var d := Records.daily(db, Records.today())
		var done: bool = str(profile.daily.get("last", "")) == d["date"]
		var today_score := int(profile.daily.get("scores", {}).get(d["date"], 0))
		var db_btn := UiKit.button(("Daily breach done · score %d\nA new one opens tomorrow" % today_score) if done else ("Daily breach: %s job · Heat %d\nDaily challenge run, one try" % [Lexicon.faction(d["job"]), d["heat"]]),
			func() -> void: daily_pressed.emit(), Vector2(300, 68), 16)
		db_btn.disabled = done
		v.add_child(db_btn)
	v.add_child(_collector_panel())
	var rig_row := UiKit.hbox(12)
	rig_row.add_child(UiKit.button("Rig upgrades\nPermanent bonuses", func() -> void: rig_pressed.emit(), Vector2(200, 68), 16))
	rig_row.add_child(UiKit.button("Records\nStats and sets", func() -> void: records_pressed.emit(), Vector2(200, 68), 16))
	v.add_child(rig_row)
	var row := UiKit.hbox(12)
	row.add_child(UiKit.button("Tutorial", func() -> void: tutorial_pressed.emit(), Vector2(130, 52), 16))
	row.add_child(UiKit.button("Rules", func() -> void: Rules.open(self), Vector2(130, 52), 16))
	row.add_child(UiKit.button("Menu", func() -> void: menu_pressed.emit(), Vector2(130, 52), 16))
	v.add_child(row)


## No finished tutorial and no runs yet: the hub offers the tutorial first.
func first_time() -> bool:
	return not bool(profile.settings.get("tutorial_done", false)) and int(profile.stats.get("runs", 0)) == 0


## Collecting front and center: packs, shards, library progress, upgrades waiting, the next binder.
func _collector_panel() -> Control:
	var box := UiKit.vbox(6)
	var lib := CollectionScreen.library_progress(db, profile)
	var ready := profile.ready_to_flash(db).size()
	var pk := UiKit.button("Open %s (%d)\nCard packs · shards %d / %d" % [Palette.w("packs").to_lower(), profile.packs_unopened, profile.pack_shards, Profile.shards_per_pack(db)],
		func() -> void: packs_pressed.emit(), Vector2(300, 72), 20)
	pk.disabled = profile.packs_unopened <= 0
	box.add_child(pk)
	var extra: Array[String] = []
	if not profile.unseen.is_empty():
		extra.append("%d NEW" % profile.unseen.size())
	if ready > 0:
		extra.append("%d ready to flash" % ready)
	var lib_b := UiKit.button("Program library %d / %d\n%s" % [lib[0], lib[1], " · ".join(extra) if not extra.is_empty() else "Your cards: browse, craft, upgrade"],
		func() -> void: collection_pressed.emit(), Vector2(300, 72), 18)
	if not profile.unseen.is_empty():
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			lib_b.add_theme_color_override(state, Palette.UPGRADED)
	box.add_child(lib_b)
	var goal := _next_binder()
	var lines: Array[String] = ["Rare within %d %s · mythic within %d" % [Packs.pity_left(db, profile, "rare"), Palette.w("packs").to_lower(), Packs.pity_left(db, profile, "mythic")]]
	if goal != "":
		lines.append(goal)
	box.add_child(UiKit.label("\n".join(lines), 14, Palette.UPGRADED, true))
	return box


## The unclaimed binder page closest to done: "Next binder: Burner rares 3 / 4".
func _next_binder() -> String:
	var best := ""
	var best_left := 999
	for f in Jobs.board(db) + ["neutral"]:
		for page in Records.binder(db, profile, f):
			if page["claimed"] or int(page["need"]) <= 0:
				continue
			var left := int(page["need"]) - int(page["have"])
			if left < best_left:
				best_left = left
				best = "Next binder: %s %s %d / %d" % [Lexicon.faction(f), str(page["name"]).to_lower(), int(page["have"]), int(page["need"])]
	return best


## Titles are either a crew title (binders) or an Exploit log id.
func _title_name(t: String) -> String:
	return str(db.exploits[t]["name"]) if db.exploits.has(t) else t


func _set_heat(h: int) -> void:
	heat = clampi(h, 0, mini(profile.max_heat, db.balance.get("heat", []).size()))
	_heat_label.text = "Heat %d" % heat
	var levels: Array = db.balance.get("heat", [])
	var lines: Array[String] = []
	for i in heat:
		lines.append(str(levels[i]["desc"]))
	_heat_desc.text = "Heat is difficulty. " + ("Heat 0 has no extra modifiers." if lines.is_empty() else " ".join(lines))
	if heat == profile.max_heat and heat < levels.size():
		_heat_desc.text += "\nBreach the final Core to unlock Heat %d." % (heat + 1)
