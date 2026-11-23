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
	# Sections get a small gap that grows to share any spare screen height.
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sections: Array[Control] = [_run_box(), _main_actions()]
	if saved_run == "":
		sections.append(_challenges())
	sections.append(_login_panel())
	sections.append(_stats_box())
	for sec in sections:
		v.add_child(_gap())
		v.add_child(sec)
	# A solid strip with a top rule, so content scrolling under the tabs reads as cut off by the bar
	# rather than overlapped by it.
	var strip := UiKit.panel(_tab_bar(), Color(Palette.PANEL_BG, 0.98))
	var sb: StyleBoxFlat = strip.get_theme_stylebox("panel")
	sb.set_content_margin_all(6)
	sb.border_width_top = 2
	sb.border_color = Color(Palette.ENERGY, 0.35)
	outer.add_child(strip)


## Flexible spacer between hub sections: at least 10 px, takes a share of leftover height.
func _gap() -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = 10
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## The soft box around everything that starts a run: heat, the run buttons and the payout fold.
func _run_box() -> Control:
	var box := UiKit.vbox(12)
	var heat_row := UiKit.hbox(16)
	heat_row.alignment = BoxContainer.ALIGNMENT_CENTER
	heat_row.add_child(UiKit.button("<", func() -> void: _set_heat(heat - 1), Vector2(56, 48)))
	_heat_label = UiKit.label("", 22, Palette.HP)
	_heat_label.custom_minimum_size.x = 140
	heat_row.add_child(_heat_label)
	heat_row.add_child(UiKit.button(">", func() -> void: _set_heat(heat + 1), Vector2(56, 48)))
	box.add_child(heat_row)
	_heat_desc = UiKit.label("", 16, Palette.TEXT_DIM, true)
	_heat_desc.custom_minimum_size.x = 600
	box.add_child(_heat_desc)
	if saved_run != "":
		box.add_child(UiKit.primary(UiKit.button("Resume run\n%s" % saved_run, func() -> void: resume_pressed.emit(), Vector2(420, 96), 22)))
		box.add_child(UiKit.button("Abandon run", func() -> void: abandon_pressed.emit(), Vector2(300, 48), 16))
	else:
		if first_time():
			var tut := UiKit.button("New here? Play the tutorial", func() -> void: tutorial_pressed.emit(), Vector2(300, 64), 18)
			tut.add_theme_color_override("font_color", Palette.UPGRADED)
			box.add_child(tut)
		box.add_child(UiKit.primary(UiKit.button("Take a job\nStart a new run", func() -> void: start_pressed.emit(heat), Vector2(420, 104), 26)))
		# Payout details fold away behind a button; the hub stays scannable.
		_rewards_label = UiKit.label("", 16, Palette.TEXT, true)
		_rewards_label.custom_minimum_size.x = 600
		var pays_box := UiKit.panel(_rewards_label)
		pays_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pays_box.visible = false
		var pays := UiKit.button("What a run pays  ?", func() -> void: pass, Vector2(240, 44), 16)
		pays.pressed.connect(func() -> void:
			pays_box.visible = not pays_box.visible
			pays.text = "Hide payouts" if pays_box.visible else "What a run pays  ?")
		box.add_child(pays)
		box.add_child(pays_box)
	_set_heat(heat)
	return _soft_box(box)


## Caches and Rig: the two places that grow your account, each with a line on what it does.
func _main_actions() -> Control:
	var row := UiKit.hbox(12)
	var n := profile.packs_unopened
	var cache_lines: Array[String] = []
	cache_lines.append(("%d unopened · shards %d / %d" % [n, profile.pack_shards, Profile.shards_per_pack(db)]) if n > 0 else "None unopened. Runs, levels and login days pay more.")
	cache_lines.append(PackArt.odds_line(db, profile, Packs.NORMAL))
	var goal := _next_binder()
	if goal != "":
		cache_lines.append(goal)
	var caches := _action("Open caches" if n > 0 else "Caches", str(n) if n > 0 else "", "\n".join(cache_lines), packs_pressed, n > 0, n > 0)
	var rig_lines := "Permanent upgrades for every run, bought with crew rep. You have %d rep in all." % _total_rep()
	var rig := _action("Rig upgrades", "", rig_lines, rig_pressed, true, false)
	row.add_child(caches)
	row.add_child(rig)
	return row


## One main-area button with its explanation under it, in a soft box half the row wide.
func _action(text: String, badge: String, info: String, sig: Signal, enabled: bool, glow: bool) -> Control:
	var col := UiKit.vbox(8, BoxContainer.ALIGNMENT_BEGIN)
	var b := UiKit.button(text + ("\n%s ready" % badge if badge != "" else ""), func() -> void: sig.emit(), Vector2(0, 80), 20)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = not enabled
	if glow:
		for state in ["font_color", "font_hover_color", "font_focus_color"]:
			b.add_theme_color_override(state, Palette.UPGRADED)
	col.add_child(b)
	var l := UiKit.label(info, 16, Palette.TEXT_DIM, true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 0
	col.add_child(l)
	var box := _soft_box(col)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_stretch_ratio = 1.0
	return box


## Daily breach and weekly challenge, side by side.
func _challenges() -> Control:
	var d := Records.daily(db, Records.today())
	var done: bool = str(profile.daily.get("last", "")) == d["date"]
	var today_score := int(profile.daily.get("scores", {}).get(d["date"], 0))
	var db_btn := UiKit.button(("Daily breach done · score %d\nA new one opens tomorrow" % today_score) if done else ("Daily breach: %s job · Heat %d\nDaily challenge run, one try" % [Lexicon.faction(d["job"]), d["heat"]]),
		func() -> void: daily_pressed.emit(), Vector2(300, 68), 16)
	db_btn.disabled = done
	var w := Weekly.challenge(db, Weekly.this_week())
	var ws := Weekly.state(profile, w["week"])
	var wk_btn := UiKit.button(("Weekly challenge cleared · best %d\nPlay again for score · new in %dd" % [int(ws["best"]), Weekly.days_left(Records.today())]) if ws["cleared"] \
		else ("Weekly challenge: Heat %d\n%d rule changes · your cards, no upgrades" % [w["heat"], w["mods"].size()]),
		func() -> void: weekly_pressed.emit(), Vector2(300, 68), 16)
	var ch_row := UiKit.hbox(12)
	for b in [db_btn, wk_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ch_row.add_child(b)
	return ch_row


## Resources and stats, tucked in a quiet box near the bottom.
func _stats_box() -> Control:
	var box := UiKit.vbox(8)
	var s := profile.stats
	box.add_child(UiKit.label("Runs %d   Wins %d   Best floor %d   Cards %d   %s %d" % [
		int(s.get("runs", 0)), int(s.get("wins", 0)), int(s.get("best_floor", 0)),
		profile.collection.owned_ids().size(), Palette.w("dust"), profile.collection.dust], 16, Palette.TEXT_DIM))
	if Records.deep_unlocked(db, profile):
		box.add_child(UiKit.label("Deep Stack open: keep going after the final Core  ·  Best depth %d" % int(s.get("best_depth", 0)), 16, Palette.UPGRADED))
	var reps := UiKit.flow(12)
	for f in Jobs.board(db):
		var rep := UiKit.hbox(5)
		rep.add_child(Symbols.badge(f, 24))
		rep.add_child(UiKit.label("%s %d" % [Jobs.rep_name(db, f), profile.rep_of(f)], 16, Palette.faction(f)))
		reps.add_child(rep)
	box.add_child(reps)
	return _soft_box(box)


func _total_rep() -> int:
	var t := 0
	for f in Jobs.board(db):
		t += profile.rep_of(f)
	return t


## Soft panel: translucent fill, rounded, faint border in the energy color.
func _soft_box(child: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.PANEL_BG, 0.55)
	sb.border_color = Color(Palette.ENERGY, 0.25)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(maxi(Palette.RADIUS, 12) + 6)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(child)
	return p


## Bottom tab bar: the other places you go between runs (Caches and Rig sit in the main area). Menu holds Settings, Rules and the tutorial.
func _tab_bar() -> Control:
	var bar := UiKit.hbox(6)
	var ready := profile.ready_to_flash(db).size()
	var lib := CollectionScreen.library_progress(db, profile)
	var tabs := [
		["Library", ("%d NEW" % profile.unseen.size()) if not profile.unseen.is_empty() else (("%d ready" % ready) if ready > 0 else "%d/%d" % lib), collection_pressed, true, not profile.unseen.is_empty() or ready > 0],
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
	var lines: Array[String] = ["Full clear: %s · +%d %s · +%d XP%s" % [cache_text(db, pay), pay["rep"], rep, pay["xp"], scrap_text(pay)]]
	if int(pay.get("first_clear", 0)) > 0:
		lines.append(first_clear_text(db, pay, heat))
	if int(pay["shards_per_elite"]) > 0:
		lines.append("Each black sentry (elite): +%d %s shard (%d make one) · +%d %s · +%d XP" % [pay["shards_per_elite"], Palette.w("pack").to_lower(),
			pay["shards_per_pack"], pay["elite_rep"], rep, pay["elite_xp"]])
	return lines


## Hub summary of what a run pays at the chosen heat (rep goes to the crew you work for).
func _rewards_text() -> String:
	var pay := Jobs.payout_preview(db, profile, Jobs.board(db)[0], heat)
	var lines: Array[String] = [
		"Clear all %d layers at Heat %d: %s, +%d rep for your client crew, +%d XP%s." % [int(db.balance.get("acts", 3)), heat, cache_text(db, pay, false), pay["rep"], pay["xp"], scrap_text(pay, ", ")],
		"Each Core (boss) you breach: +%d crew cache of your client crew, kept even if you lose later. Rep and XP pay for every floor you clear." % int(pay["per_core"])]
	if int(pay.get("full_run", 0)) > 0:
		lines.append("Finish the whole job: +%d %s, the premium cache (rare or better every time)." % [int(pay["full_run"]), PackArt.title(db, Packs.PREMIUM)])
	if int(pay.get("first_clear", 0)) > 0:
		lines.append(first_clear_text(db, pay, heat) + ".")
	if heat > 0:
		lines.append("Heat %d bonus: %s." % [heat, heat_bonus_text(db, heat)])
	if int(pay["shards_per_elite"]) > 0:
		lines.append("Each black sentry (elite fight): +%d %s shard (%d make one), +%d rep, +%d XP." % [pay["shards_per_elite"], Palette.w("pack").to_lower(), pay["shards_per_pack"], pay["elite_rep"], pay["elite_xp"]])
	var bonus: Array = db.contracts.keys().map(func(id: String) -> int: return Records.clause_rep(db, id, heat))
	if not bonus.is_empty():
		lines.append("Job bonuses: %d per job, +%d to +%d rep each if you meet them." % [int(db.balance.get("contracts", {}).get("per_job", 2)), bonus.min(), bonus.max()])
	var nxt := profile.next_level_reward(db)
	if not nxt.is_empty():
		lines.append("Next level (%d): %s, +%d %s." % [nxt["level"], count(nxt["packs"], "pack", "packs"), nxt["dust"], Palette.w("dust").to_lower()])
	return "\n".join(lines)


## " · +60 scrap" (or with another separator) when a full clear pays heat scrap.
static func scrap_text(pay: Dictionary, sep: String = " · ") -> String:
	var n := int(pay.get("heat_scrap", 0))
	return "" if n <= 0 else "%s+%d %s" % [sep, n, Palette.w("dust").to_lower()]


## "First clear at Heat 3: +2 Zero-day caches, once".
static func first_clear_text(db_in: CardDB, pay: Dictionary, h: int) -> String:
	var n := int(pay.get("first_clear", 0))
	return "First clear at Heat %d: +%d %s%s, once" % [h, n, PackArt.title(db_in, Packs.PREMIUM), "" if n == 1 else "s"]


## What heat adds to the pay: "+45% rep and XP, +30 scrap per Core breached" (balance.heat_rewards).
static func heat_bonus_text(db_in: CardDB, h: int) -> String:
	var bits: Array[String] = []
	var pct := roundi((Profile.heat_pay_mult(db_in, h) - 1.0) * 100.0)
	if pct > 0:
		bits.append("+%d%% rep and XP" % pct)
	var scrap := Profile.heat_scrap_per_core(db_in, h)
	if scrap > 0:
		bits.append("+%d %s per Core breached" % [scrap, Palette.w("dust").to_lower()])
	return ", ".join(bits)


func _set_heat(h: int) -> void:
	var levels: Array = db.balance.get("heat", [])
	heat = clampi(h, 0, mini(profile.max_heat, levels.size()))
	_heat_label.text = "Heat %d" % heat
	if heat == 0:
		_heat_desc.text = "Heat is difficulty. Heat 0 has no extra modifiers."
	else:
		var total := heat_total(db, heat)
		_heat_desc.text = "Heat %d in total: %s." % [heat, total[0].to_upper() + total.substr(1)]
		var bonus := heat_bonus_text(db, heat)
		if bonus != "":
			_heat_desc.text += "\nPays more: %s." % bonus
	if heat == profile.max_heat and heat < levels.size():
		var prem := Profile.first_clear_premium(db, heat)
		_heat_desc.text += "\nBreach the final Core to unlock Heat %d%s." % [heat + 1,
			"" if prem <= 0 else " and win +%d %s%s" % [prem, PackArt.title(db, Packs.PREMIUM), "" if prem == 1 else "s"]]
	if _rewards_label != null:
		_rewards_label.text = _rewards_text()


## Every heat level up to `h` stacked: "enemies +73% HP and +73% damage, safehouses repair 30% less, ...".
## HP/damage compound like RunState.heat_mult; the rest add up like RunState.heat_mod.
static func heat_total(db_in: CardDB, h: int) -> String:
	var levels: Array = db_in.balance.get("heat", [])
	var hp := 1.0
	var dmg := 1.0
	var sums := {}
	for i in mini(h, levels.size()):
		var mods: Dictionary = levels[i].get("mods", {})
		hp *= 1.0 + float(mods.get("enemy_hp_pct", 0.0))
		dmg *= 1.0 + float(mods.get("enemy_dmg_pct", 0.0))
		for k in mods:
			if k not in ["enemy_hp_pct", "enemy_dmg_pct"]:
				sums[k] = float(sums.get(k, 0.0)) + float(mods[k])
	var bits: Array[String] = []
	if hp != 1.0 or dmg != 1.0:
		bits.append("enemies +%d%% HP and +%d%% damage" % [roundi((hp - 1.0) * 100.0), roundi((dmg - 1.0) * 100.0)])
	if float(sums.get("enemy_might", 0.0)) > 0.0:
		bits.append("enemy hits +%d" % int(sums["enemy_might"]))
	if float(sums.get("rest_heal_pct", 0.0)) < 0.0:
		bits.append("safehouses repair %d%% less" % roundi(-float(sums["rest_heal_pct"]) * 100.0))
	var extra := int(sums.get("extra_targets", 0.0))
	if extra > 0:
		bits.append("jobs run against %d more crew%s" % [extra, "" if extra == 1 else "s"])
	if float(sums.get("double_cross", 0.0)) > 0.0:
		bits.append("your client double-crosses you in the last layer")
	return ", ".join(bits)
