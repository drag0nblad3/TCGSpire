class_name GameMenu
extends Control
## Full-screen menu on top of everything (pause menu, settings, confirms).
## entries: [[text, Callable], ...]; a press closes the menu, then calls it.
## A null Callable just closes. Text starting with "!" is drawn as a danger button.

var _title := ""
var _note := ""
var _entries: Array = []


func setup(title: String, entries: Array, note: String = "") -> GameMenu:
	_title = title
	_entries = entries
	_note = note
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(Palette.PANEL_BG, 0.96)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var parts := UiKit.screen(18)
	add_child(parts[0])
	var v: VBoxContainer = UiKit.scroll(parts[1])
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(UiKit.label(_title, 34, Palette.ENERGY))
	if _note != "":
		v.add_child(UiKit.label(_note, 16, Palette.TEXT_DIM, true))
	for e in _entries:
		var text: String = e[0]
		var danger := text.begins_with("!")
		var cb: Variant = e[1]
		var b := UiKit.button(text.trim_prefix("!"), func() -> void:
			queue_free()
			if cb is Callable:
				(cb as Callable).call(), Vector2(380, 64), 20)
		if danger:
			b.add_theme_color_override("font_color", Palette.HP)
		v.add_child(b)
