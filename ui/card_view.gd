class_name CardView
extends Control
## Draws a card frame, Field Service illustration, faction identity, cost,
## name and generated rules text. Rare+ and foil cards get the holo shader.

signal pressed(view: CardView)
## Press-and-hold: show the card large with keyword explanations.
signal inspected(view: CardView)

const SIZE := Vector2(128, 184)
const DRONE := preload("res://assets/combat/drone.svg")
const TYPE_GLYPH := {"attack": "attack", "skill": "ward", "power": "power"}
const HOLO := preload("res://shaders/holo.gdshader")
const GLITCH := preload("res://shaders/glitch_foil.gdshader")
## Card back picked in Records ("default", "glitch" or a crew id). Set from the profile by Main.
static var back_style := "default"

var card: CardInstance
var playable := true
## Small pill in the corner: owned count, price, "x2" etc.
var badge := "":
	set(v):
		badge = v
		queue_redraw()
var selected := false:
	set(v):
		selected = v
		queue_redraw()

## Shows the card back (pack opening). Setting false reveals with a flip.
var face_down := false:
	set(v):
		face_down = v
		if _holo != null:
			_holo.visible = not v
		queue_redraw()

var _holo: ColorRect
## Draw scale: the card is laid out at SIZE and drawn zoomed (hand cards in combat).
var zoom := 1.0
var _tap := Tap.new()


func setup(c: CardInstance, zoom_in: float = 1.0) -> CardView:
	card = c
	zoom = zoom_in
	custom_minimum_size = SIZE * zoom
	size = SIZE * zoom
	pivot_offset = size / 2
	mouse_filter = Control.MOUSE_FILTER_PASS
	if c.foil or c.def.rarity in ["rare", "mythic"]:
		# Glitch foils get their own scanline/chromatic shader; rares keep the holo sheen.
		_holo = ColorRect.new()
		_holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_holo.position = Vector2(6, 6) * zoom
		_holo.size = (SIZE - Vector2(12, 12)) * zoom
		var mat := ShaderMaterial.new()
		mat.shader = GLITCH if c.foil else HOLO
		mat.set_shader_parameter("strength", 0.6 if c.foil else 0.28)
		if c.foil:
			mat.set_shader_parameter("seed", float(c.def.id.hash() % 997))
		_holo.material = mat
		add_child(_holo)
	return self


func _gui_input(event: InputEvent) -> void:
	if _tap.feed(event) == "tap":
		pressed.emit(self)
		accept_event()


func _process(_dt: float) -> void:
	if _tap.poll_long():
		if inspected.get_connections().is_empty():
			CardInspector.show_for(self, card)
		else:
			inspected.emit(self)
	if card != null and (face_down or card.def.rarity in ["rare", "mythic"]):
		queue_redraw()  # animate the sigil on rares and card backs


## Largest font size (max..min) at which `text` fits in width x height.
static func fit_size(font: Font, text: String, width: float, height: float, max_size: int, min_size: int) -> int:
	for fs in range(max_size, min_size - 1, -1):
		var sz := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, fs)
		if sz.y <= height:
			return fs
	return min_size


static func title_size(name_text: String, width: float, height: float) -> int:
	var font := Palette.NAME_FONT
	var max_size := 16
	for word in name_text.split(" ", false):
		while max_size > 11 and font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, max_size).x > width:
			max_size -= 1
	return fit_size(font, name_text, width, height, max_size, 11)


func _draw() -> void:
	if card == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(zoom, zoom))
	if face_down:
		_draw_back()
		return
	var d := card.def
	var fc := Palette.faction(d.faction)
	var font := Palette.font()
	var title_font := Palette.display()
	var lift := Vector2(0, -14) if selected else Vector2.ZERO
	var rect := Rect2(lift, SIZE)
	var dim := 1.0 if playable else 0.45
	var ink := Color(Palette.CARD_TEXT, dim)

	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.CARD_BG
	sb.border_color = Palette.ENERGY if selected else Palette.rarity(d.rarity)
	sb.set_border_width_all(Palette.BORDER + (1 if selected else 0))
	sb.set_corner_radius_all(Palette.RADIUS)
	sb.shadow_color = Color(fc, 0.35 if playable else 0.0)
	sb.shadow_size = 6
	draw_style_box(sb, rect)
	if Palette.FRAME == "circuit":
		_draw_circuit(rect, Color(fc if not selected else Palette.ENERGY, dim))

	# Use a second line before reducing the size of long program names.
	var name_font := Palette.NAME_FONT
	var name_box := Rect2(rect.position + Vector2(28, 2), Vector2(SIZE.x - 48, 30))
	var name_text := card.display_name()
	var name_size := title_size(name_text, name_box.size.x, name_box.size.y)
	var name_height := name_font.get_multiline_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, name_box.size.x, name_size).y
	var name_y := name_box.position.y + maxf(0.0, (name_box.size.y - name_height) * 0.5) + name_font.get_ascent(name_size)
	draw_multiline_string(name_font, Vector2(name_box.position.x, name_y), name_text, HORIZONTAL_ALIGNMENT_LEFT, name_box.size.x, name_size, 2,
		Color(Palette.UPGRADED, dim) if card.upgraded else ink)
	var orb := rect.position + Vector2(15, 16)
	draw_circle(orb, 11, Color(Palette.ENERGY, dim))
	draw_string(title_font, orb + Vector2(-11, 5), str(card.cost()), HORIZONTAL_ALIGNMENT_CENTER, 22, 14, Palette.CARD_BG)
	Symbols.draw_on(self, rect.position + Vector2(SIZE.x - 11, 16), 8, d.faction, Color(fc, dim))

	# Every card surface uses the same cached art; keep procedural fallback for future content.
	var art := Rect2(rect.position + Vector2(8, 34), Vector2(SIZE.x - 16, 42))
	var illustration := CardArt.texture_for(d.id)
	if illustration != null:
		draw_texture_rect(illustration, art, false, Color(1, 1, 1, dim))
		draw_rect(art, Color(fc, 0.65 * dim), false, 1.0)
	else:
		draw_rect(art, Color(fc, 0.23 * dim))
		var t := Time.get_ticks_msec() / 1000.0 if d.rarity in ["rare", "mythic"] else 0.0
		if Palette.FRAME == "circuit":
			for yy in range(int(art.position.y) + 2, int(art.end.y), 3):
				draw_line(Vector2(art.position.x, yy), Vector2(art.end.x, yy), Color(fc, 0.07 * dim), 1.0)
		var glyph_ink := Color(Palette.CARD_TEXT.lerp(fc, 0.55), dim)
		if d.type == "unit":
			draw_texture_rect(DRONE, Rect2(art.get_center() - Vector2(20, 18), Vector2(40, 36)), false, glyph_ink)
		elif TYPE_GLYPH.has(d.type):
			IntentIcon.draw(self, art.get_center(), 19.0, TYPE_GLYPH[d.type], glyph_ink)
		else:
			Sigil.draw(self, art.get_center(), 19.0, d.id, Color(fc, dim), t)
		if d.type == "unit" or TYPE_GLYPH.has(d.type):
			Sigil.draw(self, art.get_center() + Vector2(31, 0), 11.0, d.id, Color(fc, 0.35 * dim), t)
	# Type line.
	# Type line; a modded card shows its mod there instead.
	if card.mod.is_empty():
		draw_string(font, rect.position + Vector2(6, 88), "%s · %s" % [Lexicon.type_name(d.type), Lexicon.faction(d.faction)],
			HORIZONTAL_ALIGNMENT_CENTER, SIZE.x - 12, 10, Color(fc, dim))
	else:
		draw_string(font, rect.position + Vector2(6, 88), "[ %s ]" % card.mod_name(),
			HORIZONTAL_ALIGNMENT_CENTER, SIZE.x - 12, 10, Color(Palette.UPGRADED, dim))

	# Rules text, auto-sized to fit the text box.
	var box := Rect2(rect.position + Vector2(6, 94), Vector2(SIZE.x - 12, SIZE.y - 94 - 16))
	var txt := card.text()
	var fs := fit_size(font, txt, box.size.x, box.size.y, 15, 7)
	var th := font.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, fs).y
	var y0 := box.position.y + maxf((box.size.y - th) / 2.0, 0.0) + font.get_ascent(fs)
	draw_multiline_string(font, Vector2(box.position.x, y0), txt, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, fs, -1, ink)

	# Rarity pip.
	draw_circle(rect.position + Vector2(SIZE.x / 2, SIZE.y - 8), 3.5, Palette.rarity(d.rarity))

	if badge != "":
		var bw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12
		var pill := StyleBoxFlat.new()
		pill.bg_color = Palette.ENERGY
		pill.set_corner_radius_all(9)
		var pr := Rect2(rect.position + Vector2(SIZE.x - bw - 4, SIZE.y - 22), Vector2(bw, 18))
		draw_style_box(pill, pr)
		draw_string(font, pr.position + Vector2(6, 13), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Palette.CARD_BG)

	if _holo != null:
		_holo.position = (Vector2(6, 6) + lift) * zoom


## Corner brackets, edge traces and a glass sheen (Glassnet skin).
func _draw_circuit(r: Rect2, col: Color) -> void:
	var L := 14.0
	var i := 4.0
	var w := 2.0
	var c := [r.position + Vector2(i, i), Vector2(r.end.x - i, r.position.y + i), r.end - Vector2(i, i), Vector2(r.position.x + i, r.end.y - i)]
	var dirs := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	for k in 4:
		draw_line(c[k], c[k] + Vector2(dirs[k].x * L, 0), col, w)
		draw_line(c[k], c[k] + Vector2(0, dirs[k].y * L), col, w)
	var faint := Color(col, col.a * 0.45)
	for side in [0, 1]:
		var x: float = r.position.x + 2.5 if side == 0 else r.end.x - 2.5
		var sx := 1.0 if side == 0 else -1.0
		var y0 := r.position.y + 100.0
		var pts := PackedVector2Array([Vector2(x, y0), Vector2(x, y0 + 26), Vector2(x + sx * 5, y0 + 31), Vector2(x + sx * 5, y0 + 44)])
		draw_polyline(pts, faint, 1.0, true)
		draw_circle(pts[3], 1.8, faint)
	var sheen := PackedVector2Array([r.position + Vector2(SIZE.x * 0.55, 2), r.position + Vector2(SIZE.x * 0.75, 2),
		r.position + Vector2(SIZE.x * 0.25, SIZE.y * 0.55), r.position + Vector2(SIZE.x * 0.05, SIZE.y * 0.55)])
	draw_colored_polygon(sheen, Color(1, 1, 1, 0.035))


func _draw_back() -> void:
	var rect := Rect2(Vector2.ZERO, SIZE)
	var sb := StyleBoxFlat.new()
	var accent := back_color()
	sb.bg_color = Palette.BUTTON
	sb.border_color = accent
	sb.set_border_width_all(Palette.BORDER)
	sb.set_corner_radius_all(Palette.RADIUS)
	draw_style_box(sb, rect)
	var t := Time.get_ticks_msec() / 1000.0
	Sigil.draw(self, rect.get_center(), 40.0, "card-back:" + back_style, Color(accent, 0.8), t)
	if back_style == Records.BACK_GLITCH:
		# Scanlines that crawl down the back.
		for i in 8:
			var y := fmod(t * 40.0 + i * SIZE.y / 8.0, SIZE.y)
			draw_line(Vector2(8, y), Vector2(SIZE.x - 8, y), Color(Palette.HP, 0.25), 2)
	draw_string(Palette.display(), Vector2(0, SIZE.y - 16), Palette.w("title"), HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 11, Palette.BUTTON_TEXT)


static func back_color() -> Color:
	if back_style == Records.BACK_GLITCH:
		return Palette.HP
	if back_style != "default" and back_style != "":
		return Palette.faction(back_style)
	return Palette.ENERGY


## Flip animation: squash to 0 width, swap face, expand back.
func flip_reveal() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale:x", 0.0, 0.12)
	tw.tween_callback(func() -> void: face_down = false)
	tw.tween_property(self, "scale:x", 1.0, 0.12)
