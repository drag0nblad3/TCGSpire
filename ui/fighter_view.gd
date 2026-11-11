class_name FighterView
extends Control
## Player, enemy or unit portrait: sigil glyph, HP bar, Ward, statuses and,
## for enemies, the telegraphed intent.

signal pressed(view: FighterView)

var fighter: Fighter
var combat: Combat
var kind := "enemy"  # enemy | unit | player
var targetable := false:
	set(v):
		targetable = v
		queue_redraw()


func setup(f: Fighter, c: Combat, kind_in: String) -> FighterView:
	fighter = f
	combat = c
	kind = kind_in
	custom_minimum_size = Vector2(220, 250) if kind == "enemy" else (Vector2(120, 120) if kind == "unit" else Vector2(320, 64))
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


func _gui_input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		pressed.emit(self)
		accept_event()


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if fighter == null:
		return
	var font := Palette.font()
	var w := size.x
	var col := Palette.ENEMY if kind == "enemy" else (Palette.faction("ember") if kind == "unit" else Palette.TEXT)
	if fighter.is_dead():
		col = Color(col, 0.2)
	var t := Time.get_ticks_msec() / 1000.0

	if targetable:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(Palette.ENERGY, 0.08 + 0.05 * sin(t * 5.0))
		glow.border_color = Palette.ENERGY
		glow.set_border_width_all(2)
		glow.set_corner_radius_all(12)
		draw_style_box(glow, Rect2(Vector2.ZERO, size))

	var y := 8.0
	if kind != "player":
		var r := 62.0 if kind == "enemy" else 26.0
		var bob := sin(t * 1.7 + fighter.id.hash() % 7) * 3.0
		Sigil.draw(self, Vector2(w / 2, y + r + 6 + bob), r, fighter.def_id + fighter.name, col, t)
		y += r * 2 + 16
	draw_string(font, Vector2(0, y + 12), fighter.name, HORIZONTAL_ALIGNMENT_CENTER, w, 14, Palette.TEXT)
	y += 18

	# HP bar.
	var bar := Rect2(10, y, w - 20, 12)
	draw_rect(bar, Color(0, 0, 0, 0.5))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(fighter.hp) / fighter.max_hp, 0, 1), bar.size.y)), Palette.HP)
	draw_string(font, bar.position + Vector2(0, 10), "%d/%d" % [fighter.hp, fighter.max_hp], HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 10, Palette.TEXT)
	if fighter.ward > 0:
		draw_circle(bar.position + Vector2(-2, 6), 9, Palette.WARD)
		draw_string(font, bar.position + Vector2(-11, 10), str(fighter.ward), HORIZONTAL_ALIGNMENT_CENTER, 18, 10, Palette.CARD_BG)
	y += 18

	var line := ""
	if kind == "unit":
		line = "ATK %d" % fighter.atk
	for k in fighter.statuses:
		line += "  %s %d" % [str(k).capitalize(), fighter.statuses[k]]
	if line != "":
		draw_string(font, Vector2(0, y + 10), line.strip_edges(), HORIZONTAL_ALIGNMENT_CENTER, w, 10, Palette.TEXT_DIM)
		y += 14

	if kind == "enemy" and not fighter.is_dead():
		var mv := fighter.current_move()
		var dmg := combat.intent_damage(fighter)
		var intent := str(mv.get("name", "?"))
		if dmg > 0:
			intent += "  · hits %d" % dmg
		draw_string(font, Vector2(0, y + 12), intent, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Palette.ENERGY)
