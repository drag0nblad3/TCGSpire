class_name PackArt
extends Control
## A data cache on the shelf: each pack kind has its own packet look.
##   normal  -> RAM-yellow packet with a striped data seam
##   crew    -> the crew's color and emblem (Burner, Flux, ... Street)
##   premium -> Zero-day cache: magenta packet, rare-gold double frame and glitch bars
## draw_packet() is shared with the pack-opening animation so both match.

signal pressed(kind: String)

const SIZE := Vector2(150, 200)

var db: CardDB
var kind := Packs.NORMAL
var count := 0
## Icon mode: just the packet, no name, odds or count (pack screen header).
var mini := false
var _tap := Tap.new()
var _t := 0.0


func setup(db_in: CardDB, kind_in: String, count_in: int) -> PackArt:
	db = db_in
	kind = kind_in
	count = count_in
	custom_minimum_size = SIZE + Vector2(0, 44)
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = Packs.kind_name(db, kind)
	return self


## Small packet only, for headers.
func as_icon(extent: float = 64.0) -> PackArt:
	mini = true
	custom_minimum_size = Vector2(extent * 0.75, extent)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	return self


func _process(delta: float) -> void:
	if kind == Packs.PREMIUM:
		_t += delta
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if _tap.feed(event) == "tap" and count > 0:
		pressed.emit(kind)


## Main color of a pack kind.
static func tint(k: String) -> Color:
	if k == Packs.PREMIUM:
		return Palette.RARITY["mythic"]
	if Packs.crew_of(k) != "":
		return Palette.faction(Packs.crew_of(k))
	return Palette.ENERGY


## Second color: frame lines and highlights.
static func accent(k: String) -> Color:
	if k == Packs.PREMIUM:
		return Palette.RARITY["rare"]
	return tint(k).lightened(0.25)


## Display name, using the theme's word for a plain pack.
static func title(db_in: CardDB, k: String) -> String:
	return Palette.w("pack") if k == Packs.NORMAL else Packs.kind_name(db_in, k)


## "Burner cache: rare guaranteed within 3 · mythic within 18" (that kind's own mercy timers).
static func odds_line(db_in: CardDB, p: Profile, k: String) -> String:
	var bits: Array[String] = []
	var rare := Packs.pity_left(db_in, p, "rare", k)
	var myth := Packs.pity_left(db_in, p, "mythic", k)
	if Packs.odds_at_least(db_in, k, "rare") >= 0.999:
		bits.append("rare or better every time")
	elif rare > 0:
		bits.append("rare guaranteed within %d" % rare)
	if myth > 0:
		bits.append("mythic within %d" % myth)
	return "%s: %s" % [title(db_in, k), " · ".join(bits)]


## One packet in `rect`. split > 0 pulls the halves apart (opening), t animates premium glitch bars.
static func draw_packet(ci: CanvasItem, rect: Rect2, k: String, split: float = 0.0, t: float = 0.0) -> void:
	var col := tint(k)
	var acc := accent(k)
	var crew := Packs.crew_of(k)
	var half_w := rect.size.x * 0.5
	for side in [-1, 1]:
		var half := Rect2(rect.position + Vector2(half_w if side == 1 else 0.0, 0), Vector2(half_w, rect.size.y))
		half.position.x += side * split
		ci.draw_rect(half, Palette.PANEL_BG.darkened(0.2))
		ci.draw_rect(half, Color(col, 0.16))
		# Data rows: dense for premium, crew packs carry little emblem ticks.
		var rows := 9 if k == Packs.PREMIUM else 7
		for row in rows:
			var y := half.position.y + rect.size.y * (0.12 + 0.8 * row / float(rows))
			var inset := 10.0 + (6.0 if row % 2 == 1 and crew != "" else 0.0)
			ci.draw_line(Vector2(half.position.x + inset, y), Vector2(half.end.x - inset, y), Color(col, 0.28), 2.0)
		ci.draw_rect(half, col, false, 2.0)
	var moved := rect
	moved.position.x -= split
	moved.size.x += split * 2.0
	if k == Packs.PREMIUM:
		# Rare-gold double frame and drifting glitch bars.
		ci.draw_rect(moved.grow(5), acc, false, 2.0)
		for i in 4:
			var y := rect.position.y + fposmod(t * 40.0 + i * rect.size.y / 4.0, rect.size.y)
			ci.draw_rect(Rect2(moved.position.x - 4, y, moved.size.x * (0.3 + 0.15 * i), 3), Color(acc if i % 2 == 0 else Palette.WARD, 0.55))
	# Seam down the middle and the emblem on top.
	if split <= 0.0:
		ci.draw_line(rect.position + Vector2(half_w, 4), rect.position + Vector2(half_w, rect.size.y - 4), Color(acc, 0.6), 1.5)
	var center := rect.get_center()
	var r := rect.size.x * 0.24
	ci.draw_circle(center, r * 1.25, Color(Palette.PANEL_BG, 0.9))
	ci.draw_arc(center, r * 1.25, 0, TAU, 40, acc, 2.0, true)
	if crew != "":
		Symbols.draw_on(ci, center, r, crew, col)
	elif k == Packs.PREMIUM:
		Sigil.draw(ci, center, r * 0.9, "zero-day", acc, t)
		Symbols.draw_on(ci, center, r * 0.55, "vault", col)
	else:
		Sigil.draw(ci, center, r * 0.9, "data cache", col)


func _draw() -> void:
	if mini:
		draw_packet(self, Rect2(Vector2.ZERO, size), kind, 0.0, _t)
		return
	var rect := Rect2(Vector2((size.x - SIZE.x) * 0.5, 6), SIZE - Vector2(0, 6))
	draw_packet(self, rect, kind, 0.0, _t)
	var font := Palette.font()
	var name_text := title(db, kind)
	draw_string(font, Vector2(0, SIZE.y + 22), name_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 17, tint(kind))
	var odds := "Rare+ guaranteed" if Packs.odds_at_least(db, kind, "rare") >= 0.999 else ("Only %s programs" % Lexicon.faction(Packs.crew_of(kind)) if Packs.crew_of(kind) != "" else "Any crew")
	draw_string(font, Vector2(0, SIZE.y + 40), odds, HORIZONTAL_ALIGNMENT_CENTER, size.x, 13, Palette.TEXT_DIM)
	# Count chip, top right.
	var chip := Rect2(Vector2(rect.end.x - 34, rect.position.y - 6), Vector2(40, 26))
	draw_rect(chip, tint(kind))
	draw_string(font, chip.position + Vector2(0, 19), "x%d" % count, HORIZONTAL_ALIGNMENT_CENTER, chip.size.x, 16, Palette.CARD_BG)
