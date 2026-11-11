class_name Sigil
extends RefCounted
## Procedural "card art": a geometric glyph generated from a seed string, so
## every card and enemy gets a unique, consistent emblem with zero art assets.


static func draw(ci: CanvasItem, center: Vector2, r: float, seed_str: String, col: Color, t: float = 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_str.hash()
	var sides := rng.randi_range(3, 8)
	var rings := rng.randi_range(1, 3)
	var rot := rng.randf() * TAU + t * 0.15
	var twist := rng.randf_range(0.0, PI / sides)
	var faint := Color(col, 0.35)

	# Soft glow disc.
	ci.draw_circle(center, r * 1.05, Color(col, 0.08))
	for k in rings:
		var rr := r * (1.0 - k * 0.3)
		var pts := _ngon(center, rr, sides, rot + twist * k)
		ci.draw_polyline(pts, col if k == 0 else faint, 2.0 if k == 0 else 1.5, true)
	var outer := _ngon(center, r, sides, rot)
	if rng.randf() < 0.6:
		for i in sides:
			ci.draw_line(center, outer[i], faint, 1.0, true)
	if sides >= 5 and rng.randf() < 0.5:
		var star := PackedVector2Array()
		for i in sides + 1:
			star.append(outer[(i * 2) % sides])
		ci.draw_polyline(star, Color(col, 0.6), 1.5, true)
	var dots := rng.randi_range(0, sides)
	for i in dots:
		var a := rot + TAU * i / maxf(dots, 1) + t * 0.3
		ci.draw_circle(center + Vector2.from_angle(a) * r * 1.12, r * 0.05, col)
	ci.draw_circle(center, r * rng.randf_range(0.08, 0.18), col)


static func _ngon(center: Vector2, r: float, sides: int, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides + 1:
		pts.append(center + Vector2.from_angle(rot + TAU * i / sides) * r)
	return pts
