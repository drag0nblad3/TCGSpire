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
	top.add_child(UiKit.label("HP %d/%d" % [run.hp, run.max_hp], 18, Palette.HP))
	top.add_child(UiKit.label("Gold %d" % run.gold, 18, Palette.ENERGY))
	top.add_child(UiKit.label("Floor %d" % run.floor_num, 18, Palette.TEXT_DIM))
	if run.heat > 0:
		top.add_child(UiKit.label("Heat %d" % run.heat, 18, Palette.HP))
	top.add_child(UiKit.button("Deck %d" % run.deck.size(), func() -> void: _show_deck(), Vector2(110, 40), 15))
	add_child(top)
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
