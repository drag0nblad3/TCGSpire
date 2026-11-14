class_name MapScreen
extends Control
## Scrollable act map. Drawn entirely in code; tap a glowing node to travel.

signal node_chosen(id: int)

const ROW_H := 104.0
const NAMES := {"fight": "Sentry", "elite": "Black sentry", "rest": "Safehouse", "shop": "Fixer", "event": "Signal", "treasure": "Cache", "vault": "Vault", "boss": "Core"}
## Plain meaning beside each flavor name in the legend.
const PLAIN := {"fight": "fight", "elite": "elite fight", "rest": "rest", "shop": "shop", "event": "event", "treasure": "loot", "vault": "jump-only elite + loot", "boss": "boss"}

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
	if run.jumps_total() > 0:
		v.add_child(JumpTracker.new().setup(run))
	var hint_row := UiKit.hbox(10)
	hint_row.add_child(UiKit.label(_hint(), 15, Palette.TEXT_DIM, true))
	v.add_child(hint_row)
	var legend := UiKit.flow(12)
	for kind in ["fight", "elite", "event", "rest", "shop", "treasure", "vault", "boss"]:
		var item := UiKit.hbox(4)
		var icon := Symbols.badge(kind, 26)
		icon.modulate = Palette.NODE[kind]
		item.add_child(icon)
		item.add_child(UiKit.label("%s (%s)" % [NAMES[kind], PLAIN[kind]], 14, Palette.TEXT))
		legend.add_child(item)
	# The key folds away behind a button so the map gets the room.
	legend.visible = false
	var key_btn := UiKit.button("Key", func() -> void: pass, Vector2(76, 40), 15)
	key_btn.pressed.connect(func() -> void:
		legend.visible = not legend.visible
		key_btn.text = "Hide key" if legend.visible else "Key")
	hint_row.add_child(key_btn)
	v.add_child(legend)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_canvas = Control.new()
	_canvas.custom_minimum_size = Vector2(0, ROW_H * (run.map.rows.size() + 0.6))
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# PASS, not the default STOP: the ScrollContainer only drag-scrolls on touch if the
	# press and motion events bubble up to it after the canvas has looked at them.
	_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_canvas.draw.connect(_draw_map)
	_canvas.gui_input.connect(_on_canvas_input)
	_scroll.add_child(_canvas)
	# Scroll so the current row is visible (map is drawn bottom-up).
	if not is_inside_tree():
		return  # built outside a running tree (tests)
	await get_tree().process_frame
	var row := 0 if run.node_id < 0 else int(run.map.node(run.node_id)["row"])
	_scroll.scroll_vertical = int(_node_pos(0, 1, row).y - _scroll.size.y * 0.6)


## Jumps come from perks (Packet Hop, Ghost Routing); vaults hint at them.
func _hint() -> String:
	if not run.jump_moves().is_empty():
		return "Climb a lit route, or JUMP diagonally through a wall (uses a jump)"
	if run.jumps_total() == 0 and _has_vaults():
		return "Tap a lit node to move there. Walls block some routes; vaults need a jump upgrade."
	return "Tap a lit node to move there. Climb to the Core (the boss) at the top."


func _has_vaults() -> bool:
	for n in run.map.nodes:
		if n["type"] == "vault":
			return true
	return false


func _process(_dt: float) -> void:
	if _canvas != null:
		_canvas.queue_redraw()


func _node_pos(col: int, cols: int, row: int) -> Vector2:
	return _map_pt((col + 0.5) / cols, row)


## Map space (x = relative column 0..1, y = row) to canvas pixels; walls use it too.
func _map_pt(x: float, y: float) -> Vector2:
	return Vector2(x * _canvas.size.x, (run.map.rows.size() - y) * ROW_H - 20)


func _radius(id: int) -> float:
	return 30.0 if run.map.node(id)["type"] == "boss" else 24.0


## Where a straight wire from a to b leaves a's square plate.
func _edge(id: int, toward: Vector2) -> Vector2:
	var p := _pos(id)
	var d := toward - p
	var m := maxf(absf(d.x), absf(d.y))
	return p if m <= 0.0 else p + d * ((_radius(id) + 3.0) / m)


## A link drawn edge to edge: straight, so diagonals start and end at their nodes.
func _wire(a: int, b: int) -> PackedVector2Array:
	return PackedVector2Array([_edge(a, _pos(b)), _edge(b, _pos(a))])


func _pos(id: int) -> Vector2:
	var n: Dictionary = run.map.node(id)
	return _node_pos(n["col"], n["cols"], n["row"])


## Nodes you can still reach from where you stand (every node before the first move).
func _reachable() -> Dictionary:
	var out := {}
	var frontier: Array = []
	if run.node_id < 0:
		for n in run.map.nodes:
			out[n["id"]] = true
		return out
	frontier.append(run.node_id)
	for jid in run.jump_moves():
		frontier.append(jid)
	while not frontier.is_empty():
		var id: int = frontier.pop_back()
		if out.has(id):
			continue
		out[id] = true
		for nx in run.map.node(id)["next"]:
			frontier.append(nx)
	return out


func _draw_map() -> void:
	var avail := run.available_nodes()
	var reach := _reachable()
	var here_row := -1 if run.node_id < 0 else int(run.map.node(run.node_id)["row"])
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
			# Routes you can no longer take fade back so the live ones read first.
			var dead: bool = not on_path and (not reach.has(n["id"]) or not reach.has(nx) or int(n["row"]) < here_row)
			if dead:
				col = Color(Palette.TEXT_DIM, 0.16)
			if on_path:
				col = Palette.ENERGY
			var wire := _wire(n["id"], nx)
			_canvas.draw_polyline(wire, Color(Palette.CARD_BG, 0.95), 8, true)
			if on_path:
				_canvas.draw_polyline(wire, Color(Palette.ENERGY, 0.16), 10, true)
			_canvas.draw_polyline(wire, col, 5 if on_path else 3, true)
			if not on_path and not dead:
				_route_pulse(wire, fposmod(t * 0.24 + phase, 1.0), Color(Palette.ENERGY, 0.65 if next_step else 0.38))
	_draw_walls()
	# Jumps already taken stay on the trail as solid arcs.
	for i in range(1, run.path.size()):
		if run.was_jump(i):
			var arc := _jump_arc(run.path[i - 1], run.path[i])
			_canvas.draw_polyline(arc, Color(Palette.ENERGY, 0.16), 10, true)
			_canvas.draw_polyline(arc, Palette.ENERGY, 5, true)
	# Jumps open from the current node: dashed arcs over the walls, with a label.
	for jid in run.jump_moves():
		var arc := _jump_arc(run.node_id, jid)
		var pulse := 0.65 + 0.35 * sin(t * 3.0)
		for i in range(arc.size() - 1):
			if i % 2 == 0:
				_canvas.draw_line(arc[i], arc[i + 1], Color(Palette.ENERGY, pulse), 4, true)
		var tip := arc[arc.size() - 1]
		var back := (arc[arc.size() - 3] - tip).normalized() * 11.0
		_canvas.draw_polyline(PackedVector2Array([tip + back.rotated(0.5), tip, tip + back.rotated(-0.5)]), Color(Palette.ENERGY, pulse), 3, true)
	for n in run.map.nodes:
		var p := _pos(n["id"])
		var col: Color = Palette.NODE[n["type"]]
		var r := _radius(n["id"])
		if n["type"] == "vault":
			# Sealed vault: a locked double frame, so it reads as a prize behind walls.
			_canvas.draw_style_box(_plate(Color(col, 0.10), Color(col, 0.55), 2), Rect2(p - Vector2.ONE * (r + 6), Vector2.ONE * (r + 6) * 2))
		var is_avail: bool = n["id"] in avail
		var visited: bool = n["id"] in run.path
		var current: bool = n["id"] == run.node_id
		if not is_avail and not visited and run.node_id >= 0 and n["row"] <= run.map.node(run.node_id)["row"]:
			col = Color(col, 0.3)
		elif not visited and not reach.has(n["id"]):
			col = Color(col, 0.38)
		if is_avail:
			draw_glow(p, r + 8 + 2 * sin(t * 3.0), col)
			# A ring that keeps rippling out from each place you can move to.
			var ripple := fposmod(t * 0.9, 1.0)
			_canvas.draw_arc(p, r + 6 + ripple * 22.0, 0, TAU, 40, Color(col, 0.7 * (1.0 - ripple)), 3, true)
		_canvas.draw_style_box(_plate(Palette.CARD_BG, col, 3 if is_avail or current else 1), Rect2(p - Vector2.ONE * r, Vector2.ONE * r * 2))
		Symbols.draw_on(_canvas, p, r * 0.75, n["type"], col)
		# Labels and shapes make node types readable without relying on color.
		# Labels sit on a small plate so route lines never run through the text.
		var label_w := font.get_string_size(NAMES[n["type"]], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 10
		_canvas.draw_style_box(_plate(Color(Palette.CARD_BG, 0.92), Color(col, 0.0), 0), Rect2(p + Vector2(-label_w / 2, r + 3), Vector2(label_w, 19)))
		_canvas.draw_string(font, p + Vector2(-55, r + 17), NAMES[n["type"]], HORIZONTAL_ALIGNMENT_CENTER, 110, 14, col)
		if visited:
			var c := p + Vector2(r - 1, -r + 1)
			_canvas.draw_circle(c, 8, Palette.ENERGY)
			_canvas.draw_polyline(PackedVector2Array([c + Vector2(-4, 0), c + Vector2(-1, 3), c + Vector2(4, -3)]), Palette.CARD_BG, 2, true)
		if current:
			_canvas.draw_arc(p, r + 7, PI * 0.1, PI * 0.9, 24, Palette.ENERGY, 3, true)
	# A JUMP tag on top of each node a jump can reach.
	for jid in run.jump_moves():
		var top := _pos(jid) + Vector2(0, -_radius(jid) - 12)
		_canvas.draw_style_box(_plate(Palette.CARD_BG, Palette.ENERGY, 2), Rect2(top - Vector2(24, 9), Vector2(48, 18)))
		_canvas.draw_string(font, top + Vector2(-24, 5), "JUMP", HORIZONTAL_ALIGNMENT_CENTER, 48, 12, Palette.ENERGY)


## A curved hop from a to the next floor, bowing outward so it reads as a leap.
func _jump_arc(a: int, b: int) -> PackedVector2Array:
	var p0 := _edge(a, _pos(b))
	var p2 := _edge(b, _pos(a))
	var dir := signf(p2.x - p0.x) if absf(p2.x - p0.x) > 4.0 else 1.0
	var bow := Vector2(dir * -34.0, -6.0)
	var c := (p0 + p2) / 2.0 + bow
	var pts := PackedVector2Array()
	for i in 17:
		var u := i / 16.0
		pts.append(p0.lerp(c, u).lerp(c.lerp(p2, u), u))
	return pts


## Firewall walls: thick block segments, with the links they cut left as faint
## dashed ghosts so you can see what each wall blocks.
func _draw_walls() -> void:
	for w in run.map.walls:
		for link in w.get("cut", []):
			var ghost := _wire(int(link[0]), int(link[1]))
			_canvas.draw_dashed_line(ghost[0], ghost[1], Color(Palette.TEXT_DIM, 0.6), 2, 7, true)
	for w in run.map.walls:
		var a := _map_pt(float(w["a"][0]), float(w["a"][1]))
		var b := _map_pt(float(w["b"][0]), float(w["b"][1]))
		_wall(a, b)


## A firewall: soft glow, a clean capsule bar with a bright core, small caps.
func _wall(a: Vector2, b: Vector2) -> void:
	var dir := (b - a).normalized()
	var t := Time.get_ticks_msec() / 1000.0
	var glow := 0.16 + 0.05 * sin(t * 2.2 + a.x * 0.05)
	_canvas.draw_line(a - dir * 6, b + dir * 6, Color(Palette.ENEMY, glow), 24, true)
	_canvas.draw_line(a, b, Color(Palette.CARD_BG, 0.95), 12, true)
	_canvas.draw_line(a, b, Color(Palette.ENEMY, 0.9), 8, true)
	_canvas.draw_line(a + dir * 3, b - dir * 3, Color(Palette.TEXT, 0.75), 2, true)
	for p in [a, b]:
		_canvas.draw_circle(p, 6, Palette.ENEMY)
		_canvas.draw_circle(p, 2.5, Palette.TEXT)


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
