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
	top.add_child(UiKit.label("HP %d/%d" % [run.hp, run.max_hp], 22, Palette.HP))
	top.add_child(UiKit.label("%d creds" % run.gold, 18, Palette.ENERGY))
	top.add_child(UiKit.label("Layer %d · Node %d" % [run.act, run.floor_num], 18, Palette.TEXT_DIM))
	if run.heat > 0:
		top.add_child(UiKit.label("Heat %d" % run.heat, 18, Palette.HP))
	top.add_child(UiKit.button("Deck %d" % run.deck.size(), func() -> void: _show_deck(), Vector2(110, 40), 15))
	if not run.perks.is_empty():
		top.add_child(UiKit.button("Perks %d" % run.perks.size(), func() -> void:
			UiKit.toast(get_tree().root, perk_text(run), 4.0), Vector2(96, 40), 15))
	add_child(top)
	if run.job != "":
		var against: Array = run.banned.map(func(x: String) -> String: return Lexicon.faction(x))
		var job_row := UiKit.hbox(8)
		job_row.add_child(Symbols.badge(run.job, 28))
		add_child(job_row)
		job_row.add_child(UiKit.label("%s for %s  ·  against %s" % ["Daily breach" if run.daily != "" else "Job", Jobs.info(run.db, run.job).get("client", run.job), " + ".join(against)], 14, Palette.faction(run.job)))
		if not run.clauses.is_empty():
			job_row.add_child(UiKit.button("Bonuses %d/%d" % [run.clauses.filter(func(id: String) -> bool: return Records.clause_met(run.db, run, id)).size(), run.clauses.size()], func() -> void:
				UiKit.toast(get_tree().root, clause_text(run), 5.0), Vector2(124, 34), 13))
	if not run.talismans.is_empty():
		var row := UiKit.hbox(6)
		for tid in run.talismans:
			var tv := TalismanView.new().setup(tid, run.db)
			tv.pressed.connect(func(id: String) -> void: UiKit.toast(get_tree().root, TalismanView.text(run.db, id)))
			row.add_child(tv)
		add_child(row)


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
