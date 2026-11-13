class_name JumpTracker
extends Control
## Map header chip for the jump upgrade: one pip per jump this layer, lit while
## unspent, plus a "JUMPS 1/2" readout. Shown only when the run has jumps.

var run: RunState


func setup(r: RunState) -> JumpTracker:
	run = r
	custom_minimum_size = Vector2(70 + 26 * run.jumps_total(), 34)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


func _draw() -> void:
	var total := run.jumps_total()
	var left := run.jumps_left()
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(Palette.PANEL_BG, 0.9)
	plate.border_color = Palette.ENERGY if left > 0 else Palette.TEXT_DIM
	plate.set_border_width_all(2)
	plate.set_corner_radius_all(8)
	draw_style_box(plate, Rect2(Vector2.ZERO, size))
	var font := Palette.font()
	draw_string(font, Vector2(10, 22), "JUMPS", HORIZONTAL_ALIGNMENT_LEFT, 60, 14, Palette.TEXT)
	for i in total:
		var c := Vector2(70 + 26 * i, size.y / 2.0)
		# A small chevron arc per jump: filled while unspent.
		var lit := i < left
		var pts := PackedVector2Array([c + Vector2(-8, 6), c + Vector2(0, -7), c + Vector2(8, 6)])
		if lit:
			draw_circle(c, 11, Color(Palette.ENERGY, 0.22))
		draw_polyline(pts, Palette.ENERGY if lit else Color(Palette.TEXT_DIM, 0.5), 3, true)
