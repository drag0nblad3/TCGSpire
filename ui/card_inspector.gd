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
	if card.has_loop():
		out.append("%s: %s" % [Lexicon.keyword("loop"), CardDef.KEYWORD_DESC["loop"]])
	if card.is_x():
		out.append("%s: %s" % [Lexicon.keyword("x_cost"), CardDef.KEYWORD_DESC["x_cost"]])
	if not card.def.evolve.is_empty():
		out.append("Evolve: %s Evolves into %s after %d runs (%d so far)." % [CardDef.KEYWORD_DESC["evolve"], Lexicon.card_name(str(card.def.evolve.get("into", ""))), int(card.def.evolve.get("after", 20)), card.uses])
	if not card.def.get_on_dump(card.upgraded).is_empty():
		out.append("%s: %s" % [Lexicon.keyword("on_dump"), CardDef.KEYWORD_DESC["on_dump"]])
	var seen := {}
	var effs: Array = card.effects()
	var pair := evolve_pair(card)
	if not pair.is_empty() and pair[0] == card:
		effs += (pair[1] as CardInstance).effects()  # explain the evolved form's statuses too
	for e in effs:
		var op := str(e.get("op", ""))
		if CardPrograms.DESCRIPTIONS.has(op) and not seen.has(op):
			seen[op] = true
			out.append("%s: %s" % [op.capitalize(), CardPrograms.DESCRIPTIONS[op]])
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
		out.append("Firmware v%d: its numbers are %d%% higher." % [card.fw, roundi((card.fw_mult() - 1.0) * 100)])
	if card.def.rarity != "curse":
		out.append("Upgrades climb v1 (+%d%%), v2 (+%d%%), then (+): %s Recompile at a safehouse for this run, or collect copies and flash firmware for good. (+) opens once the rest of your deck is v2." % [25, 50, card.def.upgrade_summary()] if card.fw_scale.size() < 3 else "Upgrades climb v1 (+%d%%), v2 (+%d%%), then (+): %s Recompile at a safehouse for this run, or collect copies and flash firmware for good. (+) opens once the rest of your deck is v2." % [roundi((float(card.fw_scale[1]) - 1.0) * 100), roundi((float(card.fw_scale[2]) - 1.0) * 100), card.def.upgrade_summary()])
		if card.upgraded:
			out.append("This copy is fully upgraded (+).")
	var src := evolved_from(card.def.id)
	if src != null:
		out.append("Evolved form: %s turns into this after %d runs. It only appears inside a run." % [src.name, int(src.evolve.get("after", 20))])
	return out


## The base card a token evolves from, or null.
static func evolved_from(id: String) -> CardDef:
	var db := CardDB.shared()
	for cid in db.cards:
		var c: CardDef = db.cards[cid]
		if str(c.evolve.get("into", "")) == id:
			return c
	return null


## The pair to draw side by side for an Evolve card: [before, after], or [] if it has no evolution.
## The evolved copy keeps this copy's upgrade, firmware and mod, as it does in a fight.
static func evolve_pair(card: CardInstance) -> Array:
	var db := CardDB.shared()
	if not card.def.evolve.is_empty():
		var into: CardDef = db.card(str(card.def.evolve.get("into", "")))
		if into == null:
			return []
		var after := card.copy()
		after.def = into
		after.uses = 0
		after.foil = false
		return [card, after]
	var src := evolved_from(card.def.id)
	if src == null:
		return []
	var before := card.copy()
	before.def = src
	before.foil = false
	return [before, card]


static func _card_box(c: CardInstance, zoom: float, dim: bool) -> Control:
	var cv := CardView.new().setup(c)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.scale = Vector2(zoom, zoom)
	cv.pivot_offset = Vector2.ZERO
	if dim:
		cv.modulate = Color(1, 1, 1, 0.75)
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.custom_minimum_size = CardView.SIZE * zoom
	wrap.add_child(cv)
	return wrap


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
	var pair := evolve_pair(_card)
	if pair.is_empty():
		holder.custom_minimum_size = Vector2(0, CardView.SIZE.y * 2.0 + 10)
		holder.add_child(_card_box(_card, 2.0, false))
	else:
		# Evolve: this card and what it becomes, side by side.
		var zoom := 1.55
		holder.custom_minimum_size = Vector2(0, CardView.SIZE.y * zoom + 10)
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var base: CardInstance = pair[0]
		row.add_child(_card_box(pair[0], zoom, pair[0] != _card))
		var mid := VBoxContainer.new()
		mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mid.alignment = BoxContainer.ALIGNMENT_CENTER
		mid.custom_minimum_size = Vector2(76, 0)
		var after_n := int(base.def.evolve.get("after", 20))
		mid.add_child(UiKit.label("EVOLVE", 14, Palette.UPGRADED))
		mid.add_child(UiKit.label("→", 40, Palette.UPGRADED))
		if pair[0] == _card:
			mid.add_child(UiKit.label("%d/%d\nruns" % [_card.uses, after_n], 15, Palette.TEXT))
		else:
			mid.add_child(UiKit.label("after\n%d runs" % after_n, 15, Palette.TEXT))
		for l in mid.get_children():
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(mid)
		row.add_child(_card_box(pair[1], zoom, pair[1] != _card))
		holder.add_child(row)
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
