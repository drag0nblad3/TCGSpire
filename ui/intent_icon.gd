class_name IntentIcon
extends RefCounted
## Procedural intent glyphs (sword, shield, arrows, ...) drawn with canvas calls.


static func color(kind: String) -> Color:
	match kind:
		"attack": return Palette.HP
		"ward": return Palette.WARD
		"buff": return Palette.UPGRADED
		"debuff", "curse": return Palette.ENEMY
		"heal": return Palette.faction("bloom")
		"summon": return Palette.ENERGY
	return Palette.TEXT_DIM


## Draws one icon of radius r at c.
static func draw(ci: CanvasItem, c: Vector2, r: float, kind: String, col: Color = Color.TRANSPARENT) -> void:
	if col == Color.TRANSPARENT:
		col = color(kind)
	var w := maxf(r * 0.16, 1.5)
	match kind:
		"attack":
			# Sword pointing up-right.
			var tip := c + Vector2(r * 0.75, -r * 0.75)
			var hilt := c + Vector2(-r * 0.35, r * 0.35)
			ci.draw_line(hilt, tip, col, w * 1.6, true)
			ci.draw_line(hilt + Vector2(-r * 0.3, -r * 0.3), hilt + Vector2(r * 0.3, r * 0.3), col, w * 1.3, true)
			ci.draw_line(hilt, c + Vector2(-r * 0.7, r * 0.7), col, w * 1.3, true)
		"ward":
			var pts := PackedVector2Array([c + Vector2(-r * 0.7, -r * 0.65), c + Vector2(r * 0.7, -r * 0.65),
				c + Vector2(r * 0.6, r * 0.15), c + Vector2(0, r * 0.85), c + Vector2(-r * 0.6, r * 0.15)])
			ci.draw_colored_polygon(pts, Color(col, 0.35))
			pts.append(pts[0])
			ci.draw_polyline(pts, col, w, true)
		"buff", "heal":
			var up := PackedVector2Array([c + Vector2(0, -r * 0.8), c + Vector2(r * 0.65, 0), c + Vector2(r * 0.25, 0),
				c + Vector2(r * 0.25, r * 0.75), c + Vector2(-r * 0.25, r * 0.75), c + Vector2(-r * 0.25, 0), c + Vector2(-r * 0.65, 0)])
			if kind == "heal":
				up = PackedVector2Array([c + Vector2(-r * 0.25, -r * 0.75), c + Vector2(r * 0.25, -r * 0.75), c + Vector2(r * 0.25, -r * 0.25),
					c + Vector2(r * 0.75, -r * 0.25), c + Vector2(r * 0.75, r * 0.25), c + Vector2(r * 0.25, r * 0.25),
					c + Vector2(r * 0.25, r * 0.75), c + Vector2(-r * 0.25, r * 0.75), c + Vector2(-r * 0.25, r * 0.25),
					c + Vector2(-r * 0.75, r * 0.25), c + Vector2(-r * 0.75, -r * 0.25), c + Vector2(-r * 0.25, -r * 0.25)])
			ci.draw_colored_polygon(up, col)
		"debuff":
			var dn := PackedVector2Array([c + Vector2(0, r * 0.8), c + Vector2(r * 0.65, 0), c + Vector2(r * 0.25, 0),
				c + Vector2(r * 0.25, -r * 0.75), c + Vector2(-r * 0.25, -r * 0.75), c + Vector2(-r * 0.25, 0), c + Vector2(-r * 0.65, 0)])
			ci.draw_colored_polygon(dn, col)
		"summon":
			for i in 3:
				var a := TAU * i / 3.0 - PI / 2
				ci.draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.45, r * 0.28, col)
		"power":
			var diamond := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0),
				c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)])
			ci.draw_polyline(diamond, col, w * 0.8, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.14, -r * 0.68), c + Vector2(-r * 0.42, r * 0.1),
				c + Vector2(-r * 0.05, r * 0.1), c + Vector2(-r * 0.15, r * 0.68),
				c + Vector2(r * 0.42, -r * 0.12), c + Vector2(r * 0.06, -r * 0.12)]), col)
		"curse":
			var card := Rect2(c - Vector2(r * 0.5, r * 0.7), Vector2(r, r * 1.4))
			ci.draw_rect(card, Color(col, 0.3))
			ci.draw_rect(card, col, false, w)
			ci.draw_line(card.position + Vector2(r * 0.25, r * 0.4), card.end - Vector2(r * 0.25, r * 0.4), col, w, true)
			ci.draw_line(Vector2(card.end.x - r * 0.25, card.position.y + r * 0.4), Vector2(card.position.x + r * 0.25, card.end.y - r * 0.4), col, w, true)
		_:
			ci.draw_arc(c + Vector2(0, -r * 0.2), r * 0.4, PI, TAU + PI * 0.5, 12, col, w, true)
			ci.draw_circle(c + Vector2(0, r * 0.65), w, col)


## Short label next to the icon: "7", "4x2", "6" etc.
static func label(item: Dictionary) -> String:
	match str(item["kind"]):
		"attack":
			var hits := int(item.get("hits", 1))
			return ("%dx%d" % [item["value"], hits] if hits > 1 else str(item["value"])) + (" all" if item.get("aoe", false) else "")
		"ward", "heal", "buff", "debuff":
			return str(item["value"]) if int(item["value"]) > 0 else ""
		"curse":
			return "+%d" % item["value"]
	return ""
