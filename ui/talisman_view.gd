class_name TalismanView
extends Control
## Illustrated hardware with event-driven activation effects and live status badges.
signal pressed(id: String)
var tid := ""
var rarity := "common"
var big := false
var definition: Dictionary = {}
var tracker: ImplantTracker
var run_context: RunState
var _texture: Texture2D
var _active_texture: Texture2D
var _art: Dictionary = {}
var _flash := 0.0
var _tap := Tap.new()
var _db: CardDB

func setup(id: String, db: CardDB, big_in: bool = false) -> TalismanView:
	tid = id
	_db = db
	big = big_in
	definition = db.talismans.get(id, {})
	rarity = str(definition.get("rarity", "common"))
	_texture = ImplantArt.texture_for(id)
	_active_texture = ImplantArt.texture_for(id, true)
	_art = ImplantArt.regions().get(id, {})
	custom_minimum_size = Vector2(92, 108) if big else Vector2(52, 68)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = text(db, id)
	set_process(false)
	return self

func activate() -> void:
	_flash = 0.72
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	queue_redraw()
	if _flash == 0.0:
		set_process(false)

func _gui_input(event: InputEvent) -> void:
	if _tap.feed(event) == "tap":
		pressed.emit(tid)
		accept_event()

func status() -> String:
	if tracker != null:
		return tracker.badge(definition)
	if run_context != null:
		if definition.has("run"):
			return "×%d" % int(run_context.implant_activations.get(tid, 0))
		if definition.get("flags_while_daemon", false):
			return "DAEMON"
		if definition.has("triggers"):
			return "ARMED"
		return "ON" if definition.has("flags") or definition.has("mods") or definition.has("daemon") else "TAKEN"
	return rarity.to_upper()

func _draw() -> void:
	var side := minf(size.x, size.y - 16.0)
	var origin := Vector2((size.x - side) / 2.0, 0)
	var rect := Rect2(origin, Vector2.ONE * side)
	var accent := Color(str(_art.get("accent", "#e8bb62")))
	var border: Color = Palette.RARITY.get(rarity, Palette.ENERGY) if rarity != "boss" else Palette.ENEMY
	var strength := sin(PI * clampf(_flash / 0.72, 0.0, 1.0))
	draw_style_box(_frame(border), rect)
	if _texture != null:
		var inset := rect.grow(-2)
		draw_texture_rect(_texture, inset, false)
		if _active_texture != null and strength > 0.0:
			draw_texture_rect(_active_texture, inset, false, Color(1, 1, 1, strength))
	else:
		Sigil.draw(self, rect.get_center(), side * 0.3, "talisman:" + tid, border)
	if _flash > 0.0:
		_draw_activation(rect, accent, strength)
	if tracker != null and definition.get("flags_while_daemon", false) and tracker.daemons.is_empty():
		draw_rect(rect.grow(-2), Color(0.06, 0.08, 0.1, 0.42))
	var badge := status()
	var font := ThemeDB.fallback_font
	var fs := 12 if not big else 14
	var text_width := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_rect(Rect2(origin + Vector2(0, side), Vector2(side, 16)), Palette.PANEL_BG)
	draw_string(font, origin + Vector2((side - text_width) * 0.5, side + 13), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.TEXT)
	# Exact numerical progress remains readable even at small icon sizes.
	if tracker != null:
		for i in definition.get("triggers", []).size():
			var trigger: Dictionary = definition["triggers"][i]
			if trigger.has("every"):
				var total := int(trigger["every"])
				var count := int(tracker.progress.get("%s:%d" % [tid, i], 0)) % total
				for pip in total:
					var width := (side - 8.0) / total
					draw_rect(Rect2(origin + Vector2(4 + pip * width, side - 6), Vector2(width - 1, 3)), accent if pip < count else Color(0.12, 0.14, 0.17, 0.8))
				break

func _frame(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.CARD_BG
	style.border_color = color
	style.set_border_width_all(2)
	return style

func _draw_activation(rect: Rect2, color: Color, strength: float) -> void:
	var s := rect.size.x
	var hot: Array = _art.get("hotspot", [0.5, 0.5])
	var center := rect.position + Vector2(float(hot[0]), float(hot[1])) * s
	var phase := 1.0 - _flash / 0.72
	color.a = strength * 0.4
	var radius := s * 0.15
	match _art.get("motion", "pulse"):
		"ring":
			draw_arc(center, radius, phase * TAU, phase * TAU + PI * 1.4, 24, color, maxf(1.2, s * 0.025), true)
			draw_circle(center + Vector2.from_angle(phase * TAU) * radius, s * 0.035, color)
		"spark":
			var points := PackedVector2Array([center + Vector2(-0.18, 0.02) * s, center + Vector2(-0.06, -0.07) * s, center + Vector2(0.02, 0.07) * s, center + Vector2(0.16, -0.03) * s])
			draw_polyline(points, color, maxf(1.5, s * 0.02), true)
		"slide":
			for direction in [-1, 1]:
				var p := center + Vector2(direction * s * 0.12 * strength, 0)
				draw_line(p + Vector2(0, -radius), p + Vector2(0, radius), color, maxf(2, s * 0.04), true)
		"vent":
			for i in 3:
				var p := center + Vector2((i - 1) * 0.08, -phase * 0.24) * s
				draw_line(p, p + Vector2(0, -s * 0.12), color, maxf(1.5, s * 0.025), true)
		"signal":
			var p := center + Vector2(phase * s * 0.2, 0)
			draw_rect(Rect2(p - Vector2(s * 0.08, s * 0.04), Vector2(s * 0.16, s * 0.08)), color)
			draw_arc(center, radius * (1.0 + phase), -0.8, 0.8, 16, color, 1.5, true)
		"scan":
			var y := center.y + (phase - 0.5) * radius * 2
			draw_line(Vector2(center.x - radius, y), Vector2(center.x + radius, y), color, maxf(1.5, s * 0.02), true)
		_:
			draw_circle(center, radius * strength, Color(color, strength * 0.28))
			draw_arc(center, radius * (0.8 + phase), 0, TAU, 24, color, maxf(1.5, s * 0.02), true)

func inspect() -> void:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(Palette.PANEL_BG, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(bg)
	var parts := UiKit.screen(14)
	overlay.add_child(parts[0])
	var column := UiKit.scroll(parts[1])
	column.add_child(UiKit.label(str(definition.get("name", tid)), 28))
	var art := TalismanView.new().setup(tid, _db, true)
	art.custom_minimum_size = Vector2(240, 256)
	art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	art.tracker = tracker
	art.run_context = run_context
	column.add_child(art)
	column.add_child(UiKit.label(Talismans.describe(definition), 18, Palette.TEXT, true))
	if tracker != null:
		column.add_child(UiKit.label(tracker.detail(definition), 16, Palette.ENERGY, true))
	elif run_context != null and definition.has("run"):
		column.add_child(UiKit.label("Activated %d times this run" % int(run_context.implant_activations.get(tid, 0)), 16, Palette.ENERGY))
	if definition.has("triggers") or definition.has("run"):
		column.add_child(UiKit.button("Preview activation", art.activate))
	column.add_child(UiKit.button("Close", overlay.queue_free))
	get_tree().root.add_child(overlay)

static func strip(parent: Control) -> HBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 78
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var row := UiKit.hbox(6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)
	return row

static func text(db: CardDB, id: String) -> String:
	var t: Dictionary = db.talismans.get(id, {})
	return "%s (%s implant)\n%s" % [t.get("name", id), t.get("rarity", ""), Talismans.describe(t)]
