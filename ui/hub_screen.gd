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
signal weekly_pressed
signal login_pressed
signal records_pressed
signal tutorial_pressed

var db: CardDB
var profile: Profile
var heat := 0
## Summary of a saved run in progress ("" = none): shows Resume/Abandon instead of a new job.
var saved_run := ""
var _heat_label: Label
var _heat_desc: Label
var _rewards_label: Label


func setup(db_in: CardDB, p: Profile, saved: String = "") -> HubScreen:
	db = db_in
	profile = p
	saved_run = saved
	heat = p.max_heat
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parts := UiKit.screen(10, BoxContainer.ALIGNMENT_BEGIN)
	add_child(parts[0])
	var outer: VBoxContainer = parts[1]
	# Everything scrolls except the tab bar pinned to the bottom.
	var v := UiKit.scroll(outer)
	v.add_theme_constant_override("separation", 14)
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(120, 120)
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
	if Records.deep_unlocked(db, profile):
		v.add_child(UiKit.label("Deep Stack open: keep going after the final Core  ·  Best depth %d" % int(s.get("best_depth", 0)), 14, Palette.UPGRADED))
	var reps := UiKit.flow(12)
	for f in Jobs.board(db):
		var rep := UiKit.hbox(5)
		rep.add_child(Symbols.badge(f, 28))
		rep.add_child(UiKit.label("%s %d" % [Jobs.rep_name(db, f), profile.rep_of(f)], 14, Palette.faction(f)))
		reps.add_child(rep)
	v.add_child(reps)
	v.add_child(_login_panel())

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
		v.add_child(UiKit.primary(UiKit.button("Resume run\n%s" % saved_run, func() -> void: resume_pressed.emit(), Vector2(420, 96), 22)))
		v.add_child(UiKit.button("Abandon run", func() -> void: abandon_pressed.emit(), Vector2(300, 48), 16))
	else:
		if first_time():
			var tut := UiKit.button("New here? Play the tutorial", func() -> void: tutorial_pressed.emit(), Vector2(300, 64), 18)
			tut.add_theme_color_override("font_color", Palette.UPGRADED)
			v.add_child(tut)
		v.add_child(UiKit.primary(UiKit.button("Take a job\nStart a new run", func() -> void: start_pressed.emit(heat), Vector2(420, 104), 26)))
		# Payout details fold away behind a button; the hub stays scannable.
		_rewards_label = UiKit.label("", 14, Palette.TEXT, true)
		_rewards_label.custom_minimum_size.x = 600
		var pays_box := UiKit.panel(_rewards_label)
		pays_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pays_box.visible = false
		var pays := UiKit.button("What a run pays  ?", func() -> void: pass, Vector2(240, 44), 15)
		pays.pressed.connect(func() -> void:
			pays_box.visible = not pays_box.visible
			pays.text = "Hide payouts" if pays_box.visible else "What a run pays  ?")
		v.add_child(pays)
		v.add_child(pays_box)
		_set_heat(heat)
	if saved_run == "":
		var d := Records.daily(db, Records.today())
		var done: bool = str(profile.daily.get("last", "")) == d["date"]
		var today_score := int(profile.daily.get("scores", {}).get(d["date"], 0))
		var db_btn := UiKit.button(("Daily breach done · score %d\nA new one opens tomorrow" % today_score) if done else ("Daily breach: %s job · Heat %d\nDaily challenge run, one try" % [Lexicon.faction(d["job"]), d["heat"]]),
			func() -> void: daily_pressed.emit(), Vector2(300, 68), 16)
		db_btn.disabled = done
		var w := Weekly.challenge(db, Weekly.this_week())
		var ws := Weekly.state(profile, w["week"])
		var wk_btn := UiKit.button(("Weekly challenge cleared · best %d
Play again for score · new in %dd" % [int(ws["best"]), Weekly.days_left(Records.today())]) if ws["cleared"] \
			else ("Weekly challenge: Heat %d
%d rule changes · your cards, no upgrades" % [w["heat"], w["mods"].size()]),
			func() -> void: weekly_pressed.emit(), Vector2(300, 68), 16)
		var ch_row := UiKit.hbox(12)
		db_btn.custom_minimum_size = Vector2(300, 68)
		ch_row.add_child(db_btn)
		ch_row.add_child(wk_btn)
		v.add_child(ch_row)
	v.add_child(_collector_hints())
	outer.add_child(_tab_bar())


## Bottom tab bar: the places you go between runs. Menu holds Settings, Rules and the tutorial.
func _tab_bar() -> Control:
	var bar := UiKit.hbox(6)
	var ready := profile.ready_to_flash(db).size()
	var lib := CollectionScreen.library_progress(db, profile)
	var tabs := [
		["Caches", str(profile.packs_unopened) if profile.packs_unopened > 0 else "none", packs_pressed, profile.packs_unopened > 0, profile.packs_unopened > 0],
		["Library", ("%d NEW" % profile.unseen.size()) if not profile.unseen.is_empty() else (("%d ready" % ready) if ready > 0 else "%d/%d" % lib), collection_pressed, true, not profile.unseen.is_empty() or ready > 0],
		["Rig", "upgrades", rig_pressed, true, false],
		["Records", "sets", records_pressed, true, false],
		["Menu", "more", menu_pressed, true, false],
	]
	for t in tabs:
		var b := UiKit.button("%s\n%s" % [t[0], t[1]], func() -> void: (t[2] as Signal).emit(), Vector2(128, 70), 16)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.disabled = not t[3]
		if t[4]:
			for state in ["font_color", "font_hover_color", "font_focus_color"]:
				b.add_theme_color_override(state, Palette.UPGRADED)
		bar.add_child(b)
	return bar


## Daily login bonus: the 7-day track (claimed, today, ahead) and a Claim button while today's is open.
func _login_panel() -> Control:
	var open := LoginBonus.can_claim(profile, Records.today())
	var next := LoginBonus.next_day(profile)
	# Today's cycle day: the one waiting to be claimed, or the one already claimed today.
	var today_day := next if open else int(profile.login.get("day", 0))
	var box := UiKit.vbox(8)
	box.add_child(UiKit.label("Daily login bonus · day %d of %d" % [today_day, LoginBonus.CYCLE], 17, Palette.ENERGY))
	var track := UiKit.hbox(6)
	track.alignment = BoxContainer.ALIGNMENT_CENTER
	for day in range(1, LoginBonus.CYCLE + 1):
		var r := LoginBonus.reward(db, day)
		var done := day < today_day or (day == today_day and not open)
		var now := day == today_day and open
		var reward := ("+%d" % r["scrap"]) if int(r["scrap"]) > 0 else ""
		for k in r["packs"]:
			reward += ("\n" if reward != "" else "") + ("Zero-day" if k == Packs.PREMIUM else "cache")
		var cell := UiKit.label("Day %d\n%s" % [day, "done" if done else reward], 13,
			Palette.UPGRADED if done else (Palette.ENERGY if now else Palette.TEXT_DIM))
		cell.custom_minimum_size = Vector2(54, 0)
		track.add_child(UiKit.panel(cell, Palette.BUTTON if now else Palette.PANEL_BG))
	box.add_child(track)
	if open:
		var b := UiKit.button("Claim day %d: %s" % [next, LoginBonus.reward_text(db, next)], func() -> void: login_pressed.emit(), Vector2(300, 56), 18)
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			b.add_theme_color_override(state, Palette.UPGRADED)
		box.add_child(b)
	else:
		box.add_child(UiKit.label("Claimed today. Tomorrow: day %d, %s. Missing a day never resets the track." % [next, LoginBonus.reward_text(db, next)], 13, Palette.TEXT_DIM, true))
	return box


## No finished tutorial and no runs yet: the hub offers the tutorial first.
func first_time() -> bool:
	return not bool(profile.settings.get("tutorial_done", false)) and int(profile.stats.get("runs", 0)) == 0


## Collecting hints under the challenges: cache odds and the next binder (the buttons live in the tab bar).
func _collector_hints() -> Control:
	var lines: Array[String] = []
	if profile.packs_unopened > 0:
		lines.append("%d unopened %s · shards %d / %d" % [profile.packs_unopened, Palette.w("packs").to_lower(), profile.pack_shards, Profile.shards_per_pack(db)])
	lines.append(PackArt.odds_line(db, profile, Packs.NORMAL))
	var goal := _next_binder()
	if goal != "":
		lines.append(goal)
	return UiKit.label("\n".join(lines), 14, Palette.UPGRADED, true)


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


## "+4 data caches", "+1 data cache".
static func count(n: int, one: String, many: String) -> String:
	return "+%d %s" % [n, Palette.w(one).to_lower() if n == 1 else Palette.w(many).to_lower()]


## "+3 crew caches, +1 Zero-day cache" for a full clear.
static func cache_text(db_in: CardDB, pay: Dictionary, name_crew: bool = true) -> String:
	var kinds: Array = pay.get("pack_list", [])
	var crew := kinds.filter(func(k: String) -> bool: return Packs.crew_of(k) != "").size()
	var bits: Array[String] = []
	if crew > 0:
		bits.append("+%d %s%s" % [crew, PackArt.title(db_in, kinds[0]) if name_crew else "client crew cache", "" if crew == 1 else "s"])
	var prem := kinds.count(Packs.PREMIUM)
	if prem > 0:
		bits.append("+%d %s" % [prem, PackArt.title(db_in, Packs.PREMIUM)])
	var normal := kinds.count(Packs.NORMAL)
	if normal > 0:
		bits.append(count(normal, "pack", "packs"))
	return ", ".join(bits)


## Job board lines for what one job pays, every amount with its unit.
static func payout_lines(db: CardDB, p: Profile, job: String, heat: int, extra: int) -> Array[String]:
	var pay := Jobs.payout_preview(db, p, job, heat, extra)
	var rep := Jobs.rep_name(db, job)
	var lines: Array[String] = ["Full clear: %s · +%d %s · +%d XP" % [cache_text(db, pay), pay["rep"], rep, pay["xp"]]]
	if int(pay["shards_per_elite"]) > 0:
		lines.append("Each black sentry (elite): +%d %s shard (%d make one) · +%d %s · +%d XP" % [pay["shards_per_elite"], Palette.w("pack").to_lower(),
			pay["shards_per_pack"], pay["elite_rep"], rep, pay["elite_xp"]])
	return lines


## Hub summary of what a run pays at the chosen heat (rep goes to the crew you work for).
func _rewards_text() -> String:
	var pay := Jobs.payout_preview(db, profile, Jobs.board(db)[0], heat)
	var lines: Array[String] = [
		"Clear all %d layers at Heat %d: %s, +%d rep for your client crew, +%d XP." % [int(db.balance.get("acts", 3)), heat, cache_text(db, pay, false), pay["rep"], pay["xp"]],
		"Each Core (boss) you breach: +%d crew cache of your client crew, kept even if you lose later. Rep and XP pay for every floor you clear." % int(pay["per_core"])]
	if int(pay.get("full_run", 0)) > 0:
		lines.append("Finish the whole job: +%d %s, the premium cache (rare or better every time)." % [int(pay["full_run"]), PackArt.title(db, Packs.PREMIUM)])
	if int(pay["shards_per_elite"]) > 0:
		lines.append("Each black sentry (elite fight): +%d %s shard (%d make one), +%d rep, +%d XP." % [pay["shards_per_elite"], Palette.w("pack").to_lower(), pay["shards_per_pack"], pay["elite_rep"], pay["elite_xp"]])
	var bonus: Array = db.contracts.keys().map(func(id: String) -> int: return Records.clause_rep(db, id, heat))
	if not bonus.is_empty():
		lines.append("Job bonuses: %d per job, +%d to +%d rep each if you meet them." % [int(db.balance.get("contracts", {}).get("per_job", 2)), bonus.min(), bonus.max()])
	var nxt := profile.next_level_reward(db)
	if not nxt.is_empty():
		lines.append("Next level (%d): %s, +%d %s." % [nxt["level"], count(nxt["packs"], "pack", "packs"), nxt["dust"], Palette.w("dust").to_lower()])
	return "\n".join(lines)


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
	if _rewards_label != null:
		_rewards_label.text = _rewards_text()
