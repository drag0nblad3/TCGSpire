class_name DeckOverlay
extends Control
## Full-screen card grid on top of everything. on_pick(index) gets the tapped
## card's index (or -1 for the button). Used for deck view, upgrade, removal and
## installing a mod (only cards that fit it can be picked; they preview with it).

var _title := ""
var _cards: Array = []
var _button := ""
var _on_pick: Callable
var _preview_upgrade := false
var _pickable := false
var _mod: Dictionary = {}


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
	var parts := UiKit.screen(14, BoxContainer.ALIGNMENT_BEGIN)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label(_title, 24))
	var inner := UiKit.scroll(v)
	var grid := UiKit.flow(10)
	inner.add_child(grid)
	if _cards.is_empty():
		inner.add_child(UiKit.label("No cards here yet.", 18, Palette.TEXT_DIM))
	for i in _cards.size():
		var src: CardInstance = _cards[i]
		var shown := src
		var ok := true
		if _preview_upgrade:
			ok = not src.upgraded and src.def.rarity != "curse"
			if ok:
				shown = src.copy()
				shown.upgraded = true
		if not _mod.is_empty():
			ok = CardMods.can_apply(_mod, src)
			if ok:
				shown = src.copy()
				shown.mod = _mod
		var cv := CardView.new().setup(shown)
		cv.playable = not _pickable or ok
		if _pickable and cv.playable:
			cv.pressed.connect(func(_v: CardView) -> void: _close(i))
		grid.add_child(cv)
	v.add_child(UiKit.button(_button, func() -> void: _close(-1)))


func _close(i: int) -> void:
	queue_free()
	_on_pick.call(i)
