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
	b.pressed.connect(func() -> void: GameAudio.play("tap"))
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
## Screen edges the OS keeps for itself (notch, rounded corners, status/nav bars), in
## viewport units: {left, top, right, bottom}. All zero on desktop windows.
static func safe_insets(node: CanvasItem) -> Dictionary:
	var out := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0 or DisplayServer.get_name() == "headless":
		return out
	var pos := Vector2(DisplayServer.window_get_position())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if safe.size.x <= 0:
		return out
	var k := node.get_viewport_rect().size.x / win.x
	out["left"] = maxf(0.0, safe.position.x - pos.x) * k
	out["top"] = maxf(0.0, safe.position.y - pos.y) * k
	out["right"] = maxf(0.0, (pos.x + win.x) - safe.end.x) * k
	out["bottom"] = maxf(0.0, (pos.y + win.y) - safe.end.y) * k
	return out


## Top-right corner for a corner button of width `w`: inside the safe area plus a thumb margin.
static func corner_pos(node: CanvasItem, w: float, margin: float = 16.0) -> Vector2:
	var ins := safe_insets(node)
	return Vector2(node.get_viewport_rect().size.x - w - margin - float(ins["right"]), margin + float(ins["top"]))


## A short message that slides down from the top as a full-width banner, then slides away.
## It ignores input, so it never blocks a tap.
static func toast(host: Node, text: String, seconds: float = 2.2) -> void:
	# Only one toast at a time: a new one replaces the old.
	for n in host.get_children():
		if n.has_meta("toast"):
			n.queue_free()
	var l := label(text, 17, Palette.TEXT, true)
	l.custom_minimum_size.x = 0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var p := panel(l, Color(Palette.PANEL_BG, 0.98))
	p.set_meta("toast", true)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.border_color = Color(Palette.ENERGY, 0.8)
	sb.border_width_bottom = 3
	sb.set_corner_radius_all(0)
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	host.add_child(p)
	p.z_index = 50
	var w: float = (host as CanvasItem).get_viewport_rect().size.x if host is CanvasItem else 720.0
	var top := float(safe_insets(host as CanvasItem)["top"]) if host is CanvasItem else 0.0
	p.custom_minimum_size.x = w - 24
	p.size = Vector2(w - 24, 0)
	p.reset_size()
	p.position = Vector2(12, -p.size.y - 8)
	var tw := p.create_tween()
	tw.tween_property(p, "position:y", top, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(seconds)
	tw.tween_property(p, "position:y", -p.size.y - 8, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(p.queue_free)


## Main action on a screen: solid accent fill and dark text, so it stands out from the
## outlined secondary buttons around it.
static func primary(b: Button) -> Button:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(Palette.RADIUS)
		sb.set_content_margin_all(10)
		sb.bg_color = Palette.ENERGY
		if state == "hover":
			sb.bg_color = Palette.ENERGY.lightened(0.15)
		elif state == "pressed":
			sb.bg_color = Palette.ENERGY.darkened(0.25)
		elif state == "disabled":
			sb.bg_color = Color(Palette.ENERGY, 0.25)
		elif state == "focus":
			sb.draw_center = false
		sb.border_color = Palette.ENERGY.lightened(0.35)
		if state != "focus":
			sb.set_border_width_all(maxi(Palette.BORDER, 2))
		sb.shadow_color = Color(Palette.ENERGY, 0.35)
		sb.shadow_size = 0 if state in ["disabled", "focus"] else 10
		b.add_theme_stylebox_override(state, sb)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, Palette.CARD_BG)
	b.add_theme_color_override("font_disabled_color", Color(Palette.CARD_BG, 0.6))
	return b
