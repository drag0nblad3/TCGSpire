class_name CombatLogOverlay
extends Control
## Full-screen history of the current fight (CombatLog lines), newest at the bottom.
## Scroll to read; any tap closes it.

var _combat: Combat


func setup(c: Combat) -> CombatLogOverlay:
	_combat = c
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(Palette.PANEL_BG, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var parts := UiKit.screen(12, BoxContainer.ALIGNMENT_BEGIN)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("Combat log", 24))
	var inner := UiKit.scroll(v)
	inner.add_theme_constant_override("separation", 4)
	var lines := CombatLog.lines(_combat)
	if lines.is_empty():
		inner.add_child(UiKit.label("Nothing has happened yet.", 18, Palette.TEXT_DIM))
	for l: Dictionary in lines:
		inner.add_child(_row(l))
	v.add_child(UiKit.label("Tap anywhere to close", 14, Palette.TEXT_DIM))
	UiKit.tap_to_close(self)
	# Open on the latest actions.
	var sc := inner.get_parent() as ScrollContainer
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func _row(l: Dictionary) -> Control:
	var side := str(l["side"])
	var indent: bool = l["indent"]
	var col := Palette.TEXT
	var fs := 17
	match side:
		"head":
			col = Palette.ENERGY
			fs = 18
		"enemy":
			col = Palette.ENEMY
		"info":
			col = Palette.TEXT_DIM
	if indent:
		col = Color(col, 0.75) if side != "head" else col
		fs = 15
	var lab := UiKit.label(str(l["text"]), fs, col, true)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 28 if indent else 0)
	if side == "head":
		m.add_theme_constant_override("margin_top", 10)
	m.add_child(lab)
	return m
