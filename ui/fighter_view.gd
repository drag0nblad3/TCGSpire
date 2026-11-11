class_name FighterView
extends Control
## Player, enemy or unit portrait: sigil glyph, HP bar, Ward, status chips and,
## for enemies, telegraphed intent icons. Tap = pressed, hold = inspected.
## During animation playback the combat screen drives shown_hp / shown_ward so
## numbers change in step with the hits instead of jumping to the final state.

signal pressed(view: FighterView)
signal inspected(view: FighterView)

var fighter: Fighter
var combat: Combat
var kind := "enemy"  # enemy | unit | player
var targetable := false:
	set(v):
		targetable = v
		queue_redraw()
## -1 = show the live value.
var shown_hp := -1
var shown_ward := -1
## Set while an action plays out so the intent doesn't change mid-animation.
var frozen_intents = null
## Draw offset (lunges, recoil) and white hit flash, both tweened by CombatScreen.
var offset := Vector2.ZERO
var flash := 0.0

var _tap := Tap.new()


func setup(f: Fighter, c: Combat, kind_in: String) -> FighterView:
	fighter = f
	combat = c
	kind = kind_in
	custom_minimum_size = Vector2(200, 260) if kind == "enemy" else (Vector2(120, 130) if kind == "unit" else Vector2(340, 70))
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


func hp() -> int:
	return shown_hp if shown_hp >= 0 else fighter.hp


func ward() -> int:
	return shown_ward if shown_ward >= 0 else fighter.ward


func freeze() -> void:
	shown_hp = fighter.hp
	shown_ward = fighter.ward
	if kind == "enemy":
		frozen_intents = Intents.of(combat, fighter)


func intents() -> Array:
	if frozen_intents != null:
		return frozen_intents
	return Intents.of(combat, fighter) if kind == "enemy" else []


func _gui_input(event: InputEvent) -> void:
	if _tap.feed(event) == "tap":
		pressed.emit(self)
		accept_event()


func _process(dt: float) -> void:
	if _tap.poll_long():
		inspected.emit(self)
	flash = maxf(flash - dt * 4.0, 0.0)
	queue_redraw()


func _draw() -> void:
	if fighter == null:
		return
	draw_set_transform(offset)
	var font := Palette.font()
	var w := size.x
	var col := Palette.ENEMY if kind == "enemy" else (Palette.faction("ember") if kind == "unit" else Palette.TEXT)
	var t := Time.get_ticks_msec() / 1000.0

	if targetable:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(Palette.ENERGY, 0.08 + 0.05 * sin(t * 5.0))
		glow.border_color = Palette.ENERGY
		glow.set_border_width_all(2)
		glow.set_corner_radius_all(maxi(Palette.RADIUS, 4))
		draw_style_box(glow, Rect2(Vector2.ZERO, size))
	elif kind == "player":
		var sb := StyleBoxFlat.new()
		sb.bg_color = Palette.PANEL_BG
		sb.set_corner_radius_all(maxi(Palette.RADIUS, 4))
		draw_style_box(sb, Rect2(Vector2.ZERO, size))

	var y := 4.0
	if kind == "enemy":
		y = _draw_intents(font, w, y)
	if kind != "player":
		var r := 54.0 if kind == "enemy" else 24.0
		var bob := sin(t * 1.7 + fighter.id.hash() % 7) * 3.0
		var c := Vector2(w / 2, y + r + 4 + bob)
		Sigil.draw(self, c, r, fighter.def_id + fighter.name, col, t)
		if flash > 0.0:
			draw_circle(c, r * 1.1, Color(Palette.HP, flash * 0.5))
		y += r * 2 + 12
	if kind == "unit":
		draw_string(font, Vector2(0, y + 10), fighter.name, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Palette.TEXT)
		y += 14
	elif kind == "enemy":
		draw_string(Palette.display(), Vector2(0, y + 12), fighter.name, HORIZONTAL_ALIGNMENT_CENTER, w, 15, Palette.TEXT)
		y += 18
	else:
		draw_string(Palette.display(), Vector2(12, 22), Palette.w("hero"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.TEXT)
		y = 30.0

	# HP bar (+ Ward shield badge on its left).
	var bar := Rect2(22, y, w - 34, 14)
	draw_rect(bar, Color(Palette.CARD_BG, 0.85))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(hp()) / fighter.max_hp, 0, 1), bar.size.y)), Palette.HP)
	if flash > 0.0 and kind == "player":
		draw_rect(bar.grow(3), Color(Palette.HP, flash * 0.6), false, 3)
	draw_rect(bar, Color(Palette.TEXT, 0.4), false, 1)
	draw_string(font, bar.position + Vector2(0, 12), "%d/%d" % [hp(), fighter.max_hp], HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, 12, Palette.TEXT)
	if ward() > 0:
		IntentIcon.draw(self, bar.position + Vector2(-10, 7), 13, "ward")
		draw_string(font, bar.position + Vector2(-24, 12), str(ward()), HORIZONTAL_ALIGNMENT_CENTER, 28, 12, Palette.TEXT)
	y += 20

	# Status chips.
	var chips: Array = []
	if kind == "unit":
		chips.append(["ATK %d" % fighter.atk, Palette.ENERGY])
	for k in fighter.statuses:
		var debuff: bool = Statuses.DEFS.get(k, {}).get("debuff", false)
		chips.append(["%s %d" % [str(k).capitalize(), fighter.statuses[k]], Palette.ENEMY if debuff else Palette.UPGRADED])
	var x := 6.0 if kind != "player" else bar.position.x
	var cy := y if kind != "player" else bar.end.y + 4
	if kind == "player":
		x = 80.0
		cy = 8.0
	for chip in chips:
		var cw := font.get_string_size(chip[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 10
		if x + cw > w - 4:
			x = 6.0
			cy += 18
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(chip[1], 0.22)
		sb.border_color = chip[1]
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(7)
		draw_style_box(sb, Rect2(x, cy, cw, 16))
		draw_string(font, Vector2(x + 5, cy + 12), chip[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Palette.TEXT)
		x += cw + 4
	draw_set_transform(Vector2.ZERO)


func _draw_intents(font: Font, w: float, y: float) -> float:
	var items := intents()
	if items.is_empty() or fighter.is_dead():
		return y + 30
	var fs := 15
	var widths: Array = []
	var total := 0.0
	for it in items:
		var lw := font.get_string_size(IntentIcon.label(it), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(24 + lw + 6)
		total += widths[-1]
	var x := (w - total) / 2
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(Palette.CARD_BG, 0.8)
	pill.set_corner_radius_all(13)
	draw_style_box(pill, Rect2(x - 6, y, total + 12, 26))
	for i in items.size():
		var it: Dictionary = items[i]
		IntentIcon.draw(self, Vector2(x + 11, y + 13), 10, it["kind"])
		draw_string(Palette.display(), Vector2(x + 24, y + 19), IntentIcon.label(it), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, IntentIcon.color(it["kind"]))
		x += widths[i]
	return y + 30


## Text for the inspect popup.
func describe() -> String:
	var nm := Palette.w("hero") if kind == "player" else fighter.name
	var lines: Array[String] = ["%s  (%d/%d HP)" % [nm, fighter.hp, fighter.max_hp]]
	if kind == "enemy" and not fighter.is_dead():
		lines.append("Next: " + Intents.explain(fighter))
	if kind == "unit":
		lines.append("Strikes the front enemy for %d at the end of your turn. Area attacks, and attacks aimed at the front, can hit it." % fighter.atk)
	if fighter.ward > 0:
		lines.append("Ward %d: absorbs damage first." % fighter.ward)
	for k in fighter.statuses:
		lines.append("%s %d: %s" % [str(k).capitalize(), fighter.statuses[k], Statuses.DEFS.get(k, {}).get("desc", "")])
	return "\n".join(lines)
