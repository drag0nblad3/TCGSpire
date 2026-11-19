class_name DeckOverlay
extends Control
## Full-screen card grid on top of everything. on_pick(index) gets the tapped
## card's index (or -1 for the button). Used for deck view, upgrade, removal and
## installing a mod (only cards that fit it can be picked; they preview with it).
## `low = true` (combat picks: Dump, recover) sits the cards just above the button,
## in the lower part of the screen where the thumb reaches; it scrolls past ~55%.

var _title := ""
var _cards: Array = []
var _button := ""
var _on_pick: Callable
var _preview_upgrade := false
var _pickable := false
var _mod: Dictionary = {}
var low := false


func setup(title: String, cards: Array, button_text: String, on_pick: Callable, pickable: bool = false, preview_upgrade: bool = false, mod: Dictionary = {}) -> DeckOverlay:
	_mod = mod
	_title = title
	_cards = cards
	_button = button_text
	_on_pick = on_pick
	_pickable = pickable
	_preview_upgrade = preview_upgrade
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(Palette.PANEL_BG, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var parts := UiKit.screen(14, BoxContainer.ALIGNMENT_END if low else BoxContainer.ALIGNMENT_BEGIN)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label(_title, 24))
	var inner := UiKit.scroll(v)
	if low:
		_fit_low(inner.get_parent())
	var grid := UiKit.flow(10)
	inner.add_child(grid)
	if _cards.is_empty():
		inner.add_child(UiKit.label("No cards here yet.", 18, Palette.TEXT_DIM))
	var maxed := RunState.deck_maxed(_cards)
	for i in _cards.size():
		var src: CardInstance = _cards[i]
		var shown := src
		var ok := true
		if _preview_upgrade:
			ok = src.can_level_up(maxed)
			if ok:
				shown = src.copy()
				shown.level_up()
		if not _mod.is_empty():
			ok = CardMods.can_apply(_mod, src)
			if ok:
				shown = src.copy()
				shown.mod = _mod
		var cv := CardView.new().setup(shown)
		if _preview_upgrade and ok:
			cv.before_text = src.text()
		cv.playable = not _pickable or ok
		if _pickable and cv.playable:
			cv.pressed.connect(func(_v: CardView) -> void: _close(i))
		if _preview_upgrade or not _mod.is_empty():
			# Under each card: what the upgrade or mod would change, or why it can't.
			var cell := UiKit.vbox(4, BoxContainer.ALIGNMENT_BEGIN)
			cell.add_child(cv)
			var why := ""
			if _preview_upgrade:
				why = _upgrade_note(src, shown) if ok else ("Fully upgraded." if src.upgraded else ("Max the rest of your deck to v2 first." if src.fw >= src.fw_scale.size() - 1 and src.def.rarity != "curse" and not src.def.upgrade.is_empty() else "Can't be upgraded."))
			else:
				why = CardMods.describe(_mod) if ok else ("Has %s." % src.mod_name() if not src.mod.is_empty() else "Doesn't fit.")
			var l := UiKit.label(why, 12, Palette.UPGRADED if ok else Palette.TEXT_DIM, true)
			l.custom_minimum_size = Vector2(CardView.SIZE.x, 0)
			cell.add_child(l)
			grid.add_child(cell)
		else:
			grid.add_child(cv)
	v.add_child(UiKit.button(_button, func() -> void: _close(-1)))
	if not _pickable:
		# Just a look at a pile: any tap (not a scroll) closes it.
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UiKit.tap_to_close(self, func() -> void: _close(-1))


## Low layout: the scroll is as tall as its rows of cards (capped at ~55% of the
## screen) instead of filling it, so the block stays bottom-aligned above the button.
func _fit_low(sc: ScrollContainer) -> void:
	var view := get_viewport_rect().size
	var gap := 10.0
	var per_row := maxi(1, floori((view.x - 32.0 + gap) / (CardView.SIZE.x + gap)))
	var rows := maxi(1, ceili(_cards.size() / float(per_row)))
	var need := rows * CardView.SIZE.y + (rows - 1) * gap
	sc.size_flags_vertical = Control.SIZE_SHRINK_END
	sc.custom_minimum_size.y = minf(need, view.y * 0.55)


## Short line under an upgrade preview. The card already shows changed numbers as 6→8,
## so only changes the card can't show (keywords, cost, new effects) are spelled out.
func _upgrade_note(src: CardInstance, shown: CardInstance) -> String:
	var only_numbers := CardView.diff_text(src.text(), shown.text()) != shown.text()
	if src.fw < src.fw_scale.size() - 1:
		return "v%d: numbers +%d%%" % [src.fw + 1, roundi((float(src.fw_scale[src.fw + 1]) - 1.0) * 100)]
	if only_numbers and src.cost() == shown.cost():
		return "Recompile (+)"
	return src.level_up_text()


func _close(i: int) -> void:
	queue_free()
	_on_pick.call(i)
