class_name TalismanView
extends Control
## Round badge with a procedural sigil for a talisman. Tap shows its text.

signal pressed(id: String)

var tid := ""
var rarity := "common"
var big := false


func setup(id: String, db: CardDB, big_in: bool = false) -> TalismanView:
	tid = id
	big = big_in
	rarity = str(db.talismans.get(id, {}).get("rarity", "common"))
	custom_minimum_size = Vector2(72, 72) if big else Vector2(40, 40)
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


var _tap := Tap.new()


func _gui_input(event: InputEvent) -> void:
	if _tap.feed(event) == "tap":
		pressed.emit(tid)
		accept_event()


func _draw() -> void:
	var c := size / 2
	var r := minf(size.x, size.y) / 2 - 2
	var col: Color = Palette.RARITY.get(rarity, Palette.ENERGY) if rarity != "boss" else Palette.ENEMY
	draw_circle(c, r, Palette.CARD_BG)
	draw_arc(c, r, 0, TAU, 32, col, 2.0, true)
	Sigil.draw(self, c, r * 0.6, "talisman:" + tid, col)


static func text(db: CardDB, id: String) -> String:
	var t: Dictionary = db.talismans.get(id, {})
	return "%s (%s)\n%s" % [t.get("name", id), t.get("rarity", ""), Talismans.describe(t)]
