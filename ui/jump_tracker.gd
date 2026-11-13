class_name JumpTracker
extends Control
## Map panel for the jump upgrade, on its own row so it stands apart: a glowing
## plate with one large chevron per jump this layer (lit while unspent) and a
## plain "2 of 3 left this layer" readout. Shown only when the run has jumps.

var run: RunState


func setup(r: RunState) -> JumpTracker:
	run = r
	custom_minimum_size = Vector2(0, 54)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var total := run.jumps_total()
	var left := run.jumps_left()
	var t := Time.get_ticks_msec() / 1000.0
	var pip_w := 34.0
	var w := minf(size.x, 150.0 + pip_w * total + 150.0)
	var rect := Rect2(Vector2((size.x - w) / 2.0, 4), Vector2(w, size.y - 8))
	var edge := Palette.ENERGY if left > 0 else Palette.TEXT_DIM
	if left > 0:
		var halo := StyleBoxFlat.new()
		halo.bg_color = Color(edge, 0.10 + 0.05 * sin(t * 2.5))
		halo.set_corner_radius_all(14)
		draw_style_box(halo, rect.grow(4))
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(Palette.CARD_BG, 0.96)
	plate.border_color = edge
	plate.set_border_width_all(2)
	plate.set_corner_radius_all(10)
	draw_style_box(plate, rect)
	var font := Palette.font()
	var x := rect.position.x + 16
	var cy := rect.get_center().y
	draw_string(font, Vector2(x, cy + 7), "JUMPS", HORIZONTAL_ALIGNMENT_LEFT, 90, 20, edge)
	x += 92
	for i in total:
		var c := Vector2(x + pip_w * i + pip_w / 2.0, cy)
		var lit := i < left
		if lit:
			draw_circle(c, 14, Color(Palette.ENERGY, 0.22))
		var col := Palette.ENERGY if lit else Color(Palette.TEXT_DIM, 0.45)
		for k in 2:
			var o := Vector2(0, 6 - k * 9)
			draw_polyline(PackedVector2Array([c + o + Vector2(-9, 4), c + o + Vector2(0, -4), c + o + Vector2(9, 4)]), col, 3, true)
	x += pip_w * total + 12
	draw_string(font, Vector2(x, cy + 6), "%d of %d left this layer" % [left, total], HORIZONTAL_ALIGNMENT_LEFT, rect.end.x - x - 10, 15, Palette.TEXT)
