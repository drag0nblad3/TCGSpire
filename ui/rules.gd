class_name Rules
extends Control
## "How to play" overlay: rules, intent legend, statuses and keywords. Status and
## keyword text comes straight from Statuses.DEFS / CardDef.KEYWORD_DESC, so
## new content documents itself. Open with Rules.open(node).

const WARD := "Ward: absorbs damage before HP. Your Ward is cleared at the start of your turn (unless you have Fortify)."
const UNITS := "Units: allies on your board. Each strikes the front enemy at the end of your turn. Area attacks and attacks aimed at the front can hit them."

var _tap := Tap.new()


static func open(host: Node) -> void:
	host.get_tree().root.add_child(Rules.new())


## [heading, [lines]] pairs. Data only so it is easy to test and extend.
static func sections(db: CardDB) -> Array:
	var p: Dictionary = db.balance.get("player", {})
	var hero := Palette.w("hero")
	var out: Array = []
	if Palette.w("tagline") != "":
		out.append([Palette.w("title").capitalize(), [Palette.w("tagline")]])
	out.append(["The run", [
		"Climb floor by floor on the map. Each act ends with a boss; beat %s to win." % ("both acts" if int(db.balance.get("acts", 2)) == 2 else "all %d acts" % int(db.balance.get("acts", 2))),
		"Your HP carries over between fights. Rest sites, some events and talismans heal you.",
		"After a fight you choose one card to add to your deck (or skip). A lean deck draws its best cards more often.",
	]])
	out.append(["Your turn", [
		"You start each turn with %d energy and draw %d cards. A card's cost is in its top-left orb." % [int(p.get("max_energy", 3)), int(p.get("hand_size", 5))],
		"Tap a card to play it. If it needs a target and there are several enemies, tap the enemy next. Tap the card again to cancel.",
		"Press and hold any card to read it large, with every keyword explained. Hold an enemy to read its next move.",
		"End turn: your units strike, then the cards left in your hand are discarded. When your draw pile runs out, the discard pile is shuffled back in.",
		"The buttons above the battlefield show your draw pile (in random order), discard pile, exhausted cards and whole deck.",
	]])
	out.append(["Enemy intents", ["Each enemy shows what it will do on its turn. The icons:"]])
	out.append(["Defence", [WARD, UNITS]])
	var st: Array = []
	for k in Statuses.DEFS:
		st.append("%s%s: %s" % [str(k).capitalize(), " (harmful)" if Statuses.DEFS[k]["debuff"] else "", Statuses.DEFS[k]["desc"]])
	out.append(["Statuses", st])
	var kw: Array = []
	for t in CardDef.TYPE_DESC:
		kw.append(CardDef.TYPE_DESC[t])
	for k in CardDef.KEYWORD_DESC:
		kw.append("%s: %s" % [str(k).capitalize(), CardDef.KEYWORD_DESC[k]])
	out.append(["Cards and keywords", kw])
	var factions: Array[String] = []
	for f in ["ember", "tide", "bloom", "void"]:
		factions.append(Palette.faction_name(f))
	out.append(["Between fights", [
		"Elites are tougher fights that drop talismans. Talismans are passive items that trigger on their own.",
		"%s: rest to heal or upgrade a card. %s: buy cards and talismans, or remove a card. Events (?) are choices with risks." % [Palette.w("rest"), Palette.w("shop")],
	]])
	out.append(["Collection", [
		"Your deck is built from cards you own. Before each run you pick extra cards from your collection.",
		"Runs earn XP and %s. Open them to collect new cards (rarer cards add complexity, not raw power)." % Palette.w("packs").to_lower(),
		"Disenchant spare cards into %s and craft the ones you want. Playing a card often raises its mastery." % Palette.w("dust").to_lower(),
		"Factions: %s, plus %s (neutral) cards that fit any deck." % [", ".join(factions), Palette.faction_name("neutral")],
		"%s: beat the boss to unlock harder runs with extra modifiers." % "Heat",
	]])
	out.append(["Tips", [
		"An enemy's attack number already includes its Might, its Weaken and your Brittle, so you can Ward exactly enough.",
		"The %s's HP bar sits under the battlefield. Ward shows as a blue shield beside it." % hero,
	]])
	return out


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 80
	var bg := ColorRect.new()
	bg.color = Color(Palette.PANEL_BG, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var parts := UiKit.screen(10, BoxContainer.ALIGNMENT_BEGIN)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("How to play", 30, Palette.ENERGY))
	var inner := UiKit.scroll(v)
	for sec in sections(CardDB.shared()):
		var h := UiKit.label(sec[0], 21, Palette.ENERGY)
		h.add_theme_font_override("font", Palette.display())
		inner.add_child(h)
		for line in sec[1]:
			var l := UiKit.label(str(line), 16, Palette.TEXT, true)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size.x = 0
			inner.add_child(l)
		if sec[0] == "Enemy intents":
			inner.add_child(_legend())
	v.add_child(UiKit.button("Close", queue_free, Vector2(200, 56)))


func _legend() -> Control:
	var box := VBoxContainer.new()
	for k in Intents.DESC:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.draw.connect(func() -> void: IntentIcon.draw(icon, icon.size / 2, 13, k))
		row.add_child(icon)
		var l := UiKit.label(str(Intents.DESC[k]), 15, Palette.TEXT, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.custom_minimum_size.x = 0
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		box.add_child(row)
	return box
