extends Control
## App shell: owns the Profile and the current RunState and swaps screens.
## Flow: Hub -> deck picker -> Map -> node screen (fight/rest/shop/event/
## treasure) -> Map ... -> boss -> run summary -> Hub. Packs open from the Hub.

const BACKDROP := preload("res://shaders/backdrop.gdshader")

var db: CardDB
var profile: Profile
var run: RunState
var _screen: Control
var _combat: Combat
var _bg_mat: ShaderMaterial
var _glass_pulse: Tween
## Screenshot/smoke tools turn this off so they never touch the real save.
var persist := true
var run_save_path := RunSave.DEFAULT_PATH
## Where a resumed run picks up (see RunSave); "node" = the node screen restarts.
var _resume: Dictionary = {}
var _menu_btn: Button
## Combat animation speed multiplier (settings "anim_speed"; lower = faster).
const ANIM_SPEEDS := [[1.0, "Normal"], [0.6, "Fast"], [0.3, "Very fast"]]


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = BACKDROP
	bg.material = _bg_mat
	add_child(bg)
	db = CardDB.shared()
	profile = Profile.load_or_new(db)
	var audio := GameAudio.new()
	add_child(audio)
	audio.configure(profile.settings)
	var music := GameMusic.new()
	add_child(music)
	music.configure(profile.settings)
	Palette.apply_access(profile.settings)
	apply_theme(str(profile.settings.get("theme", Themes.DEFAULT)))
	_menu_btn = UiKit.button("Menu", _open_menu, Vector2(84, 40), 15)
	_menu_btn.visible = false
	add_child(_menu_btn)
	show_hub()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()


## Android back button (quit_on_go_back is off): closes the top overlay, else steps back
## one screen. In a run it opens the pause menu; on the hub it asks before quitting.
func go_back() -> void:
	if _close_top_overlay():
		return
	if _screen is CombatScreen:
		if run != null:
			_open_menu()
		return
	if run != null and not run.over:
		_open_menu()
	elif _screen is HubScreen:
		get_tree().root.add_child(GameMenu.new().setup("Quit TCG Spire?", [
			["!Quit", func() -> void: get_tree().quit()],
			["Stay", null]]))
	elif run != null and run.over:
		return  # the end-of-run screen has its own Continue button
	else:
		show_hub()


## Closes the newest overlay: anything on the root above Main, a DeckOverlay picker
## inside Main, or a screen's own detail panel (meta "back_overlay"). False if none.
func _close_top_overlay() -> bool:
	var root := get_tree().root
	for i in range(root.get_child_count() - 1, -1, -1):
		var n := root.get_child(i)
		if n == self:
			break
		if n is Control and (n as Control).visible and not n.is_queued_for_deletion():
			_close_overlay(n)
			return true
	for i in range(get_child_count() - 1, -1, -1):
		var n := get_child(i)
		if n == _screen:
			break
		if n is DeckOverlay and not n.is_queued_for_deletion():
			_close_overlay(n)
			return true
	if _screen != null:
		for i in range(_screen.get_child_count() - 1, -1, -1):
			var n := _screen.get_child(i)
			if n.has_meta("back_overlay") and not n.is_queued_for_deletion():
				n.queue_free()
				return true
	return false


func _close_overlay(n: Node) -> void:
	if n.has_method("back"):
		n.call("back")
	else:
		n.queue_free()


## Restyles everything: colors, fonts, frames, backdrop. Screens built after
## this call pick it up (call show_hub()/show_map() to rebuild the current one).
func apply_theme(id: String) -> void:
	Palette.apply(id)
	theme = Palette.make_theme()
	# Overlays (deck, rules, inspector) live on the root window, so theme it too.
	get_tree().root.theme = theme
	var b: Dictionary = Palette.BACKDROP
	_bg_mat.set_shader_parameter("style", b["style"])
	_bg_mat.set_shader_parameter("top_color", b["top"])
	_bg_mat.set_shader_parameter("bottom_color", b["bottom"])
	_bg_mat.set_shader_parameter("glow_color", b["glow"])
	_bg_mat.set_shader_parameter("glow2_color", b["glow2"])


## Frame cap: fights and pack openings run at 60 fps, menus and the map at 30 (phones with
## 90-120 Hz screens would otherwise draw every screen that fast). Battery saver: 30 fps
## everywhere and a still backdrop.
func _apply_power() -> void:
	var saver := bool(profile.settings.get("battery_saver", false))
	var smooth := _screen is CombatScreen or (_screen != null and _screen.has_meta("smooth"))
	Engine.max_fps = 30 if saver or not smooth else 60
	_bg_mat.set_shader_parameter("speed", 0.0 if saver else 1.0)


func _save() -> void:
	if persist:
		profile.save()


func _show(node: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = node
	GameMusic.mood("combat" if node is CombatScreen else ("map" if run != null and not run.over else "menu"))
	if _glass_pulse != null:
		_glass_pulse.kill()
		_glass_pulse = null
	_bg_mat.set_shader_parameter("boss_entrance", -1.0)
	_bg_mat.set_shader_parameter("glass_intensity", 1.45 if node is CombatScreen else 1.0)
	add_child(node)
	_apply_power()
	if _menu_btn != null:
		move_child(_menu_btn, -1)
		_menu_btn.position = UiKit.corner_pos(self, _menu_btn.custom_minimum_size.x)
		_menu_btn.visible = (run != null and not run.over) or _is_profile_cheat_screen(node)


## Writes the run in progress (and where to resume it) next to the profile.
func _save_run(resume: Dictionary) -> void:
	_resume = resume
	if persist and run != null and not run.over:
		RunSave.save(run, resume, run_save_path)


func anim_speed() -> float:
	var i := int(profile.settings.get("anim_speed", 0))
	return float(ANIM_SPEEDS[clampi(i, 0, ANIM_SPEEDS.size() - 1)][0])


# --- menu / settings / saved runs ---------------------------------------------------

func _is_profile_cheat_screen(node: Control) -> bool:
	return bool(profile.settings.get("cheats", false)) and (
		node is RigScreen or (node is CollectionScreen and not (node as CollectionScreen).pick_mode))


func _open_menu() -> void:
	if _screen is CombatScreen and ((_screen as CombatScreen).is_busy() or _combat.is_over()):
		return
	var active_run := run != null and not run.over
	var entries: Array = [["Resume" if active_run else "Close", null], ["Settings", _open_settings]]
	if _screen is HubScreen:
		entries.append(["Rules", func() -> void: Rules.open(_screen)])
		entries.append(["Tutorial", start_tutorial])
	var cheats := _cheat_entries()
	if not cheats.is_empty():
		entries.append(["Cheats", _open_cheats.bind(cheats)])
	var note := ""
	if active_run:
		if _resume.get("screen", "") == "node":
			note = "Quitting here resumes this fight at the start of your current turn." if _screen is CombatScreen else "Quitting here restarts this node when you resume."
		entries.append(["Save & quit to menu", func() -> void:
			run = null
			show_hub()])
		entries.append(["!Abandon run", func() -> void:
			get_tree().root.add_child(GameMenu.new().setup("Abandon this run?", [
				["!Yes, abandon it", func() -> void:
					run.over = true
					_end_run(true)],
				["No, keep going", null]], "It counts as a loss. You keep the XP and rewards earned so far."))])
	get_tree().root.add_child(GameMenu.new().setup("Paused" if active_run else "Menu", entries, note))


func _cheat_entries() -> Array:
	if not bool(profile.settings.get("cheats", false)):
		return []
	if _screen is CombatScreen:
		var fight := _screen as CombatScreen
		return [
			["Full heal", func() -> void:
				fight.cheat_full_heal()
				_save_run(_resume)],
			["Win fight", fight.cheat_win],
		]
	if _screen is HubScreen:
		return [
			["Collection cheats", _open_cheats.bind(_collection_cheats())],
			["Faction cheats", _open_cheats.bind(_faction_cheats())],
			["Add 10 packs", func() -> void:
				profile.packs_unopened += 10
				_profile_cheat_done("Added 10 packs.")],
		]
	if _screen is CollectionScreen and not (_screen as CollectionScreen).pick_mode:
		return _collection_cheats()
	if _screen is RigScreen:
		return _faction_cheats()
	if _screen is MapScreen and run != null and not run.over:
		return [
			["Full heal", func() -> void:
				run.hp = run.max_hp
				show_map()],
			["Add 500 creds", func() -> void:
				run.gold += 500
				show_map()],
		]
	return []


func _open_cheats(entries: Array) -> void:
	get_tree().root.add_child(GameMenu.new().setup("Cheats", entries + [["Back to menu", _open_menu]],
		"Testing actions affect your current save."))


func _collection_cheats() -> Array:
	return [
		["Gain all cards", func() -> void:
			for id in db.ids_where(func(c: CardDef) -> bool: return c.rarity not in ["starter", "curse"]):
				var missing := Profile.deck_limit(db) - profile.collection.count(id)
				if missing > 0:
					profile.collection.add(id, missing)
			_profile_cheat_done("All collectible cards are owned.")],
		["Max all owned cards", func() -> void:
			for id in profile.collection.owned_ids():
				var c := db.card(id)
				if c != null and c.rarity not in ["starter", "curse"]:
					profile.firmware[id] = Profile.firmware_max(db)
			_profile_cheat_done("Owned cards have maximum firmware.")],
		["Add 1,000 dust", func() -> void:
			profile.collection.dust += 1000
			_profile_cheat_done("Added 1,000 dust.")],
		["!Empty collection", _confirm_cheat.bind("Empty your collection?",
			"Removes owned cards, foils, firmware and saved loadouts. Base deck cards remain available.",
			func() -> void:
				profile.collection.counts.clear()
				profile.collection.foils.clear()
				profile.firmware.clear()
				profile.firmware_mods.clear()
				profile.unseen.clear()
				profile.last_picks.clear()
				profile.loadouts.clear()
				_profile_cheat_done("Collection emptied."))],
	]


func _faction_cheats() -> Array:
	return [
		["Add 500 rep per faction", func() -> void:
			for faction in db.factions:
				profile.rep[faction] = profile.rep_of(faction) + 500
			_profile_cheat_done("Added 500 rep per faction.")],
		["Max all faction bonuses", func() -> void:
			for id in Perks.ids(db, "rig"):
				profile.rig[id] = int(db.perks[id]["max_rank"])
			_profile_cheat_done("All rig bonuses and capstones maxed for future runs.")],
		["!Reset reputation", _confirm_cheat.bind("Reset reputation?",
			"Sets every faction’s spendable reputation to zero. Purchased rig bonuses stay active.",
			func() -> void:
				profile.rep.clear()
				_profile_cheat_done("Reputation reset."))],
	]


func _confirm_cheat(title: String, note: String, action: Callable) -> void:
	get_tree().root.add_child(GameMenu.new().setup(title, [
		["!Confirm", action], ["Cancel", _open_menu]], note))


func _profile_cheat_done(message: String) -> void:
	_save()
	if _screen is CollectionScreen:
		(_screen as CollectionScreen)._refresh()
	elif _screen is RigScreen:
		(_screen as RigScreen)._refresh()
	elif _screen is HubScreen:
		show_hub()
	UiKit.toast(self, message)


func _open_settings() -> void:
	var st := SettingsScreen.new().setup(profile.settings)
	st.closed.connect(_open_menu)
	st.changed.connect(_on_setting_changed.bind(st))
	get_tree().root.add_child(st)


func _on_setting_changed(key: String, st: SettingsScreen) -> void:
	_save()
	match key:
		"theme":
			apply_theme(profile.settings["theme"])
			if run == null:
				show_hub()
			elif _resume.get("screen", "") == "map":
				show_map()
			# Rebuild the overlay so it picks up the new look.
			st.queue_free()
			_open_settings()
		"anim_speed":
			if _screen is CombatScreen:
				(_screen as CombatScreen).step_scale = anim_speed()
		"cheats":
			if run == null:
				_menu_btn.visible = _is_profile_cheat_screen(_screen)
		"battery_saver":
			_apply_power()
		"colorblind", "no_shake":
			Palette.apply_access(profile.settings)
		"text_size":
			Palette.apply_access(profile.settings)
			if run == null:
				show_hub()
			elif _resume.get("screen", "") == "map":
				show_map()
			st.queue_free()
			_open_settings()
		_:
			if is_instance_valid(GameAudio.instance):
				GameAudio.instance.configure(profile.settings)
			if is_instance_valid(GameMusic.instance):
				GameMusic.instance.configure(profile.settings)


## "Layer 2 · Node 17 · HP 40/60" for the hub's resume button, or "" if no saved run.
func saved_run_info() -> String:
	if not persist:
		return ""
	var data := RunSave.load_run(db, run_save_path)
	if data.is_empty():
		return ""
	var r: RunState = data["run"]
	return "Layer %d · Node %d · HP %d/%d" % [r.act, r.floor_num, r.hp, r.max_hp]


func _resume_run() -> void:
	var data := RunSave.load_run(db, run_save_path)
	if data.is_empty():
		show_hub()
		return
	run = data["run"]
	var res: Dictionary = data["resume"]
	match str(res.get("screen", "map")):
		"node":
			_play_node(run.current_node(), res.get("actions", []))
		"reward":
			_show_reward(res.get("lines", []), res.get("tals", []), res.get("choices", []), res.get("perks", []), res.get("kind", ""))
		"perks":
			_show_perk_pick(res.get("choices", []))
		_:
			show_map()


func _abandon_saved_run() -> void:
	var data := RunSave.load_run(db, run_save_path)
	if data.is_empty():
		RunSave.clear(run_save_path)
		show_hub()
		return
	run = data["run"]
	run.over = true
	_end_run(true)


## Shifts the backdrop glow toward `col` (elites, shops...). No arg = theme default.
func _tint(col: Color = Color.TRANSPARENT) -> void:
	var g: Color = Palette.BACKDROP["glow"]
	_bg_mat.set_shader_parameter("glow_color", g if col == Color.TRANSPARENT else g.lerp(col, 0.6))


# --- hub / collection / packs ---------------------------------------------------

func show_hub() -> void:
	_tint()
	run = null
	_resume = {}
	var hub := HubScreen.new().setup(db, profile, saved_run_info())
	hub.menu_pressed.connect(_open_menu)
	hub.resume_pressed.connect(_resume_run)
	hub.abandon_pressed.connect(func() -> void:
		get_tree().root.add_child(GameMenu.new().setup("Abandon the saved run?", [
			["!Yes, abandon it", _abandon_saved_run],
			["No", null]], "It counts as a loss. You keep the XP and rewards earned so far.")))
	hub.start_pressed.connect(_show_jobs)
	hub.daily_pressed.connect(_start_daily)
	hub.weekly_pressed.connect(_show_weekly)
	hub.login_pressed.connect(_claim_login)
	hub.tutorial_pressed.connect(start_tutorial)
	hub.records_pressed.connect(func() -> void:
		var rs := RecordsScreen.new().setup(db, profile)
		rs.changed.connect(_save)
		rs.closed.connect(show_hub)
		_show(rs))
	hub.collection_pressed.connect(func() -> void:
		var cs := CollectionScreen.new().setup(db, profile)
		cs.closed.connect(show_hub)
		_show(cs))
	hub.packs_pressed.connect(_show_pack_shelf)
	hub.rig_pressed.connect(func() -> void:
		var rs := RigScreen.new().setup(db, profile)
		rs.changed.connect(_save)
		rs.closed.connect(show_hub)
		_show(rs))
	_show(hub)
	CardView.back_style = str(profile.settings.get("card_back", "default"))
	var news := Records.claim_binders(db, profile) + Records.check_exploits(db, profile)
	if not news.is_empty():
		_save()
		UiKit.toast(self, "\n".join(news), 5.0)


# --- tutorial -------------------------------------------------------------------

## Briefing pages, a coached practice fight (see Tutorial), then the debrief.
## No run exists, so nothing but settings.tutorial_done is saved.
func start_tutorial() -> void:
	_show_pages(Tutorial.briefing(db), 0, _start_tutorial_fight)


func _start_tutorial_fight() -> void:
	_tint()
	_combat = Tutorial.make_combat(db)
	var s := CombatScreen.new().setup(_combat, null)
	s.step_scale = anim_speed()
	s.finished.connect(_finish_tutorial)
	_show(s)
	var coach := Tutorial.new().setup(s)
	coach.skipped.connect(_finish_tutorial.bind(false, true))
	s.add_child(coach)


func _finish_tutorial(won: bool, skipped: bool = false) -> void:
	profile.settings["tutorial_done"] = true
	_save()
	if skipped:
		show_hub()
		return
	_show_pages(Tutorial.debrief(db, won), 0, show_hub, "Take a job", func() -> void: _show_jobs(0))


## One page at a time: title, lines, Next (or `done_text` on the last page) and Skip.
## `alt` (optional) is a second button on the last page.
func _show_pages(pages: Array, i: int, on_done: Callable, alt_text: String = "", alt: Callable = Callable()) -> void:
	var parts := UiKit.screen(20)
	var v: VBoxContainer = parts[1]
	if pages.size() > 1:
		v.add_child(UiKit.label("%d / %d" % [i + 1, pages.size()], 14, Palette.TEXT_DIM))
	v.add_child(UiKit.label(pages[i][0], 30, Palette.ENERGY, true))
	for l in pages[i][1]:
		v.add_child(UiKit.label(str(l), 18, Palette.TEXT, true))
	var last := i == pages.size() - 1
	if last and alt.is_valid():
		v.add_child(UiKit.primary(UiKit.button(alt_text, alt, Vector2(300, 64), 20)))
		v.add_child(UiKit.button("Back to hub", on_done, Vector2(300, 56), 17))
	else:
		v.add_child(UiKit.primary(UiKit.button("Start practice fight" if last else "Next", on_done if last else _show_pages.bind(pages, i + 1, on_done, alt_text, alt), Vector2(300, 64), 20)))
		v.add_child(UiKit.button("Skip tutorial", func() -> void:
			profile.settings["tutorial_done"] = true
			_save()
			show_hub(), Vector2(300, 52), 16))
	_show(parts[0])


## Job board: every run is a job for one faction (see Jobs). Each crew is a compact card
## (emblem, pay, targets); tap it to open the full payout and bonus clauses and take the job.
func _show_jobs(heat: int) -> void:
	var parts := UiKit.screen(12, BoxContainer.ALIGNMENT_BEGIN)
	var outer: VBoxContainer = parts[1]
	outer.add_child(UiKit.label("Job board", 32, Palette.ENERGY))
	outer.add_child(UiKit.label("Pick a crew to work for. Tap a job for its full pay and bonuses.", 15, Palette.TEXT_DIM, true))
	var v := UiKit.scroll(outer)
	# Same board until the next run ends, so browsing doesn't reroll the targets.
	var board_rng := GameRng.new(int(profile.stats.get("runs", 0)) * 7919 + heat)
	var details: Array = []
	for offer in Jobs.offers(db, heat, board_rng):
		var f: String = offer["client"]
		var clauses := Records.roll_clauses(db, board_rng.fork("clauses:" + f))
		var j := Jobs.info(db, f)
		var against: Array = offer["targets"].map(func(x: String) -> String: return Lexicon.faction(x))
		var pay := Jobs.payout_preview(db, profile, f, heat, offer["targets"].size() - Jobs.banned(db, f).size())
		var row := UiKit.hbox(14)
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.add_child(Symbols.badge(f, 54))
		var copy := UiKit.vbox(3, BoxContainer.ALIGNMENT_BEGIN)
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		var summary := [
			[j.get("client", f) + "  /  " + Lexicon.faction(f), 19, Palette.faction(f)],
			["Pays +%d %s · %s" % [pay["rep"], Jobs.rep_name(db, f), cache_line(pay)], 14, Palette.TEXT],
			["Against %s · half your picks %s" % [" + ".join(against), Lexicon.faction(f)], 14, Palette.TEXT_DIM]]
		for line in summary:
			copy.add_child(_left_label(line[0], line[1], line[2]))
		var more := UiKit.vbox(4, BoxContainer.ALIGNMENT_BEGIN)
		more.visible = false
		more.add_child(_left_label(j.get("job", ""), 15, Palette.TEXT))
		more.add_child(_left_label("You have %d %s" % [profile.rep_of(f), Jobs.rep_name(db, f)], 14, Palette.faction(f)))
		for l in HubScreen.payout_lines(db, profile, f, heat, offer["targets"].size() - Jobs.banned(db, f).size()):
			more.add_child(_left_label(l, 14, Palette.TEXT))
		for id in clauses:
			more.add_child(_left_label("Bonus " + Records.clause_text(db, id, heat, f), 13, Palette.UPGRADED))
		more.add_child(UiKit.primary(UiKit.button("Take this job", _show_picker.bind(heat, f, offer["targets"], clauses), Vector2(260, 56), 18)))
		copy.add_child(more)
		details.append(more)
		var card := UiKit.panel(row)
		var sb: StyleBoxFlat = card.get_theme_stylebox("panel")
		sb.border_color = Color(Palette.faction(f), 0.6)
		sb.set_border_width_all(2)
		card.mouse_filter = Control.MOUSE_FILTER_PASS  # PASS so dragging on a job still scrolls the board
		var tap := Tap.new()
		card.gui_input.connect(func(event: InputEvent) -> void:
			if tap.feed(event) == "tap":
				GameAudio.play("tap")
				var open := not more.visible
				for d in details:
					d.visible = false
				more.visible = open)
		v.add_child(card)
	outer.add_child(UiKit.button("Back", show_hub, Vector2(200, 56)))
	_show(parts[0])


## "3 crew caches + Zero-day" style summary of a full clear's caches, for the job cards.
static func cache_line(pay: Dictionary) -> String:
	var n: int = pay.get("pack_list", []).size() + int(pay.get("first_clear", 0))
	return "%d cache%s on a full clear%s" % [n, "" if n == 1 else "s", HubScreen.scrap_text(pay)]


func _left_label(text: String, font_size: int, col: Color) -> Label:
	var label := UiKit.label(text, font_size, col)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _show_picker(heat: int, job: String = "", targets: Array = [], clauses: Array = []) -> void:
	var cs := CollectionScreen.new().setup(db, profile, true, job, targets)
	cs.closed.connect(_show_jobs.bind(heat))
	cs.picks_confirmed.connect(func(picks: Array) -> void:
		profile.last_picks = picks
		_save()
		run = RunState.start(db, profile, picks, int(Time.get_unix_time_from_system()), heat, job, targets)
		run.clauses = clauses.duplicate()
		run.deep_ok = Records.deep_unlocked(db, profile)
		show_map())
	_show(cs)


## Daily breach: today's fixed job, heat and seed. One attempt per day.
func _start_daily() -> void:
	var d := Records.daily(db, Records.today())
	if Records.daily_used(profile, d["date"]):
		show_hub()
		return
	var packs := Records.begin_daily(db, profile, d["date"])
	_save()
	if packs > 0:
		UiKit.toast(self, "Daily breach: +%d %s for jacking in" % [packs, Palette.w("pack").to_lower() if packs == 1 else Palette.w("packs").to_lower()], 3.0)
	run = RunState.start(db, profile, RunState.default_picks(db, profile, d["job"], d["targets"]), int(d["seed"]), int(d["heat"]), d["job"], d["targets"])
	run.daily = d["date"]
	run.clauses = Records.roll_clauses(db, GameRng.new(int(d["seed"])).fork("clauses"))
	show_map()


## Daily login bonus: pays today's day of the 7-day track, then redraws the hub.
func _claim_login() -> void:
	var got := LoginBonus.claim(db, profile, Records.today())
	if got.is_empty():
		return
	_save()
	show_hub()
	UiKit.toast(self, "Day %d login bonus: %s" % [got["day"], LoginBonus.reward_text(db, got["day"])], 3.0)


## Weekly challenge briefing: this week's job, rule changes, what's off, and the reward.
func _show_weekly() -> void:
	var w := Weekly.challenge(db, Weekly.this_week())
	var st := Weekly.state(profile, w["week"])
	var parts := UiKit.screen(14)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("Weekly challenge", 32, Palette.ENERGY))
	v.add_child(UiKit.label("Week of %s · new challenge in %d day%s" % [w["week"], Weekly.days_left(Records.today()), "" if Weekly.days_left(Records.today()) == 1 else "s"], 14, Palette.TEXT_DIM))
	var against: Array = w["targets"].map(func(x: String) -> String: return Lexicon.faction(x))
	var job_row := UiKit.hbox(12)
	job_row.add_child(Symbols.badge(w["job"], 48))
	job_row.add_child(UiKit.label("%s job at Heat %d\nAgainst: %s (banned)" % [Lexicon.faction(w["job"]), w["heat"], " + ".join(against)], 17, Palette.faction(w["job"])))
	v.add_child(job_row)
	v.add_child(UiKit.label("This week's rule changes", 19, Palette.TEXT))
	for id in w["mods"]:
		var m: Dictionary = db.weekly[id]
		var box := UiKit.vbox(4)
		box.add_child(UiKit.label(str(m["name"]), 18, Palette.UPGRADED))
		var t := UiKit.label(str(m["text"]), 15, Palette.TEXT, true)
		t.custom_minimum_size.x = 560
		box.add_child(t)
		v.add_child(UiKit.panel(box))
	var rules := UiKit.label("Load programs from your own library. Firmware and rig upgrades are off: every program plays at base level and no rig rank applies. Safehouse upgrades and subroutines inside the run still work. Same challenge for everyone this week; try as often as you like.", 14, Palette.TEXT_DIM, true)
	rules.custom_minimum_size.x = 600
	v.add_child(rules)
	var packs := int(db.balance.get("weekly", {}).get("packs", 0))
	var reward := "Cleared this week. Best score %d. Replays count for score only." % int(st["best"]) if st["cleared"] \
		else "First clear this week: +%d %s. Normal job pay (rep, XP, caches per Core) on every try." % [packs, PackArt.title(db, str(db.balance.get("weekly", {}).get("pack_kind", Packs.PREMIUM)))]
	v.add_child(UiKit.label(reward, 15, Palette.ENERGY, true))
	if int(st["tries"]) > 0:
		v.add_child(UiKit.label("Tries this week: %d · best score %d" % [int(st["tries"]), int(st["best"])], 14, Palette.TEXT_DIM))
	v.add_child(UiKit.primary(UiKit.button("Load programs", _show_weekly_picker.bind(w), Vector2(300, 68), 20)))
	v.add_child(UiKit.button("Back", show_hub, Vector2(200, 56)))
	_show(parts[0])


func _show_weekly_picker(w: Dictionary) -> void:
	var cs := CollectionScreen.new().setup(db, profile, true, w["job"], w["targets"])
	cs.base_only = true
	cs.closed.connect(_show_weekly)
	cs.picks_confirmed.connect(func(picks: Array) -> void:
		profile.last_picks = picks
		run = Weekly.begin(db, profile, w, picks)
		_save()
		show_map())
	_show(cs)


## Screenshots: show pack cards face up straight away.
var reveal_packs_now := false


## The cache shelf: every unopened pack kind with its own packet. Tap one to open it.
func _show_pack_shelf() -> void:
	var owned := profile.pack_kinds_owned()
	if owned.is_empty():
		show_hub()
		return
	var parts := UiKit.screen(16)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("%s (%d)" % [Palette.w("packs"), profile.packs_unopened], 26))
	v.add_child(UiKit.label("Tap a cache to crack it. Each kind keeps its own mercy timer.", 14, Palette.TEXT_DIM, true))
	var grid := UiKit.flow(14)
	grid.alignment = FlowContainer.ALIGNMENT_CENTER
	for k in owned:
		var tile := PackArt.new().setup(db, k, profile.pack_count(k))
		tile.custom_minimum_size.x = 170
		tile.pressed.connect(func(kind: String) -> void: _show_pack(kind))
		grid.add_child(tile)
	v.add_child(grid)
	v.add_child(UiKit.label(PackArt.odds_line(db, profile, owned[0]), 14, PackArt.tint(owned[0]), true))
	v.add_child(UiKit.primary(UiKit.button("Open a %s" % PackArt.title(db, owned[0]), func() -> void: _show_pack(owned[0]), Vector2(260, 60))))
	v.add_child(UiKit.button("Back", show_hub, Vector2(160, 52)))
	_show(parts[0])


func _show_pack(kind: String = "") -> void:
	if kind == "" or profile.pack_count(kind) <= 0:
		var owned := profile.pack_kinds_owned()
		if owned.is_empty():
			show_hub()
			return
		kind = owned[0]
	var pulled := profile.open_pack(db, GameRng.new(int(Time.get_ticks_usec())), kind)
	_save()
	var screen := PackScreen.new().setup(db, profile, kind, pulled, reveal_packs_now)
	screen.set_meta("smooth", true)  # 60 fps for the reveal animations
	screen.changed.connect(_save)
	screen.next_pack.connect(_show_pack)
	screen.done.connect(func() -> void: _show_pack_shelf() if profile.packs_unopened > 0 else show_hub())
	_show(screen)


# --- map ------------------------------------------------------------------------

func show_map() -> void:
	if run.deep_pending:
		_show_deep_choice()
		return
	_tint()
	_save_run({"screen": "map"})
	var m := MapScreen.new().setup(run)
	m.node_chosen.connect(_enter_node)
	_show(m)


func _enter_node(id: int) -> void:
	GameAudio.play("travel")
	var node := run.enter(id)
	_save_run({"screen": "node"})
	if not run.jump_lines.is_empty():
		UiKit.toast(self, "\n".join(run.jump_lines))
	_play_node(node)


func _play_node(node: Dictionary, actions: Array = []) -> void:
	match node.get("type", ""):
		"fight", "elite", "boss", "vault":
			_start_combat(node, actions)
		"rest":
			_show_rest()
		"shop":
			_show_shop(run.make_shop())
		"event":
			_show_event(run.pick_event())
		"treasure":
			var tid := run.roll_talisman("", run.rng.fork("treasure:%d" % run.floor_num))
			run.add_talisman(tid)
			_show_message(Palette.w("treasure"), ["You pull %s from the cache." % db.talismans[tid]["name"] if tid != "" else "The cache is empty."], {"tals": [tid] if tid != "" else []})


## `actions`: a saved fight's moves (Combat.checkpoint) to replay, so a resumed run picks up
## at the start of the turn it was closed on. If they no longer fit, the fight starts over.
func _start_combat(node: Dictionary, actions: Array = []) -> void:
	_tint(Palette.NODE[node["type"]] if node["type"] != "fight" else Color.TRANSPARENT)
	_combat = run.start_combat(node["encounter"])
	_combat.start()
	if not actions.is_empty() and not _combat.replay(actions):
		push_warning("Saved fight didn't replay; starting it over")
		_combat = run.start_combat(node["encounter"])
		_combat.start()
	var s := CombatScreen.new().setup(_combat, run)
	s.step_scale = anim_speed()
	s.finished.connect(_on_combat_finished)
	var fight := _combat
	s.acted.connect(func() -> void:
		# Save at each turn start: closing the app mid-fight resumes at that turn.
		if fight == _combat and not fight.is_over() and fight.phase == Combat.Phase.PLAYER:
			var cp := fight.checkpoint()
			if cp.size() != (_resume.get("actions", []) as Array).size():
				_save_run({"screen": "node", "actions": cp}))
	_show(s)
	if node.get("type", "") == "boss":
		GameMusic.mood("boss")
		GameAudio.play("boss")
	var accent := s.reveal_boss()
	if accent.a > 0.0 and Palette.BACKDROP["style"] == 4:
		_bg_mat.set_shader_parameter("boss_color", accent)
		_bg_mat.set_shader_parameter("boss_entrance", -0.18)
		_glass_pulse = create_tween()
		_glass_pulse.tween_property(_bg_mat, "shader_parameter/boss_entrance", 1.22, 1.10)
		_glass_pulse.tween_callback(_bg_mat.set_shader_parameter.bind("boss_entrance", -1.0))


func _on_combat_finished(_won: bool) -> void:
	var rewards := run.finish_combat(_combat)
	if run.over:
		_end_run()
		return
	var lines := ["+%d creds" % rewards["gold"]]
	if int(rewards.get("healed", 0)) > 0:
		lines.append("Nanites repair %d HP" % int(rewards["healed"]))
	if rewards.has("act_started"):
		lines.push_front("Layer %d breached. You reboot (now %d/%d HP)." % [rewards["act_started"], run.hp, run.max_hp])
		if run.double_crossed and int(rewards["act_started"]) == run.total_acts():
			lines.insert(1, "Double cross! %s sold you out. Their crew now hunts you, and their Core guards the last layer." % Jobs.info(db, run.job).get("client", Lexicon.faction(run.job)))
	var tals: Array = []
	if rewards["talisman"] != "":
		run.add_talisman(rewards["talisman"])
		lines.append("Recovered implant: %s" % db.talismans[rewards["talisman"]]["name"])
		tals.append(rewards["talisman"])
	if rewards.has("vault"):
		var v: Dictionary = rewards["vault"]
		lines.append("Vault cracked: +%d creds" % int(v["gold"]))
		if str(v["talisman"]) != "":
			lines.append("Vault implant: %s" % db.talismans[v["talisman"]]["name"])
			tals.append(v["talisman"])
		lines.append_array(v.get("lines", []))
	_show_reward(lines, tals, rewards["cards"], rewards.get("perks", []), rewards["kind"])


func _show_reward(lines: Array, tals: Array, choices: Array, perks: Array = [], kind: String = "") -> void:
	GameAudio.play("reward")
	_save_run({"screen": "reward", "lines": lines, "tals": tals, "choices": choices, "perks": perks, "kind": kind})
	var next := show_map if perks.is_empty() else _show_perk_pick.bind(perks)
	var parts := _run_screen(20)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("Sentries crashed", 34, Palette.ENERGY))
	for l in lines:
		v.add_child(UiKit.label(l, 18))
	_add_talisman_row(v, tals)
	v.add_child(UiKit.label("Rip one program into your deck", 20, Palette.TEXT_DIM))
	var row := UiKit.flow(12)
	for id in choices:
		var up := run.offer_upgraded(id, kind)
		var cv := CardView.new().setup(run.offer_card(id, up))
		cv.pressed.connect(func(_v: CardView) -> void:
			run.add_card(id, up)
			next.call())
		if up:
			var cell := UiKit.vbox(4)
			cell.add_child(cv)
			cell.add_child(UiKit.label("Upgraded", 16, Palette.UPGRADED))
			row.add_child(cell)
		else:
			row.add_child(cv)
		cv.reveal_reward.call_deferred(float(row.get_child_count() - 1) * 0.1)
	v.add_child(row)
	if kind != "" and not choices.is_empty() and run.reward_rerolls_left > 0:
		v.add_child(UiKit.button("Reroll programs (%d left)" % run.reward_rerolls_left, func() -> void:
			var replacement := run.reroll_reward(kind, choices)
			if replacement.is_empty():
				UiKit.toast(self, "No alternate program set available.")
			else:
				_show_reward(lines, tals, replacement, perks, kind)))
	var skip_gold := run.reward_skip_gold(kind) if not choices.is_empty() else 0
	v.add_child(UiKit.button("Skip (+%d creds)" % skip_gold if skip_gold > 0 else "Skip", func() -> void:
		if skip_gold > 0:
			run.skip_reward(kind)
		next.call()))
	_show(parts[0])


## After black sentries and Cores: load one of a few subroutines (run perks).
func _show_perk_pick(choices: Array) -> void:
	_save_run({"screen": "perks", "choices": choices})
	var parts := _run_screen(18)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("Load a subroutine", 32, Palette.ENERGY))
	v.add_child(UiKit.label("Pick one perk. Subroutines run in the background for the rest of this run.", 16, Palette.TEXT_DIM, true))
	for pid in choices:
		var p: Dictionary = db.perks[pid]
		v.add_child(UiKit.button("%s\n%s" % [p["name"], Perks.describe(p)], func() -> void:
			var before := _run_snapshot()
			var lines := run.add_perk(pid)
			var gains := _run_gains(before)
			gains["perks"] = []
			if lines.size() > 1 or not gains["cards"].is_empty() or not gains["tals"].is_empty():
				_show_message(p["name"], lines, gains)
			else:
				show_map(), Vector2(560, 80), 17))
	v.add_child(UiKit.button("Skip", show_map, Vector2(200, 56)))
	_show(parts[0])


# --- rest / shop / event ----------------------------------------------------------

## A run screen: the run bar pinned to the top, the content below it. Returns [root, content].
func _run_screen(sep: int = 20, align: BoxContainer.AlignmentMode = BoxContainer.ALIGNMENT_CENTER) -> Array:
	var parts := UiKit.screen(10, BoxContainer.ALIGNMENT_BEGIN)
	var outer: VBoxContainer = parts[1]
	outer.add_child(RunHeader.new().setup(run))
	var v := UiKit.vbox(sep, align)
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(v)
	return [parts[0], v]

func _show_rest() -> void:
	_tint(Palette.NODE["rest"])
	var parts := _run_screen(24)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label(Palette.w("rest"), 30))
	if Palette.w("rest_text") != "":
		v.add_child(UiKit.label(Palette.w("rest_text"), 16, Palette.TEXT_DIM, true))
	v.add_child(UiKit.label("Pick one:", 16, Palette.TEXT_DIM))
	var heal := run.rest_heal_amount()
	var reboot := UiKit.button(("Reboot\nHeal %d HP" % heal) if heal > 0 else "Reboot\nAlready at full HP", func() -> void:
		run.rest_heal()
		GameAudio.play("heal")
		show_map(), Vector2(320, 78), 20)
	reboot.disabled = heal <= 0
	v.add_child(reboot)
	v.add_child(UiKit.button("Recompile a program\nUpgrade one card for the rest of this run", func() -> void:
		add_child(DeckOverlay.new().setup("Choose a program to recompile", run.deck, "Cancel", func(i: int) -> void:
			if i >= 0 and run.upgrade_card(i):
				GameAudio.play("upgrade")
				show_map(), true, true)), Vector2(440, 78), 19))
	var mods := run.mod_choices(int(db.balance.get("rest_mod_choices", 2)), run.rng.fork("tinker:%d" % run.floor_num))
	if not mods.is_empty():
		v.add_child(UiKit.label("Or tinker: add a mod to one card (one mod per card, lasts this run)", 16, Palette.TEXT_DIM))
		for mid in mods:
			v.add_child(_mod_button(mid, "", func() -> void:
				_pick_mod_target(mid, func(i: int) -> void:
					if run.install_mod(i, mid):
						GameAudio.play("upgrade")
						show_map())))
	_show(parts[0])


## Button showing a mod's name, rules and fit. suffix e.g. a price.
func _mod_button(mid: String, suffix: String, on_press: Callable) -> Button:
	var m := db.mod(mid)
	var fit := CardMods.restriction_text(m)
	var b := UiKit.button("%s%s\n%s%s" % [m["name"], suffix, CardMods.describe(m), (" " + fit) if fit != "" else ""], on_press, Vector2(560, 74), 18)
	b.add_theme_color_override("font_color", Palette.rarity(str(m["rarity"])))
	return b


func _pick_mod_target(mid: String, on_pick: Callable) -> void:
	var m := db.mod(mid)
	add_child(DeckOverlay.new().setup("Install %s on which program?" % m["name"], run.deck, "Cancel", func(i: int) -> void:
		if i >= 0:
			on_pick.call(i), true, false, m))


func _show_shop(shop: Dictionary) -> void:
	_tint(Palette.NODE["shop"])
	var parts := _run_screen(16, BoxContainer.ALIGNMENT_BEGIN)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label(Palette.w("shop"), 30))
	v.add_child(UiKit.label("The shop. Spend creds on programs, implants (passive bonuses) and mods.", 15, Palette.TEXT_DIM, true))
	var cards := UiKit.flow(10)
	for item in shop["cards"]:
		var sold_card: bool = item.get("sold", false)
		var cv := CardView.new().setup(run.offer_card(item["id"], bool(item.get("up", false))))
		cv.playable = not sold_card and run.gold >= int(item["price"])
		cv.pressed.connect(func(_v: CardView) -> void:
			if run.buy(item, false):
				GameAudio.play("purchase")
				_show_shop(shop))
		var cell := UiKit.vbox(4)
		cell.add_child(cv)
		if item.get("up", false):
			cell.add_child(UiKit.label("Upgraded", 16, Palette.UPGRADED))
		cell.add_child(UiKit.label("sold" if sold_card else "%d creds" % item["price"], 18, Palette.TEXT_DIM if sold_card else (Palette.ENERGY if cv.playable else Palette.HP)))
		cards.add_child(cell)
	v.add_child(cards)
	for item in shop["talismans"]:
		var trow := UiKit.hbox(10)
		trow.add_child(_implant_panel(item["id"], 440.0))
		var sold: bool = item.get("sold", false)
		var b := UiKit.button("sold" if sold else "Buy\n%d creds" % item["price"], func() -> void:
			if run.buy(item, true):
				GameAudio.play("purchase")
				_show_shop(shop), Vector2(128, 64), 18)
		b.disabled = sold or run.gold < int(item["price"])
		trow.add_child(b)
		v.add_child(trow)
	for item in shop.get("mods", []):
		var sold: bool = item.get("sold", false)
		var mb := _mod_button(item["id"], "  ·  sold" if sold else "  ·  %d creds" % item["price"], func() -> void:
			_pick_mod_target(item["id"], func(i: int) -> void:
				if run.buy_mod(item, i):
					GameAudio.play("purchase")
					_show_shop(shop)))
		mb.disabled = sold or run.gold < int(item["price"])
		v.add_child(mb)
	var rm := UiKit.button("Remove a card from your deck (%d creds)" % run.remove_price(), func() -> void:
		add_child(DeckOverlay.new().setup("Choose a program to remove", run.deck, "Cancel", func(i: int) -> void:
			if i >= 0 and run.remove_card(i):
				GameAudio.play("delete")
				shop["remove"] = run.remove_price()
				_show_shop(shop), true)), Vector2(300, 56))
	rm.disabled = run.gold < run.remove_price() or shop.get("removed", false)
	v.add_child(rm)
	v.add_child(UiKit.button("Leave shop", show_map))
	_show(parts[0])


func _show_event(ev: Dictionary) -> void:
	_tint(Palette.NODE["event"])
	var parts := _run_screen(20)
	var v: VBoxContainer = parts[1]
	var art := Control.new()
	art.custom_minimum_size = Vector2(160, 160)
	art.draw.connect(func() -> void:
		Sigil.draw(art, art.size / 2, 64.0, "event:" + str(ev["id"]), Palette.NODE["event"], Time.get_ticks_msec() / 1000.0)
		art.queue_redraw())
	v.add_child(art)
	v.add_child(UiKit.label(ev["title"], 30))
	v.add_child(UiKit.label(ev["text"], 17, Palette.TEXT_DIM, true))
	for ch in ev["choices"]:
		var desc: Array[String] = []
		for o in ch.get("outcomes", []):
			desc.append(RunOutcomes.describe(o))
		var label: String = ch["label"] + ("\n" + " ".join(desc) if not desc.is_empty() else "")
		var b := UiKit.button(label, func() -> void:
			var before := _run_snapshot()
			var lines := run.choose(ch)
			_show_message(ev["title"], lines if not lines.is_empty() else ["Nothing happens."], _run_gains(before)), Vector2(520, 72), 16)
		b.disabled = not run.can_choose(ch)
		v.add_child(b)
	if run.event_rerolls_left > 0 and db.events.size() > 1:
		v.add_child(UiKit.button("Reroll this signal (%d left)" % run.event_rerolls_left, func() -> void:
			var replacement := run.reroll_event(ev["id"])
			if not replacement.is_empty():
				_show_event(replacement)))
	_show(parts[0])


## Result screen for a Signal, cache or subroutine. `gains` (see _run_gains) is shown, not just
## listed: new or changed programs as cards, implants and subroutines with their rules text.
func _show_message(title: String, lines: Array, gains: Dictionary = {}) -> void:
	var parts := _run_screen(20)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label(title, 30))
	for l in lines:
		v.add_child(UiKit.label(str(l), 18, Palette.TEXT, true))
	var cards: Array = gains.get("cards", [])
	if not cards.is_empty():
		var row := UiKit.flow(12)
		for c: CardInstance in cards:
			var cv := CardView.new().setup(c)
			row.add_child(cv)
			cv.reveal_reward.call_deferred(float(row.get_child_count() - 1) * 0.1)
		v.add_child(row)
	_add_talisman_row(v, gains.get("tals", []))
	for pid in gains.get("perks", []):
		var p: Dictionary = db.perks[pid]
		v.add_child(_info_panel("Subroutine: " + str(p["name"]), Perks.describe(p), Palette.ENERGY))
	v.add_child(UiKit.primary(UiKit.button("Continue", show_map)))
	_show(parts[0])


## What the run holds now, to diff after a random outcome (see _run_gains).
func _run_snapshot() -> Dictionary:
	var cards := {}
	for c: CardInstance in run.deck:
		cards[c] = [c.upgraded, c.fw, c.mod_id()]
	return {"cards": cards, "tals": run.talismans.duplicate(), "perks": run.perks.duplicate()}


## {"cards": programs added, upgraded or modded since `before`, "tals": new implants, "perks": new subroutines}.
func _run_gains(before: Dictionary) -> Dictionary:
	var known: Dictionary = before["cards"]
	var cards: Array = []
	for c: CardInstance in run.deck:
		if not known.has(c) or known[c] != [c.upgraded, c.fw, c.mod_id()]:
			cards.append(c)
	return {"cards": cards,
		"tals": run.talismans.filter(func(t: String) -> bool: return t not in before["tals"]),
		"perks": run.perks.filter(func(p: String) -> bool: return p not in before["perks"])}


func _add_talisman_row(v: VBoxContainer, tals: Array) -> void:
	for tid in tals:
		v.add_child(_implant_panel(tid))


## An implant shown with its name and what it does (rewards, the Fixer, Signals).
func _implant_panel(tid: String, width: float = 520.0) -> Control:
	var t: Dictionary = db.talismans[tid]
	var rarity := str(t.get("rarity", "common"))
	var col: Color = Palette.ENEMY if rarity == "boss" else Palette.rarity(rarity)
	return _info_panel(str(t.get("name", tid)), Talismans.describe(t), col, TalismanView.new().setup(tid, db, true), width)


## Panel with an optional icon, a coloured title and wrapped body text.
func _info_panel(title: String, body: String, col: Color, icon: Control = null, width: float = 520.0) -> Control:
	var row := UiKit.hbox(12)
	if icon != null:
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
	var text := UiKit.vbox(2)
	for pair in [[title, 18, col], [body, 15, Palette.TEXT]]:
		var l := UiKit.label(pair[0], pair[1], pair[2], true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.custom_minimum_size.x = width - (96 if icon != null else 12)
		text.add_child(l)
	row.add_child(text)
	var p := UiKit.panel(row)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return p


## Deep Stack: after the final Core (and every Core below it) pick between banking the win
## and going one layer deeper. The win is already safe either way.
func _show_deep_choice() -> void:
	_tint()
	_save_run({"screen": "map"})
	var cfg: Dictionary = db.balance.get("deep_stack", {})
	var next := run.deep + 1
	var parts := UiKit.screen(16)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("The Deep Stack" if run.deep == 0 else "Depth %d cleared" % run.deep, 34, Palette.ENERGY))
	var body := UiKit.label("The job is done and the win is yours. Below the last Core the Stack keeps going. Each layer down, sentries get +%d%% HP and +%d%% damage on top of the last. Each Core down there still pays a crew cache, but no rep, and your depth goes on your record. Flatlining keeps the win." % [
		roundi(float(cfg.get("enemy_hp_pct", 0.0)) * 100), roundi(float(cfg.get("enemy_dmg_pct", 0.0)) * 100)], 16, Palette.TEXT, true)
	body.custom_minimum_size.x = 560
	v.add_child(body)
	v.add_child(UiKit.label("Your record: depth %d   ·   HP %d/%d" % [int(profile.stats.get("best_depth", 0)), run.hp, run.max_hp], 15, Palette.TEXT_DIM))
	v.add_child(UiKit.primary(UiKit.button("Go deeper (depth %d)" % next, func() -> void:
		run.descend()
		show_map(), Vector2(360, 72), 22)))
	v.add_child(UiKit.button("Jack out with the win", func() -> void:
		run.jack_out()
		_end_run(), Vector2(360, 64)))
	_show(parts[0])


# --- end of run -------------------------------------------------------------------

func _end_run(abandoned: bool = false) -> void:
	# Who finished you: the enemies still standing when the fight was lost.
	var killers: Array[String] = []
	if not run.boss_won and not abandoned and _combat != null and _combat.phase == Combat.Phase.LOST:
		for en: Fighter in _combat.living(_combat.enemies):
			if en.name not in killers:
				killers.append(en.name)
	var lines := profile.finish_run(db, run)
	_save()
	if persist:
		RunSave.clear(run_save_path)
	var parts := UiKit.screen(14)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("Run won! You own the Stack." if run.boss_won else ("Run abandoned on node %d" if abandoned else "Flatlined: run over on node %d") % run.floor_num, 34, Palette.ENERGY if run.boss_won else Palette.HP, true))
	if not killers.is_empty():
		v.add_child(UiKit.label("Taken down by " + " and ".join(killers), 22, Palette.ENEMY, true))
	var stats := UiKit.hbox(10)
	for pair in [["Fights", run.combats_won], ["Elites", run.elites_won], ["Node", run.floor_num], ["Deck", run.deck.size()]]:
		var cell := UiKit.vbox(0)
		cell.add_child(UiKit.label(str(pair[1]), 30, Palette.TEXT))
		cell.add_child(UiKit.label(str(pair[0]), 19, Palette.TEXT_DIM))
		cell.custom_minimum_size.x = 110
		stats.add_child(UiKit.panel(cell))
	v.add_child(stats)
	v.add_child(_path_strip())
	var high := _run_highlights()
	if not high.is_empty():
		v.add_child(UiKit.label("Highlights", 22, Palette.ENERGY))
		var hl := UiKit.label("\n".join(high), 20, Palette.TEXT, true)
		v.add_child(hl)
	if not lines.is_empty():
		v.add_child(UiKit.label("Earned", 22, Palette.ENERGY))
		var earned := UiKit.label("\n".join(lines.map(func(l: Variant) -> String: return str(l))), 20, Palette.UPGRADED, true)
		earned.custom_minimum_size.x = 600
		var box := UiKit.panel(earned)
		box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(box)
	v.add_child(UiKit.primary(UiKit.button(Palette.w("camp"), show_hub, Vector2(360, 72), 22)))
	_show(parts[0])


## The route this run took, one small node icon per stop (layers split by a gap).
func _path_strip() -> Control:
	var box := UiKit.vbox(6)
	box.add_child(UiKit.label("Your route on layer %d" % run.act, 19, Palette.TEXT_DIM))
	var row := UiKit.flow(4)
	row.custom_minimum_size.x = 600
	for id in run.path:
		var n: Dictionary = run.map.node(id) if run.map != null and id >= 0 and id < run.map.nodes.size() else {}
		if n.is_empty():
			continue
		var icon := Symbols.badge(str(n["type"]), 24)
		icon.modulate = Palette.NODE[n["type"]]
		row.add_child(icon)
	if row.get_child_count() == 0:
		return Control.new()
	box.add_child(row)
	return box


## A few lines worth remembering: biggest hit, most-run program, peak Firewall, kills.
func _run_highlights() -> Array[String]:
	var t := run.tally
	var out: Array[String] = []
	if int(t.get("big_hit", 0)) > 0:
		out.append("Biggest hit: %d damage" % int(t["big_hit"]))
	var best := ""
	var best_n := 0
	for id in run.card_plays:
		if int(run.card_plays[id]) > best_n and db.card(id) != null and db.card(id).rarity not in ["starter", "curse"]:
			best = db.card(id).name
			best_n = int(run.card_plays[id])
	if best != "":
		out.append("Most run program: %s (%d times)" % [best, best_n])
	if int(t.get("max_ward", 0)) > 0:
		out.append("Peak Firewall: %d" % int(t["max_ward"]))
	if int(t.get("kills", 0)) > 0:
		out.append("Sentries crashed: %d" % int(t["kills"]))
	return out
