class_name MapScreen
extends Control
## Scrollable act map. Drawn entirely in code; tap a glowing node to travel.

signal node_chosen(id: int)

const ROW_H := 104.0
const GLYPH := {"fight": "S", "elite": "X", "rest": "H", "shop": "$", "event": "?", "treasure": "C", "boss": "B"}
const NAMES := {"fight": "Sentry", "elite": "Black sentry", "rest": "Safehouse", "shop": "Fixer", "event": "Signal", "treasure": "Cache", "boss": "Core"}

var run: RunState
var _canvas: Control
var _scroll: ScrollContainer


func setup(r: RunState) -> MapScreen:
	run = r
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parts := UiKit.screen(10, BoxContainer.ALIGNMENT_BEGIN)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	v.add_child(RunHeader.new().setup(run))
	var legend := UiKit.hbox(14)
	for t in ["fight", "elite", "event", "rest", "shop", "treasure"]:
		legend.add_child(UiKit.label("%s %s" % [GLYPH[t], NAMES[t]], 12, Palette.NODE[t]))
	v.add_child(legend)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(680, ROW_H * (run.map.rows.size() + 0.6))
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_canvas_input)
	_scroll.add_child(_canvas)
	# Scroll so the current row is visible (map is drawn bottom-up).
	await get_tree().process_frame
	var row := 0 if run.node_id < 0 else int(run.map.node(run.node_id)["row"])
	_scroll.scroll_vertical = int(_node_pos(0, 1, row).y - _scroll.size.y * 0.6)


func _process(_dt: float) -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _node_pos(col: int, cols: int, row: int) -> Vector2:
	var w := _canvas.custom_minimum_size.x
	var jitter := float(((col * 7 + row * 13) % 5) - 2) * 6.0
	return Vector2((col + 0.5) / cols * w + jitter, (run.map.rows.size() - row) * ROW_H - 20)


func _pos(id: int) -> Vector2:
	var n: Dictionary = run.map.node(id)
	return _node_pos(n["col"], n["cols"], n["row"])


func _draw_map() -> void:
	var avail := run.available_nodes()
	var t := Time.get_ticks_msec() / 1000.0
	var font := Palette.font()
	for n in run.map.nodes:
		for nx in n["next"]:
			var on_path: bool = n["id"] in run.path and nx in run.path
			var col := Color(Palette.ENERGY, 0.9) if on_path else Color(Palette.TEXT_DIM, 0.25)
			_dashed(_pos(n["id"]), _pos(nx), col, 3.0 if on_path else 2.0)
	for n in run.map.nodes:
		var p := _pos(n["id"])
		var col: Color = Palette.NODE[n["type"]]
		var r := 30.0 if n["type"] == "boss" else 18.0
		var is_avail: bool = n["id"] in avail
		var visited: bool = n["id"] in run.path
		if not is_avail and not visited and run.node_id >= 0 and n["row"] <= run.map.node(run.node_id)["row"]:
			col = Color(col, 0.3)
		if is_avail:
			draw_glow(p, r + 8 + 3 * sin(t * 4.0), col)
		_canvas.draw_circle(p, r, Palette.CARD_BG)
		_canvas.draw_arc(p, r, 0, TAU, 32, col, 3.0 if is_avail else 2.0, true)
		if n["type"] == "boss":
			Sigil.draw(_canvas, p, r * 0.7, "boss:" + str(n["encounter"]), col, t)
		else:
			_canvas.draw_string(font, p + Vector2(-r, 6), GLYPH[n["type"]], HORIZONTAL_ALIGNMENT_CENTER, r * 2, 18, col)
		if visited:
			_canvas.draw_circle(p + Vector2(r * 0.75, -r * 0.75), 5, Palette.ENERGY)


func draw_glow(p: Vector2, r: float, col: Color) -> void:
	_canvas.draw_circle(p, r, Color(col, 0.18))


func _dashed(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var d := a.distance_to(b)
	var steps := int(d / 12.0)
	for i in steps:
		if i % 2 == 0:
			_canvas.draw_line(a.lerp(b, float(i) / steps), a.lerp(b, float(i + 1) / steps), col, w, true)


var _tap := Tap.new()


func _on_canvas_input(event: InputEvent) -> void:
	# Tap (not drag) so scrolling the map never picks a node by accident.
	if _tap.feed(event) != "tap":
		return
	for id in run.available_nodes():
		if _pos(id).distance_to(event.position) < 44.0:
			node_chosen.emit(id)
			return
