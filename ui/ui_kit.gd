class_name UiKit
extends RefCounted
## Tiny helpers so screens are built in a few lines of code (no .tscn files).


static func label(text: String, font_size: int = 16, col: Color = Palette.TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font_size >= 24:
		l.add_theme_font_override("font", Palette.display())
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 560
	return l


static func button(text: String, on_press: Callable, min_size: Vector2 = Vector2(220, 60), font_size: int = 18) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", font_size)
	b.pressed.connect(on_press)
	return b


static func vbox(sep: int = 16, align: BoxContainer.AlignmentMode = BoxContainer.ALIGNMENT_CENTER) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.alignment = align
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", sep)
	return h


static func flow(sep: int = 12) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.alignment = FlowContainer.ALIGNMENT_CENTER
	f.add_theme_constant_override("h_separation", sep)
	f.add_theme_constant_override("v_separation", sep)
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return f


## Full-screen root with side margins. Returns [root, content_vbox].
static func screen(sep: int = 20, align: BoxContainer.AlignmentMode = BoxContainer.ALIGNMENT_CENTER) -> Array:
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		root.add_theme_constant_override("margin_" + side, 16)
	for side in ["top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 28)
	var v := vbox(sep, align)
	root.add_child(v)
	return [root, v]


## Vertical scroll area that expands to fill. Add children to the returned inner box.
static func scroll(parent: Control) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(sc)
	var inner := vbox(12, BoxContainer.ALIGNMENT_BEGIN)
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(inner)
	return inner


static func panel(child: Control, col: Color = Palette.PANEL_BG) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(maxi(Palette.RADIUS, 4))
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.add_child(child)
	return p


## Shows a short message that fades out, on top of `host`.
static func toast(host: Node, text: String, seconds: float = 2.2) -> void:
	# Only one toast at a time: a new one replaces the old.
	for n in host.get_children():
		if n.has_meta("toast"):
			n.queue_free()
	var l := label(text, 16, Palette.TEXT, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var p := panel(l, Color(Palette.PANEL_BG, 0.97))
	p.set_meta("toast", true)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.border_color = Color(Palette.ENERGY, 0.7)
	sb.set_border_width_all(2)
	host.add_child(p)
	p.position = Vector2(60, 150)
	p.z_index = 50
	var tw := p.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)
