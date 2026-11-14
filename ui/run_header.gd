class_name RunHeader
extends VBoxContainer
## HP / gold / floor / deck line plus the talisman row. Shown on every run screen.

signal deck_pressed

var run: RunState


func setup(r: RunState) -> RunHeader:
	run = r
	return self


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var top := UiKit.hbox(18)
	top.add_child(UiKit.label("HP %d/%d" % [run.hp, run.max_hp], 23, Palette.HP))
	top.add_child(UiKit.label("%d creds" % run.gold, 20, Palette.ENERGY))
	top.add_child(UiKit.label(("Depth %d · Node %d" % [run.deep, run.floor_num]) if run.deep > 0 else ("Layer %d · Node %d" % [run.act, run.floor_num]), 18, Palette.TEXT_DIM))
	if run.heat > 0:
		top.add_child(UiKit.label("Heat %d" % run.heat, 18, Palette.HP))
	add_child(top)
	if run.job != "":
		var against: Array = run.banned.map(func(x: String) -> String: return Lexicon.faction(x))
		var job_row := UiKit.hbox(8)
		job_row.add_child(Symbols.badge(run.job, 28))
		add_child(job_row)
		job_row.add_child(UiKit.label("%s for %s  ·  against %s" % ["Weekly challenge" if run.weekly != "" else ("Daily breach" if run.daily != "" else "Job"), Jobs.info(run.db, run.job).get("client", run.job), " + ".join(against)], 14, Palette.faction(run.job)))
	# Buttons sit on their own centred row, clear of the corner Menu button.
	var btns := UiKit.hbox(8)
	btns.add_child(UiKit.button("Deck %d" % run.deck.size(), func() -> void: _show_deck(), Vector2(104, 40), 15))
	if not run.perks.is_empty():
		btns.add_child(_info_button("Subroutines %d" % run.perks.size(), "perks", func() -> String: return perk_text(run), 150))
	if not run.clauses.is_empty():
		btns.add_child(_info_button("Bonuses %d/%d" % [run.clauses.filter(func(id: String) -> bool: return Records.clause_met(run.db, run, id)).size(), run.clauses.size()],
			"clauses", func() -> String: return clause_text(run), 128))
	if not run.weekly_mods.is_empty():
		btns.add_child(_info_button("Rule changes", "weekly", func() -> String:
			return "\n".join(run.weekly_mods.map(func(id: String) -> String: return Weekly.describe(run.db, id))), 128))
	add_child(btns)
	_info = UiKit.label("", 15, Palette.TEXT, true)
	_info.custom_minimum_size.x = 600
	_info_box = UiKit.panel(_info)
	_info_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_info_box.visible = false
	add_child(_info_box)
	if not run.talismans.is_empty():
		var row := TalismanView.strip(self)
		for tid in run.talismans:
			var tv := TalismanView.new().setup(tid, run.db)
			tv.run_context = run
			tv.pressed.connect(func(_id: String) -> void: tv.inspect())
			if tid in run.implant_recent:
				tv.activate()
			row.add_child(tv)
		run.implant_recent.clear()


var _info: Label
var _info_box: PanelContainer
var _info_key := ""


func _info_button(text: String, key: String, body: Callable, width: float) -> Button:
	return UiKit.button(text, func() -> void: toggle_info(key, body.call()), Vector2(width, 40), 15)


## Shows `text` in the panel under the buttons; the same button again hides it.
func toggle_info(key: String, text: String) -> void:
	if _info_box.visible and _info_key == key:
		_info_box.visible = false
		_info_key = ""
		return
	_info_key = key
	_info.text = text
	_info_box.visible = true


func _show_deck() -> void:
	var overlay := DeckOverlay.new().setup("Your deck", run.deck, "Close", func(_i: int) -> void: pass)
	get_tree().root.add_child(overlay)


## The job's bonus clauses with a mark for each one already met.
static func clause_text(r: RunState) -> String:
	var lines: Array[String] = ["Contract bonuses: meet them for extra rep."]
	for id in r.clauses:
		lines.append(("[met] " if Records.clause_met(r.db, r, id) else "") + Records.clause_text(r.db, id, r.heat, r.job))
	return "\n".join(lines)


## One line per loaded subroutine.
static func perk_text(r: RunState) -> String:
	var lines: Array[String] = ["Subroutines (perks for this run):"]
	for pid in r.perks:
		var p: Dictionary = r.db.perks[pid]
		lines.append("%s: %s" % [p["name"], Perks.describe(p)])
	return "\n".join(lines)
