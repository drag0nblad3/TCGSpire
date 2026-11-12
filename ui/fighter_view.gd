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
## Status chip text size (units draw a bit smaller).
const CHIP_FONT := 17


func setup(f: Fighter, c: Combat, kind_in: String) -> FighterView:
	fighter = f
	combat = c
	kind = kind_in
	custom_minimum_size = _base_size()
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
	# HP text sizes per kind; the bar is a bit taller than its number.
	var hfs: int = {"enemy": 19, "unit": 16, "player": 22}[kind]
	var bar := Rect2(34, y, w - 44, hfs + 6)
	draw_rect(bar, Color(Palette.CARD_BG, 0.85))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(hp()) / fighter.max_hp, 0, 1), bar.size.y)), Palette.HP)
	if flash > 0.0 and kind == "player":
		draw_rect(bar.grow(3), Color(Palette.HP, flash * 0.6), false, 3)
	draw_rect(bar, Color(Palette.TEXT, 0.4), false, 1)
	var hp_pos := bar.position + Vector2(0, bar.size.y / 2 + hfs * 0.36)
	draw_string_outline(font, hp_pos, "%d/%d" % [hp(), fighter.max_hp], HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, hfs, 4, Color(Palette.CARD_BG, 0.9))
	draw_string(font, hp_pos, "%d/%d" % [hp(), fighter.max_hp], HORIZONTAL_ALIGNMENT_CENTER, bar.size.x, hfs, Palette.TEXT)
	if ward() > 0:
		var wc := bar.position + Vector2(-16, bar.size.y / 2)
		IntentIcon.draw(self, wc, 21, "ward")
		draw_string(font, wc + Vector2(-16, 7), str(ward()), HORIZONTAL_ALIGNMENT_CENTER, 32, 18, Palette.TEXT)
	y += bar.size.y + 6

	# Status chips.
	var chips: Array = []
	if kind == "unit":
		chips.append(["ATK %d" % fighter.atk, Palette.ENERGY])
	for k in fighter.statuses:
		var debuff: bool = Statuses.DEFS.get(k, {}).get("debuff", false)
		chips.append(["%s %d" % [Lexicon.status(str(k)), fighter.statuses[k]], Palette.ENEMY if debuff else Palette.UPGRADED])
	# Big enough to read at a glance on a phone; wraps to more rows as needed.
	var fs := CHIP_FONT if kind != "unit" else CHIP_FONT - 3
	var ch := fs + 10.0
	var x := 6.0
	var cy := y if kind != "player" else bar.end.y + 6
	for chip in chips:
		var cw := font.get_string_size(chip[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14
		if x + cw > w - 4 and x > 6.0:
			x = 6.0
			cy += ch + 4
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(chip[1], 0.28)
		sb.border_color = chip[1]
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(int(ch / 2))
		draw_style_box(sb, Rect2(x, cy, cw, ch))
		draw_string(font, Vector2(x + 7, cy + ch / 2 + fs * 0.36), chip[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Palette.TEXT)
		x += cw + 5
	draw_set_transform(Vector2.ZERO)
	# Grow (or shrink back) to fit every row of chips.
	var need := maxf(_base_size().y, (cy + ch + 6) if not chips.is_empty() else 0.0)
	if not is_equal_approx(need, custom_minimum_size.y):
		custom_minimum_size.y = need


func _base_size() -> Vector2:
	return Vector2(200, 274) if kind == "enemy" else (Vector2(120, 130) if kind == "unit" else Vector2(340, 56))


func _draw_intents(font: Font, w: float, y: float) -> float:
	var items := intents()
	if items.is_empty() or fighter.is_dead():
		return y + 44
	# Big, bordered pill so the enemy's plan reads at a glance on a phone.
	var fs := 21
	var ir := 15.0
	var widths: Array = []
	var total := 0.0
	for it in items:
		var lw := font.get_string_size(IntentIcon.label(it), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		widths.append(ir * 2 + 6 + lw + 10)
		total += widths[-1]
	var x := (w - total) / 2
	var main_col := IntentIcon.color(items[0]["kind"])
	var pulse := 0.55 + 0.25 * sin(Time.get_ticks_msec() / 1000.0 * 3.0)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(Palette.CARD_BG, 0.92)
	pill.border_color = Color(main_col, pulse)
	pill.set_border_width_all(2)
	pill.set_corner_radius_all(19)
	pill.shadow_color = Color(main_col, 0.35)
	pill.shadow_size = 6
	draw_style_box(pill, Rect2(x - 8, y, total + 16, 40))
	for i in items.size():
		var it: Dictionary = items[i]
		IntentIcon.draw(self, Vector2(x + ir, y + 20), ir, it["kind"])
		draw_string(Palette.display(), Vector2(x + ir * 2 + 6, y + 28), IntentIcon.label(it), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, IntentIcon.color(it["kind"]))
		x += widths[i]
	return y + 44


## Text for the inspect popup.
func describe() -> String:
	var nm := Palette.w("hero") if kind == "player" else fighter.name
	var lines: Array[String] = ["%s  (%d/%d HP)" % [nm, fighter.hp, fighter.max_hp]]
	if kind == "enemy" and not fighter.is_dead():
		lines.append("Next: " + Intents.explain(fighter))
	if kind == "unit":
		lines.append("Daemon: hits the front enemy for %d at the end of your turn. Area attacks, and attacks aimed at the front, can hit it." % fighter.atk)
	if fighter.ward > 0:
		lines.append("Firewall %d: absorbs damage first." % fighter.ward)
	for k in fighter.statuses:
		lines.append("%s %d: %s" % [Lexicon.status(str(k)), fighter.statuses[k], Statuses.DEFS.get(k, {}).get("desc", "")])
	return "\n".join(lines)
