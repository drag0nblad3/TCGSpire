class_name MapScreen
extends Control
## Scrollable act map. Drawn entirely in code; tap a glowing node to travel.

signal node_chosen(id: int)

const ROW_H := 104.0
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
	var title := UiKit.hbox(12)
	title.add_child(UiKit.label("THE STACK / %02d" % run.act, 24, Palette.ENERGY))
	v.add_child(title)
	v.add_child(UiKit.label(_hint(), 15, Palette.TEXT_DIM))
	var legend := UiKit.flow(12)
	for kind in ["fight", "elite", "event", "rest", "shop", "treasure", "boss"]:
		var item := UiKit.hbox(4)
		var icon := Symbols.badge(kind, 26)
		icon.modulate = Palette.NODE[kind]
		item.add_child(icon)
		item.add_child(UiKit.label(NAMES[kind], 14, Palette.TEXT))
		legend.add_child(item)
	v.add_child(legend)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(0, ROW_H * (run.map.rows.size() + 0.6))
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_canvas_input)
	_scroll.add_child(_canvas)
	# Scroll so the current row is visible (map is drawn bottom-up).
	await get_tree().process_frame
	var row := 0 if run.node_id < 0 else int(run.map.node(run.node_id)["row"])
	_scroll.scroll_vertical = int(_node_pos(0, 1, row).y - _scroll.size.y * 0.6)


## Mentions sidesteps only when the run has earned some (Lateral Shunt, Ghost Routing).
func _hint() -> String:
	var left := run.sidesteps_left()
	if not run.side_moves().is_empty():
		return "Climb, or sidestep along this floor (no stop) · %d sidestep%s left" % [left, "" if left == 1 else "s"]
	if left > 0:
		return "Choose a lit node · %d sidestep%s left this layer" % [left, "" if left == 1 else "s"]
	return "Choose a lit node · Walls block some routes · Scroll up toward the Core"


func _process(_dt: float) -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _node_pos(col: int, cols: int, row: int) -> Vector2:
	var w := _canvas.size.x
	var jitter := float(((col * 7 + row * 13) % 5) - 2) * 6.0
	return Vector2((col + 0.5) / cols * w + jitter, (run.map.rows.size() - row) * ROW_H - 20)


func _pos(id: int) -> Vector2:
	var n: Dictionary = run.map.node(id)
	return _node_pos(n["col"], n["cols"], n["row"])


func _draw_map() -> void:
	var avail := run.available_nodes()
	var t := Time.get_ticks_msec() / 1000.0
	var font := Palette.font()
	var width := _canvas.size.x
	_canvas.draw_rect(Rect2(Vector2.ZERO, _canvas.size), Color(Palette.CARD_BG, 0.48))
	# Quiet server architecture behind the route: stacked decks, rails and rack lights.
	for row in run.map.rows.size():
		var y := _node_pos(0, 1, row).y
		var deck := Rect2(8, y - 43, width - 16, 86)
		_canvas.draw_style_box(_plate(Color(Palette.PANEL_BG, 0.18), Color(Palette.TEXT_DIM, 0.08)), deck)
		_canvas.draw_string(font, Vector2(17, y - 24), "%02d" % (row + 1), HORIZONTAL_ALIGNMENT_LEFT, 30, 12, Palette.TEXT_DIM)
		for side in [18.0, width - 21]:
			for k in 3:
				_canvas.draw_rect(Rect2(side, y + 14 + k * 6, 3, 2), Color(Palette.ENERGY, 0.25))
	for n in run.map.nodes:
		for nx in n["next"]:
			var on_path: bool = n["id"] in run.path and nx in run.path
			var next_step: bool = n["id"] == run.node_id and nx in avail
			var phase := float(int(n["id"]) * 17 + int(nx) * 7) * 0.31
			# Slow breathing with restrained signal jitter; never blink a route off.
			var breathe := 0.5 + 0.5 * sin(t * 1.8 + phase)
			var jitter := sin(t * 7.0 + phase) * sin(t * 4.3 + phase * 2.0)
			var strength := clampf(0.48 + breathe * 0.30 + jitter * 0.05, 0.43, 0.83)
			var col := Color(Palette.ENERGY if next_step else Palette.TEXT_DIM, strength)
			if on_path:
				col = Palette.ENERGY
			var a := _pos(n["id"])
			var b := _pos(nx)
			var mid := (a.y + b.y) / 2
			var wire := PackedVector2Array([a, Vector2(a.x, mid + 10), Vector2(b.x, mid - 10), b])
			_canvas.draw_polyline(wire, Color(Palette.CARD_BG, 0.95), 8, true)
			if on_path:
				_canvas.draw_polyline(wire, Color(Palette.ENERGY, 0.16), 10, true)
			_canvas.draw_polyline(wire, col, 5 if on_path else 3, true)
			if not on_path:
				_route_pulse(wire, fposmod(t * 0.24 + phase, 1.0), Color(Palette.ENERGY, 0.65 if next_step else 0.38))
	_draw_walls()
	# Sidesteps already taken stay drawn as solid sideways links on the trail.
	for i in range(1, run.path.size()):
		var pa: Dictionary = run.map.node(run.path[i - 1])
		var pb: Dictionary = run.map.node(run.path[i])
		if pa["row"] == pb["row"]:
			_canvas.draw_line(_pos(pa["id"]), _pos(pb["id"]), Color(Palette.ENERGY, 0.16), 10, true)
			_canvas.draw_line(_pos(pa["id"]), _pos(pb["id"]), Palette.ENERGY, 5, true)
	# Sidesteps open from the current node: a dashed sideways link with an arrow.
	for sid in run.side_moves():
		var a := _pos(run.node_id)
		var b := _pos(sid)
		var dir := signf(b.x - a.x)
		var y := (a.y + b.y) / 2.0
		var from := Vector2(a.x + dir * 30, y)
		var to := Vector2(b.x - dir * 34, y)
		var pulse := 0.65 + 0.35 * sin(t * 3.0)
		_canvas.draw_line(from, to, Color(Palette.CARD_BG, 0.95), 8, true)
		_canvas.draw_dashed_line(from, to, Color(Palette.ENERGY, pulse), 3, 9, true)
		_canvas.draw_polyline(PackedVector2Array([to + Vector2(-dir * 9, -8), to, to + Vector2(-dir * 9, 8)]), Color(Palette.ENERGY, pulse), 3, true)
		var mid := (from + to) / 2.0
		_canvas.draw_string(font, mid + Vector2(-60, -9), "SIDESTEP · NO STOP", HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Palette.ENERGY)
	for n in run.map.nodes:
		var p := _pos(n["id"])
		var col: Color = Palette.NODE[n["type"]]
		var r := 30.0 if n["type"] == "boss" else 24.0
		var is_avail: bool = n["id"] in avail
		var visited: bool = n["id"] in run.path
		var passed: bool = visited and run.was_sidestep(run.path.find(n["id"]))
		var current: bool = n["id"] == run.node_id
		if not is_avail and not visited and run.node_id >= 0 and n["row"] <= run.map.node(run.node_id)["row"]:
			col = Color(col, 0.3)
		if is_avail:
			draw_glow(p, r + 8 + 2 * sin(t * 3.0), col)
		_canvas.draw_style_box(_plate(Palette.CARD_BG, col, 3 if is_avail or current else 1), Rect2(p - Vector2.ONE * r, Vector2.ONE * r * 2))
		Symbols.draw_on(_canvas, p, r * 0.75, n["type"], col)
		# Labels and shapes make node types readable without relying on color.
		_canvas.draw_string(font, p + Vector2(-55, r + 17), NAMES[n["type"]], HORIZONTAL_ALIGNMENT_CENTER, 110, 14, col)
		if visited and not passed:
			var c := p + Vector2(r - 1, -r + 1)
			_canvas.draw_circle(c, 8, Palette.ENERGY)
			_canvas.draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-1, 3), c + Vector2(4, -3)]), Palette.CARD_BG, 2, true)
		if current:
			_canvas.draw_arc(p, r + 7, PI * 0.1, PI * 0.9, 24, Palette.ENERGY, 3, true)


## Short firewall walls. Horizontal: a ghost of each cut wire with a bar across it.
## Vertical: a bar standing between two neighbours on a floor (or two floors).
func _draw_walls() -> void:
	for w in run.map.walls:
		if w["kind"] == "h":
			var xs: Array = []
			var y := 0.0
			for link in w["links"]:
				var a := _pos(int(link[0]))
				var b := _pos(int(link[1]))
				y = (a.y + b.y) / 2.0
				var ghost := PackedVector2Array([a, Vector2(a.x, y + 10), Vector2(b.x, y - 10), b])
				for i in range(ghost.size() - 1):
					_canvas.draw_dashed_line(ghost[i], ghost[i + 1], Color(Palette.TEXT_DIM, 0.42), 2, 6, true)
				xs.append((a.x + b.x) / 2.0)
			_wall_line([Vector2(xs.min() - 26, y), Vector2(xs.max() + 26, y)])
		else:
			var x := 0.0
			var ys: Array = []
			for pair in w["pairs"]:
				var a := _pos(int(pair[0]))
				var b := _pos(int(pair[1]))
				x += (a.x + b.x) / 2.0 / w["pairs"].size()
				ys.append(a.y)
			_wall_line([Vector2(x, ys.max() + 34), Vector2(x, ys.min() - 34)])


func _wall_line(pts: Array) -> void:
	var line := PackedVector2Array(pts)
	_canvas.draw_polyline(line, Color(Palette.CARD_BG, 0.95), 12, true)
	_canvas.draw_polyline(line, Color(Palette.ENEMY, 0.9), 7, true)
	_canvas.draw_polyline(line, Color(Palette.TEXT, 0.55), 2, true)
	for p in [line[0], line[line.size() - 1]]:
		_canvas.draw_circle(p, 5, Palette.ENEMY)


## A short packet of light travels along the actual elbowed wire, bottom to top.
func _route_pulse(wire: PackedVector2Array, progress: float, color: Color) -> void:
	var length := 0.0
	for i in range(wire.size() - 1):
		length += wire[i].distance_to(wire[i + 1])
	var head := progress * (length + 28.0)
	var cursor := 0.0
	for i in range(wire.size() - 1):
		var segment := wire[i].distance_to(wire[i + 1])
		if segment <= 0.0:
			continue
		var start := maxf(head - 28.0, cursor)
		var end := minf(head, cursor + segment)
		if end > start:
			var a := wire[i].lerp(wire[i + 1], (start - cursor) / segment)
			var b := wire[i].lerp(wire[i + 1], (end - cursor) / segment)
			_canvas.draw_line(a, b, color, 4, true)
		cursor += segment


func _plate(fill: Color, edge: Color, border: int = 1) -> StyleBoxFlat:
	var plate := StyleBoxFlat.new()
	plate.bg_color = fill
	plate.border_color = edge
	plate.set_border_width_all(border)
	plate.set_corner_radius_all(7)
	return plate


func draw_glow(p: Vector2, r: float, col: Color) -> void:
	_canvas.draw_circle(p, r, Color(col, 0.18))


var _tap := Tap.new()


func _on_canvas_input(event: InputEvent) -> void:
	# Tap (not drag) so scrolling the map never picks a node by accident.
	if _tap.feed(event) != "tap":
		return
	for id in run.available_nodes():
		if _pos(id).distance_to(event.position) < 44.0:
			node_chosen.emit(id)
			return
