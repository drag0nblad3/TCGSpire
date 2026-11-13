class_name FighterView
extends Control
## Player, enemy or unit portrait: sigil glyph, HP bar, Ward, status chips and,
## for enemies, telegraphed intent icons. Tap = pressed, hold = inspected.
## During animation playback the combat screen drives shown_hp / shown_ward so
## numbers change in step with the hits instead of jumping to the final state.

signal pressed(view: FighterView)
signal inspected(view: FighterView)

const DRONE := preload("res://assets/combat/drone.svg")

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
var frozen_move := ""
## Draw offset (lunges, recoil) and white hit flash, both tweened by CombatScreen.
var offset := Vector2.ZERO
var flash := 0.0
var firewall_flash := 0.0
var offline := false
var boss_profile: Dictionary = {}
var boss_large := false
var boss_accent := Color.TRANSPARENT
var enemy_faction := ""
var enemy_portrait: Array = []
var elite := false

var _tap := Tap.new()


func setup(f: Fighter, c: Combat, kind_in: String) -> FighterView:
	fighter = f
	combat = c
	kind = kind_in
	custom_minimum_size = Vector2(200, 274) if kind == "enemy" else (Vector2(176, 158) if kind == "unit" else Vector2(340, 70))
	if kind == "enemy":
		if combat != null and combat.db != null:
			enemy_faction = str(combat.db.enemies.get(fighter.def_id, {}).get("faction", ""))
			var encounter: Dictionary = combat.db.encounters.get(combat.encounter_id, {})
			if encounter.get("kind", "") == "elite":
				var lineup: Array = encounter.get("enemies", [])
				# The lead enemy and any copies are elite. Escorts and summons keep their normal portraits.
				elite = not lineup.is_empty() and fighter.def_id == lineup[0]
		enemy_portrait = EnemyPortraits.ROSTER.get(fighter.def_id, [])
		boss_profile = BossPresentation.PROFILES.get(fighter.def_id, {})
		if not boss_profile.is_empty():
			boss_accent = Palette.faction(boss_profile["faction"])
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


func set_enemy_width(width: float) -> void:
	boss_large = not boss_profile.is_empty() and width >= 300.0
	custom_minimum_size = Vector2(width, 415.0 if boss_large else 274.0)


func hp() -> int:
	return shown_hp if shown_hp >= 0 else fighter.hp


func ward() -> int:
	return shown_ward if shown_ward >= 0 else fighter.ward


func freeze() -> void:
	shown_hp = fighter.hp
	shown_ward = fighter.ward
	if kind == "enemy":
		frozen_intents = Intents.of(combat, fighter)
		frozen_move = str(fighter.current_move().get("name", ""))


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
	firewall_flash = maxf(firewall_flash - dt * 4.0, 0.0)
	queue_redraw()


func _draw() -> void:
	if fighter == null:
		return
	draw_set_transform(offset)
	var font := Palette.font()
	var w := size.x
	var col := Palette.ENEMY if kind == "enemy" else (Palette.faction("ember") if kind == "unit" else Palette.TEXT)
	if enemy_faction != "":
		col = Palette.faction(enemy_faction)
	var t := Time.get_ticks_msec() / 1000.0

	var intent_items := intents()
	var boss := not boss_profile.is_empty()
	var charging: bool = boss and hp() > 0 and _move_name() == boss_profile["signature"] and not intent_items.is_empty()
	var heat := boss_accent
	var charge := 0.5 + 0.5 * sin(t * 3.2) if charging else 0.0
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(Palette.PANEL_BG, 0.88 if kind == "player" else 0.72)
	panel.border_color = Palette.ENERGY if targetable else Color(Palette.TEXT, 0.23)
	panel.set_border_width_all(2 if targetable else 1)
	panel.set_corner_radius_all(maxi(Palette.RADIUS, 6))
	if targetable:
		panel.shadow_color = Color(Palette.ENERGY, 0.20 + 0.12 * sin(t * 5.0))
		panel.shadow_size = 9
	elif boss:
		panel.border_color = Color(heat, 0.45 + charge * 0.45)
		panel.shadow_color = Color(heat, 0.16 + charge * 0.25)
		panel.shadow_size = 12
	draw_style_box(panel, Rect2(Vector2.ZERO, size))
	if targetable:
		_draw_target()

	var y := 4.0
	if kind == "enemy":
		y = _draw_intents(font, w, y, intent_items, charging)
	if kind != "player":
		var art_height := 252.0 if boss_large else (108.0 if kind == "enemy" else 47.0)
		var r := minf(art_height * 0.45, w * 0.34)
		var bob := sin(t * 1.7 + fighter.id.hash() % 7) * 3.0
		var c := Vector2(w / 2, y + art_height * 0.5 + bob)
		if boss:
			var halo := minf(w * 0.38, art_height * 0.54)
			draw_circle(c, halo, Color(heat, 0.06 + charge * 0.10), true, -1, true)
			draw_arc(c, halo, 0, TAU, 72, Color(heat, 0.18 + charge * 0.40), 2.0, true)
			if charging:
				draw_arc(c, halo + 6.0 + charge * 7.0, 0, TAU, 72, Color(heat, 0.30 - charge * 0.19), 2.0, true)
		var portrait: Texture2D = boss_profile["portrait"] if boss else null
		if kind == "unit" and fighter.name == "Drone":
			portrait = DRONE
		if not enemy_portrait.is_empty() and not boss:
			var height := art_height if fighter.def_id == "burner_tagger" else art_height * 0.94
			var bounds := Vector2(w - 18.0, height) * (1.10 if elite else 0.93)
			EnemyPortraits.draw(self, c, bounds, enemy_portrait, t + float(fighter.id.hash() % 29) * 0.11, elite)
		elif portrait != null:
			var art_size := portrait.get_size()
			art_size *= minf((w - 20.0) / art_size.x, art_height / art_size.y)
			var tint := Palette.UPGRADED if kind == "unit" else Color.WHITE
			if boss:
				tint = Color.WHITE.lerp(heat.lightened(0.62), charge * 0.28)
			draw_texture_rect(portrait, Rect2(c - art_size * 0.5, art_size), false, tint)
		else:
			Sigil.draw(self, c, r, fighter.def_id + fighter.name, col, t)
		if offline:
			var diagonal := Vector2(r * 0.6, r * 0.6)
			draw_line(c - diagonal, c + diagonal, Palette.HP, 3, true)
			diagonal.x *= -1
			draw_line(c - diagonal, c + diagonal, Palette.HP, 3, true)
		if targetable:
			_draw_fitted(font, "TARGET", Vector2(6, y + art_height + 4), w - 12, 12, Palette.ENERGY)
		y += art_height + (16 if kind == "enemy" else 4)
	if kind == "unit":
		draw_string(font, Vector2(4, y + 10), fighter.name, HORIZONTAL_ALIGNMENT_CENTER, w - 8, 12, Palette.TEXT)
		y += 14
	elif kind == "enemy":
		var name_size := 28 if boss_large else 20
		var name_inset := 23.0 if enemy_faction != "" else 6.0
		if enemy_faction != "":
			Symbols.draw_on(self, Vector2(14, y + name_size * 0.58), 8, enemy_faction, col)
		var name_font := Palette.NAME_FONT
		var name_width := w - 2.0 * name_inset
		if name_font.get_string_size(fighter.name, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x > name_width:
			var name_height := name_font.get_multiline_string_size(fighter.name, HORIZONTAL_ALIGNMENT_CENTER, name_width, 13).y
			draw_multiline_string(name_font, Vector2(name_inset, y + name_font.get_ascent(13)), fighter.name,
				HORIZONTAL_ALIGNMENT_CENTER, name_width, 13, 2, Palette.TEXT)
			y += name_height + 5
		else:
			_draw_fitted(name_font, fighter.name, Vector2(name_inset, y + name_size), name_width, name_size, Palette.TEXT)
			y += name_size + 7
	else:
		draw_string(Palette.display(), Vector2(12, 22), Palette.w("hero"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Palette.TEXT)
		y = 30.0

	# HP bar (+ Ward shield badge on its left).
	var bar := Rect2(26, y, w - 38, 17)
	draw_rect(bar, Color(Palette.CARD_BG, 0.85))
	# A daemon's HP is its countdown, so it gets the RAM colour instead of the HP red.
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(float(hp()) / fighter.max_hp, 0, 1), bar.size.y)), Palette.ENERGY if kind == "unit" else Palette.HP)
	if flash > 0.0 and kind == "player":
		draw_rect(bar.grow(3), Color(Palette.HP, flash * 0.6), false, 3)
	draw_rect(bar, Color(Palette.TEXT, 0.4), false, 1)
	var hp_text := "%d/%d HP" % [hp(), fighter.max_hp]
	_draw_fitted(font, hp_text, bar.position + Vector2(0, 13), bar.size.x, 14, Palette.TEXT)
	if ward() > 0:
		IntentIcon.draw(self, bar.position + Vector2(-12, 8), 13, "ward")
		draw_string(font, bar.position + Vector2(-26, 13), str(ward()), HORIZONTAL_ALIGNMENT_CENTER, 28, 12, Palette.TEXT)
	y += 22

	# Status chips.
	var chips: Array = []
	if kind == "unit":
		if offline:
			chips.append(["Offline", Palette.HP])
		else:
			# The rule this daemon enforces while it runs (its HP bar above is the countdown).
			draw_multiline_string(font, Vector2(4, y + 10), DaemonRules.describe(fighter.rule), HORIZONTAL_ALIGNMENT_CENTER, w - 8, 11, 4, Palette.TEXT)
			y += 48
	for k in fighter.statuses:
		var debuff: bool = Statuses.DEFS.get(k, {}).get("debuff", false)
		chips.append(["%s %d" % [Lexicon.status(str(k)), fighter.statuses[k]], Palette.ENEMY if debuff else Palette.UPGRADED])
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
	_draw_impact()
	draw_set_transform(Vector2.ZERO)


func _draw_target() -> void:
	var ink := Palette.ENERGY
	for corner in [Vector2(7, 7), Vector2(size.x - 7, 7), Vector2(7, size.y - 7), size - Vector2(7, 7)]:
		var dx := 12.0 if corner.x < size.x * 0.5 else -12.0
		var dy := 12.0 if corner.y < size.y * 0.5 else -12.0
		draw_polyline(PackedVector2Array([corner + Vector2(dx, 0), corner, corner + Vector2(0, dy)]), ink, 3, true)


func _draw_impact() -> void:
	if firewall_flash > 0.0:
		var shield := Rect2(Vector2(4, 4), size - Vector2(8, 8))
		var ink := Color(Palette.WARD, firewall_flash * 0.9)
		for x in [shield.position.x, shield.end.x]:
			draw_dashed_line(Vector2(x, shield.position.y), Vector2(x, shield.end.y), ink, 3.0, 7.0, true, true)
		for y in [shield.position.y, shield.end.y]:
			draw_dashed_line(Vector2(shield.position.x, y), Vector2(shield.end.x, y), ink, 3.0, 7.0, true, true)
	if flash > 0.0:
		var c := size * 0.5
		var ink := Color(Palette.HP, flash * 0.8)
		var slash := Vector2(minf(size.x * 0.28, 45.0), -minf(size.y * 0.21, 35.0))
		draw_line(c - slash, c + slash, ink, 6.0 * flash, true)


func _draw_fitted(font: Font, text: String, pos: Vector2, width: float, fs: int, col: Color) -> void:
	while fs > 9 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 1
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, fs, col)


func _move_name() -> String:
	return frozen_move if frozen_intents != null else str(fighter.current_move().get("name", ""))


func _draw_intents(font: Font, w: float, y: float, items: Array, charging: bool) -> float:
	if items.is_empty() or hp() <= 0:
		return y + 59
	var main_col := IntentIcon.color(items[0]["kind"])
	for it in items:
		if it["kind"] == "attack":
			main_col = IntentIcon.color("attack")
			break
	if charging:
		main_col = boss_accent
	var pill := StyleBoxFlat.new()
	pill.bg_color = Palette.CARD_BG.lerp(main_col, 0.12)
	pill.border_color = Color(main_col, 0.68)
	pill.set_border_width_all(1)
	pill.set_corner_radius_all(6)
	draw_style_box(pill, Rect2(8, y + 3, w - 16, 51))

	# Use the engine's values, including hits and area, while keeping wide combinations inside the tile.
	var slot := (w - 20) / items.size()
	var x := 10.0
	for it in items:
		var attack: bool = it["kind"] == "attack"
		var label := IntentIcon.label(it)
		var r := clampf(slot * 0.17, 3.0, 10.0)
		var fs := (26 if charging else 21) if attack else 14
		var icon_width := 2.0 * r + 3.0 if label != "" else 0.0
		var text_width := maxf(1.0, slot - icon_width)
		while fs > 9 and font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > text_width:
			fs -= 1
		var label_width := minf(text_width, font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		var start := x + (slot - icon_width - label_width) * 0.5
		IntentIcon.draw(self, Vector2(start + r if icon_width > 0 else x + slot * 0.5, y + 21), r, it["kind"])
		if label != "":
			draw_string(font, Vector2(start + icon_width, y + 28), label, HORIZONTAL_ALIGNMENT_LEFT, text_width, fs, Palette.TEXT)
		x += slot
	_draw_fitted(font, _move_name(), Vector2(12, y + 47), w - 24, 16 if charging else 13, Palette.TEXT)
	return y + 59


## Text for the inspect popup.
func describe() -> String:
	var nm := Palette.w("hero") if kind == "player" else fighter.name
	var lines: Array[String] = ["%s  (%d/%d HP)" % [nm, fighter.hp, fighter.max_hp]]
	if kind == "enemy" and not fighter.is_dead():
		lines.append("Next: " + Intents.explain(fighter))
	if kind == "unit":
		lines.append("Daemon: %s" % DaemonRules.describe(fighter.rule))
		lines.append("Its HP is its countdown: it loses 1 at the start of each of your turns and 1 per hit taken. Purge moves take more. At 0 it closes and the rule ends.")
	if fighter.ward > 0:
		lines.append("Firewall %d: absorbs damage first." % fighter.ward)
	for k in fighter.statuses:
		lines.append("%s %d: %s" % [Lexicon.status(str(k)), fighter.statuses[k], Statuses.DEFS.get(k, {}).get("desc", "")])
	return "\n".join(lines)
