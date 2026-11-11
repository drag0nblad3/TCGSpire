class_name CardView
extends Control
## Draws a card entirely in code: frame, faction band, procedural sigil, cost,
## name and generated rules text. Rare+ and foil cards get the holo shader.

signal pressed(view: CardView)
## Press-and-hold: show the card large with keyword explanations.
signal inspected(view: CardView)

const SIZE := Vector2(128, 184)
const HOLO := preload("res://shaders/holo.gdshader")

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
var _tap := Tap.new()


func setup(c: CardInstance) -> CardView:
	card = c
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE / 2
	mouse_filter = Control.MOUSE_FILTER_PASS
	if c.foil or c.def.rarity in ["rare", "mythic"]:
		_holo = ColorRect.new()
		_holo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_holo.position = Vector2(6, 6)
		_holo.size = SIZE - Vector2(12, 12)
		var mat := ShaderMaterial.new()
		mat.shader = HOLO
		mat.set_shader_parameter("strength", 0.5 if c.foil else 0.28)
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


func _draw() -> void:
	if card == null:
		return
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

	# Name (shrinks to fit) + cost orb.
	var name_w := SIZE.x - 36
	var name_fs := 13
	while name_fs > 8 and title_font.get_string_size(card.display_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, name_fs).x > name_w:
		name_fs -= 1
	draw_string(title_font, rect.position + Vector2(29, 18), card.display_name(), HORIZONTAL_ALIGNMENT_LEFT, name_w, name_fs,
		Color(Palette.UPGRADED, dim) if card.upgraded else ink)
	var orb := rect.position + Vector2(15, 14)
	draw_circle(orb, 11, Color(Palette.ENERGY, dim))
	draw_string(title_font, orb + Vector2(-11, 5), str(card.cost()), HORIZONTAL_ALIGNMENT_CENTER, 22, 14, Palette.CARD_BG)

	# Faction band + sigil "art".
	var art := Rect2(rect.position + Vector2(8, 26), Vector2(SIZE.x - 16, 50))
	var band := StyleBoxFlat.new()
	band.bg_color = Color(fc, 0.16 * dim)
	band.set_corner_radius_all(maxi(Palette.RADIUS - 4, 0))
	draw_style_box(band, art)
	var t := Time.get_ticks_msec() / 1000.0 if d.rarity in ["rare", "mythic"] else 0.0
	Sigil.draw(self, art.get_center(), 19.0, d.id, Color(fc, dim), t)

	# Type line.
	draw_string(font, rect.position + Vector2(6, 88), "%s · %s" % [d.type.capitalize(), Palette.faction_name(d.faction)],
		HORIZONTAL_ALIGNMENT_CENTER, SIZE.x - 12, 10, Color(Palette.CARD_TEXT_DIM, dim))

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
		_holo.position = Vector2(6, 6) + lift


func _draw_back() -> void:
	var rect := Rect2(Vector2.ZERO, SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.BUTTON
	sb.border_color = Palette.ENERGY
	sb.set_border_width_all(Palette.BORDER)
	sb.set_corner_radius_all(Palette.RADIUS)
	draw_style_box(sb, rect)
	var t := Time.get_ticks_msec() / 1000.0
	Sigil.draw(self, rect.get_center(), 40.0, "card-back", Color(Palette.ENERGY, 0.8), t)
	draw_string(Palette.display(), Vector2(0, SIZE.y - 16), Palette.w("title"), HORIZONTAL_ALIGNMENT_CENTER, SIZE.x, 11, Palette.BUTTON_TEXT)


## Flip animation: squash to 0 width, swap face, expand back.
func flip_reveal() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale:x", 0.0, 0.12)
	tw.tween_callback(func() -> void: face_down = false)
	tw.tween_property(self, "scale:x", 1.0, 0.12)
