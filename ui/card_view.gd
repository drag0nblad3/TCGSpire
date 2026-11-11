class_name CardView
extends Control
## Draws a card entirely in code: frame, faction band, procedural sigil, cost,
## name and generated rules text. Rare+ and foil cards get the holo shader.

signal pressed(view: CardView)

const SIZE := Vector2(128, 184)
const HOLO := preload("res://shaders/holo.gdshader")

var card: CardInstance
var playable := true
var selected := false:
	set(v):
		selected = v
		queue_redraw()

var _holo: ColorRect


func setup(c: CardInstance) -> CardView:
	card = c
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE / 2
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		pressed.emit(self)
		accept_event()


func _process(_dt: float) -> void:
	if card != null and card.def.rarity in ["rare", "mythic"]:
		queue_redraw()  # animate the sigil on rares


func _draw() -> void:
	if card == null:
		return
	var d := card.def
	var fc := Palette.faction(d.faction)
	var font := Palette.font()
	var lift := Vector2(0, -14) if selected else Vector2.ZERO
	var rect := Rect2(lift, SIZE)
	var dim := 1.0 if playable else 0.45

	var sb := StyleBoxFlat.new()
	sb.bg_color = Palette.CARD_BG
	sb.border_color = Palette.rarity(d.rarity) if not selected else Palette.ENERGY
	sb.set_border_width_all(3 if selected else 2)
	sb.set_corner_radius_all(10)
	sb.shadow_color = Color(fc, 0.35 if playable else 0.0)
	sb.shadow_size = 6
	draw_style_box(sb, rect)

	# Faction band + sigil "art".
	var art := Rect2(rect.position + Vector2(8, 26), Vector2(SIZE.x - 16, 66))
	var band := StyleBoxFlat.new()
	band.bg_color = Color(fc, 0.16 * dim)
	band.set_corner_radius_all(6)
	draw_style_box(band, art)
	var t := Time.get_ticks_msec() / 1000.0 if d.rarity in ["rare", "mythic"] else 0.0
	Sigil.draw(self, art.get_center(), 24.0, d.id, Color(fc, dim), t)

	# Name.
	var name_col := Color(Palette.TEXT, dim)
	if card.upgraded:
		name_col = Color(Palette.UPGRADED, dim)
	draw_string(font, rect.position + Vector2(30, 19), card.display_name(), HORIZONTAL_ALIGNMENT_LEFT, SIZE.x - 36, 13, name_col)

	# Cost orb.
	var orb := rect.position + Vector2(15, 14)
	draw_circle(orb, 11, Color(Palette.ENERGY, dim))
	draw_string(font, orb + Vector2(-11, 5), str(card.cost()), HORIZONTAL_ALIGNMENT_CENTER, 22, 15, Palette.CARD_BG)

	# Type line.
	draw_string(font, rect.position + Vector2(8, 106), "%s · %s" % [d.type.capitalize(), d.faction.capitalize()],
		HORIZONTAL_ALIGNMENT_CENTER, SIZE.x - 16, 10, Color(Palette.TEXT_DIM, dim))

	# Rules text.
	draw_multiline_string(font, rect.position + Vector2(8, 124), card.text(), HORIZONTAL_ALIGNMENT_CENTER,
		SIZE.x - 16, 11, 5, Color(Palette.TEXT, dim))

	# Rarity pip.
	draw_circle(rect.position + Vector2(SIZE.x / 2, SIZE.y - 9), 3.5, Palette.rarity(d.rarity))

	if _holo != null:
		_holo.position = Vector2(6, 6) + lift
