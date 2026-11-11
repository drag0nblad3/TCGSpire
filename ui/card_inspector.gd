class_name CardInspector
extends Control
## Press-and-hold any card: a large copy plus plain-language explanations of
## its type, keywords and every status it mentions. Tap anywhere to close.

var _card: CardInstance
var _tap := Tap.new()


static func show_for(host: Node, card: CardInstance) -> void:
	if card == null or not host.is_inside_tree():
		return
	var ci := CardInspector.new()
	ci._card = card
	host.get_tree().root.add_child(ci)


## Glossary lines for one card (also used by tests).
static func glossary(card: CardInstance) -> Array[String]:
	var out: Array[String] = []
	out.append(str(CardDef.TYPE_DESC.get(card.def.type, "")))
	for k in card.keywords():
		out.append("%s: %s" % [Lexicon.keyword(str(k)), CardDef.KEYWORD_DESC.get(k, "")])
	var seen := {}
	for e in card.effects():
		var op := str(e.get("op", ""))
		var st := str(e.get("status", ""))
		if st != "" and not seen.has(st) and Statuses.DEFS.has(st):
			seen[st] = true
			out.append("%s: %s" % [Lexicon.status(st), Statuses.DEFS[st]["desc"]])
		if op in ["ward", "damage_per_ward"] and not seen.has("ward"):
			seen["ward"] = true
			out.append(Rules.WARD)
		if op == "summon" and not seen.has("unit"):
			seen["unit"] = true
			out.append(Rules.UNITS)
	if not card.mod.is_empty():
		out.append("Mod: %s. %s" % [card.mod_name(), CardMods.describe(card.mod)])
	if card.fw > 0:
		out.append("Firmware v%d: its numbers are %d%% higher, permanently." % [card.fw, roundi((card.fw_mult() - 1.0) * 100)])
	if card.def.rarity != "curse":
		if card.upgraded:
			out.append("Upgraded (+): " + card.def.upgrade_summary() + " Recompiled at a safehouse for this run.")
		else:
			out.append("Upgrade (+): " + card.def.upgrade_summary() + " Recompile it at a safehouse for this run.")
	return out


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 90
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(Palette.PANEL_BG, 0.96)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var parts := UiKit.screen(18)
	parts[0].mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(0, CardView.SIZE.y * 2.0 + 10)
	var cv := CardView.new().setup(_card)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.scale = Vector2(2.0, 2.0)
	cv.pivot_offset = Vector2.ZERO
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.custom_minimum_size = CardView.SIZE * 2.0
	wrap.add_child(cv)
	holder.add_child(wrap)
	v.add_child(holder)
	for line in glossary(_card):
		if line != "":
			v.add_child(UiKit.label(line, 17, Palette.TEXT, true))
	v.add_child(UiKit.label("Tap anywhere to close", 14, Palette.TEXT_DIM))
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.12)


func _gui_input(event: InputEvent) -> void:
	if _tap.feed(event) == "tap":
		queue_free()
		accept_event()
