class_name GlitchTitle
extends Control
## Big title with chromatic split and an occasional glitch jolt (Glassnet skin).

var text := ""
var font_size := 40


func setup(t: String, fs: int = 40) -> GlitchTitle:
	text = t
	font_size = fs
	custom_minimum_size = Vector2(0, fs * 1.5)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var f := Palette.display()
	var t := Time.get_ticks_msec() / 1000.0
	var y := size.y * 0.5 + f.get_ascent(font_size) * 0.4
	# A short jolt about every 3.5 s.
	var phase := fmod(t, 3.5)
	var jolt := 0.0
	if phase < 0.18:
		jolt = sin(phase * 120.0) * 5.0
	var split := 2.0 + absf(jolt)
	var b: Dictionary = Palette.BACKDROP
	draw_string(f, Vector2(-split + jolt, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color(b["glow2"], 0.75))
	draw_string(f, Vector2(split - jolt * 0.5, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Color(b["glow"], 0.75))
	draw_string(f, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, size.x, font_size, Palette.TEXT)
	if jolt != 0.0:
		# Slice offset: a thin band of the title shifted sideways.
		var band := Rect2(0, y - font_size * 0.55, size.x, font_size * 0.18)
		draw_rect(band, Color(Palette.CARD_BG, 0.6))
		draw_line(Vector2(0, band.position.y), Vector2(size.x, band.position.y), Color(b["glow"], 0.8), 1.0)
