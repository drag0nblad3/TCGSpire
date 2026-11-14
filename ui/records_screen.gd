class_name RecordsScreen
extends Control
## Records: crew binders, the Exploit log, daily breach scores and the card back / title
## picker. Rules live in Records; this screen only shows them.

signal closed
signal changed

const TABS := ["binders", "exploits", "ice", "daily", "style"]
const TAB_NAMES := {"binders": "Binders", "exploits": "Exploits", "ice": "ICE", "daily": "Daily", "style": "Style"}

var db: CardDB
var profile: Profile
var tab := "binders"
var _list: VBoxContainer
var _tabs: HBoxContainer


func setup(db_in: CardDB, p: Profile, tab_in: String = "binders") -> RecordsScreen:
	db = db_in
	profile = p
	tab = tab_in
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parts := UiKit.screen(12, BoxContainer.ALIGNMENT_BEGIN)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("Records", 30, Palette.ENERGY))
	_tabs = UiKit.hbox(8)
	v.add_child(_tabs)
	_list = UiKit.scroll(v)
	v.add_child(UiKit.button("Back", func() -> void: closed.emit(), Vector2(160, 60)))
	_refresh()


func _set_tab(t: String) -> void:
	tab = t
	_refresh()


func _refresh() -> void:
	for n in _tabs.get_children():
		n.queue_free()
	for t in TABS:
		var b := UiKit.button(TAB_NAMES[t], _set_tab.bind(t), Vector2(122, 48), 15)
		b.disabled = t == tab
		_tabs.add_child(b)
	for n in _list.get_children():
		n.queue_free()
	match tab:
		"binders":
			_binders()
		"exploits":
			_exploits()
		"ice":
			_ice()
		"daily":
			_daily()
		"style":
			_style()


func _line(text: String, size: int = 15, col: Color = Palette.TEXT) -> Label:
	var l := UiKit.label(text, size, col, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.custom_minimum_size.x = 0
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(l)
	return l


func _binders() -> void:
	_line("Own every program on a page to complete it. Commons and uncommons pay dust; a full crew set also unlocks that crew's card back and a title.", 14, Palette.TEXT_DIM)
	var cfg: Dictionary = db.balance.get("binders", {})
	for f in Jobs.board(db) + ["neutral"]:
		var head := UiKit.hbox(10)
		if f != "neutral":
			head.add_child(Symbols.badge(f, 32))
		var name_l := UiKit.label(Lexicon.faction(f), 19, Palette.faction(f) if f != "neutral" else Palette.TEXT)
		name_l.add_theme_font_override("font", Palette.display())
		head.add_child(name_l)
		_list.add_child(head)
		for page in Records.binder(db, profile, f):
			var r: Dictionary = cfg.get(page["tier"], {})
			var reward := "%d dust" % int(r.get("dust", 0))
			if r.get("card_back", false) and f != "neutral":
				reward += ", card back, title"
			var mark := "Done" if page["done"] else "%d / %d" % [page["have"], page["need"]]
			var row := UiKit.hbox(10)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(220, 14)
			bar.show_percentage = false
			bar.max_value = maxi(int(page["need"]), 1)
			bar.value = int(page["have"])
			var name_r := UiKit.label("%s  %s" % [page["name"], mark], 14, Palette.ENERGY if page["done"] else Palette.TEXT)
			name_r.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			name_r.custom_minimum_size.x = 170
			var reward_l := UiKit.label(reward, 13, Palette.TEXT_DIM)
			reward_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.alignment = BoxContainer.ALIGNMENT_BEGIN
			row.add_child(name_r)
			row.add_child(bar)
			row.add_child(reward_l)
			_list.add_child(row)


func _exploits() -> void:
	var ids: Array = db.exploits.keys()
	ids.sort()
	_line("%d / %d exploits logged. Five unlock the glitch card back." % [profile.exploits.size(), ids.size()], 15, Palette.TEXT_DIM)
	for id in ids:
		var x: Dictionary = db.exploits[id]
		var got := profile.exploits.has(id)
		var have := Records.life_stat(db, profile, str(x["stat"]))
		_line(("%s  ·  %s" % [x["name"], x["text"]]) if got else ("%s  ·  %s  (%d / %d)" % [x["name"], x["text"], mini(have, int(x["at_least"])), int(x["at_least"])]),
			16, Palette.UPGRADED if got else Palette.TEXT)
		_line(str(x["lore"]) if got else "[encrypted]", 13, Palette.TEXT_DIM)


## ICE database: every sentry, decoded after a few fights. Unknown ones stay hidden.
func _ice() -> void:
	var entries := Records.ice_entries(db, profile)
	var need := Records.ice_reveal(db)
	var decoded := entries.filter(func(e: Dictionary) -> bool: return e["state"] == "decoded").size()
	_line("ICE database: %d / %d decoded. Fight a sentry %d times to decode its moves and file. Counts update when a run ends." % [decoded, entries.size(), need], 14, Palette.TEXT_DIM)
	var group := "?"
	var hidden := {}
	for e in entries:
		if e["state"] == "unknown":
			hidden[e["faction"]] = int(hidden.get(e["faction"], 0)) + 1
	for e in entries:
		var f: String = e["faction"]
		if f != group:
			group = f
			var head := UiKit.hbox(10)
			if f != "":
				head.add_child(Symbols.badge(f, 32))
			var name_l := UiKit.label(Lexicon.faction(f) if f != "" else "The Stack", 19, Palette.faction(f) if f != "" else Palette.TEXT)
			name_l.add_theme_font_override("font", Palette.display())
			head.add_child(name_l)
			_list.add_child(head)
			if hidden.has(f):
				_line("??? × %d not met yet" % int(hidden[f]), 14, Palette.TEXT_DIM)
		var tag: String = {"elite": "  ·  black sentry", "boss": "  ·  Core"}.get(e["kind"], "")
		if e["state"] == "unknown":
			continue
		_line("%s%s  ·  met %d  ·  crashed %d  ·  flatlined you %d" % [e["name"], tag, e["seen"], e["crashed"], e["lost"]],
			16, Palette.UPGRADED if e["state"] == "decoded" else Palette.TEXT)
		if e["state"] == "seen":
			_line("[encrypted] %d more fight%s to decode." % [need - int(e["seen"]), "" if need - int(e["seen"]) == 1 else "s"], 13, Palette.TEXT_DIM)
			continue
		for m in e["moves"]:
			_line("  " + str(m), 13)
		_line(str(e["lore"]), 13, Palette.TEXT_DIM)


func _daily() -> void:
	var d := Records.daily(db, Records.today())
	var done: bool = str(profile.daily.get("last", "")) == d["date"]
	_line("Today (%s): a %s job at Heat %d against %s. Everyone gets the same Stack and seed, and you get one attempt a day with your default picks." % [
		d["date"], Lexicon.faction(d["job"]), d["heat"], " + ".join(d["targets"].map(func(x: String) -> String: return Lexicon.faction(x)))], 15)
	_line("Done today." if done else "Not run yet today. Start it from the hub.", 15, Palette.ENERGY)
	_line("Best score ever: %d   ·   Dailies finished: %d" % [int(profile.daily.get("best", 0)), int(profile.stats.get("daily_runs", 0))], 15, Palette.TEXT_DIM)
	var scores: Dictionary = profile.daily.get("scores", {})
	var dates: Array = scores.keys()
	dates.sort()
	dates.reverse()
	for date in dates.slice(0, 14):
		_line("%s   %d" % [date, int(scores[date])], 14)
	_line("Score: 10 per node, 25 per black sentry, 100 per layer, 250 for the final Core, 5 per clean fight.", 13, Palette.TEXT_DIM)


func _style() -> void:
	_line("Card back", 18, Palette.ENERGY)
	var backs := UiKit.flow(10)
	var current := str(profile.settings.get("card_back", "default"))
	for b in Records.card_backs(profile):
		var label := "Default" if b == "default" else ("Glitch" if b == Records.BACK_GLITCH else Lexicon.faction(b))
		var btn := UiKit.button(label, func() -> void:
			profile.settings["card_back"] = b
			CardView.back_style = b
			changed.emit()
			_refresh(), Vector2(150, 48), 15)
		btn.disabled = b == current
		backs.add_child(btn)
	_list.add_child(backs)
	var preview := CardView.new().setup(db.instance("jab"))
	preview.face_down = true
	var holder := CenterContainer.new()
	holder.add_child(preview)
	_list.add_child(holder)
	_line("Title", 18, Palette.ENERGY)
	var titles := UiKit.flow(10)
	var cur_t := str(profile.settings.get("title", ""))
	for t in Records.titles(profile):
		var name_t: String = "None" if t == "" else (str(db.exploits[t]["name"]) if db.exploits.has(t) else t)
		var tb := UiKit.button(name_t, func() -> void:
			profile.settings["title"] = t
			changed.emit()
			_refresh(), Vector2(180, 48), 14)
		tb.disabled = t == cur_t
		titles.add_child(tb)
	_list.add_child(titles)
	_line("Unlock more by completing full crew binders and logging exploits.", 13, Palette.TEXT_DIM)
