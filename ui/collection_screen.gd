class_name CollectionScreen
extends Control
## Browse every card, filter by faction, and craft/disenchant with dust.
## Also used as the pre-run deck picker (pick_mode = true).

signal closed
signal picks_confirmed(picks: Array)

const FILTERS := ["all", "neutral", "ember", "tide", "bloom"]

var db: CardDB
var profile: Profile
var pick_mode := false
var picks: Array = []
var _filter := "all"
var _grid: HFlowContainer
var _header: Label


func setup(db_in: CardDB, p: Profile, pick: bool = false) -> CollectionScreen:
	db = db_in
	profile = p
	pick_mode = pick
	if pick:
		for id in p.last_picks:
			if picks.count(id) < p.collection.count(id) and picks.size() < p.starter_picks(db):
				picks.append(id)
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parts := UiKit.screen(12, BoxContainer.ALIGNMENT_BEGIN)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	_header = UiKit.label("", 20, Palette.TEXT, true)
	v.add_child(_header)
	if pick_mode:
		v.add_child(UiKit.label("Your run starts with the base deck (%s) plus the cards you pick here." % _base_summary(), 14, Palette.TEXT_DIM, true))
	var filters := UiKit.hbox(8)
	for f in FILTERS:
		filters.add_child(UiKit.button(f.capitalize(), func() -> void: _set_filter(f), Vector2(100, 44), 15))
	v.add_child(filters)
	var inner := UiKit.scroll(v)
	_grid = UiKit.flow(10)
	inner.add_child(_grid)
	var bottom := UiKit.hbox(16)
	bottom.add_child(UiKit.button("Back", func() -> void: closed.emit(), Vector2(160, 60)))
	if pick_mode:
		bottom.add_child(UiKit.button("Begin run", func() -> void: picks_confirmed.emit(picks.duplicate()), Vector2(220, 60), 22))
	v.add_child(bottom)
	_refresh()


func _base_summary() -> String:
	var counts := {}
	for id in db.balance.get("base_deck", []):
		counts[id] = int(counts.get(id, 0)) + 1
	var parts: Array[String] = []
	for id in counts:
		parts.append("%d %s" % [counts[id], db.card(id).name])
	return ", ".join(parts)


func _set_filter(f: String) -> void:
	_filter = f
	_refresh()


func _ids() -> Array:
	var ids := db.ids_where(func(c: CardDef) -> bool:
		return c.rarity not in ["starter", "curse"] and (_filter == "all" or c.faction == _filter) \
			and (not pick_mode or profile.collection.owns(c.id)))
	var order := CardDef.RARITIES
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ca := db.card(a)
		var cb := db.card(b)
		return [ca.faction, order.find(ca.rarity), ca.cost, a] < [cb.faction, order.find(cb.rarity), cb.cost, b])
	return ids


func _refresh() -> void:
	var col := profile.collection
	var total := db.ids_where(func(c: CardDef) -> bool: return c.rarity not in ["starter", "curse"]).size()
	var owned := col.owned_ids().filter(func(id: String) -> bool: return db.card(id) != null and db.card(id).rarity not in ["starter", "curse"]).size()
	if pick_mode:
		_header.text = "Pick your starting cards: %d / %d" % [picks.size(), profile.starter_picks(db)]
	else:
		_header.text = "Collection %d / %d   ·   Dust %d" % [owned, total, col.dust]
	for n in _grid.get_children():
		n.queue_free()
	for id in _ids():
		var inst := db.instance(id)
		inst.foil = int(col.foils.get(id, 0)) > 0
		var cv := CardView.new().setup(inst)
		var n := col.count(id)
		var stars := "*".repeat(profile.mastery_tier(db, id))
		if pick_mode:
			var chosen := picks.count(id)
			cv.badge = "%d/%d" % [chosen, n]
			cv.selected = chosen > 0
		else:
			cv.badge = ("x%d" % n if n > 0 else "new") + (" " + stars if stars != "" else "")
			cv.playable = n > 0
		cv.pressed.connect(func(_v: CardView) -> void: _on_card(id))
		_grid.add_child(cv)


func _on_card(id: String) -> void:
	if pick_mode:
		var chosen := picks.count(id)
		if chosen < profile.collection.count(id) and picks.size() < profile.starter_picks(db):
			picks.append(id)
		else:
			while id in picks:
				picks.erase(id)
		_refresh()
		return
	_show_detail(id)


func _show_detail(id: String) -> void:
	var col := profile.collection
	var c := db.card(id)
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.02, 0.05, 0.92)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var parts := UiKit.screen(18)
	overlay.add_child(parts[0])
	var v: VBoxContainer = parts[1]
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(0, CardView.SIZE.y * 1.7)
	var cv := CardView.new().setup(db.instance(id))
	cv.scale = Vector2(1.6, 1.6)
	holder.add_child(cv)
	v.add_child(holder)
	var up := db.instance(id, true)
	v.add_child(UiKit.label("Upgraded: " + up.text(), 15, Palette.UPGRADED, true))
	v.add_child(UiKit.label("Owned %d   ·   Foils %d   ·   Played %d times" % [col.count(id), int(col.foils.get(id, 0)), int(profile.mastery.get(id, 0))], 15, Palette.TEXT_DIM))
	var mtiers: Array = db.balance.get("mastery", [])
	var next_t := ""
	for t in mtiers:
		if int(profile.mastery.get(id, 0)) < int(t["plays"]):
			next_t = "Next mastery at %d plays: %s" % [int(t["plays"]), "foil copy" if t.get("foil", false) else "+%d dust" % int(t.get("dust", 0))]
			break
	if next_t != "":
		v.add_child(UiKit.label(next_t, 14, Palette.ENERGY))
	var row := UiKit.hbox(14)
	var craft_cost := col.craft_cost(id, db)
	var craft := UiKit.button("Craft (%d dust)" % craft_cost, func() -> void:
		if col.craft(id, db):
			profile.save()
			overlay.queue_free()
			_refresh()
			_show_detail(id), Vector2(220, 60))
	craft.disabled = col.dust < craft_cost
	row.add_child(craft)
	var value := int(db.balance.get("dust", {}).get("disenchant", {}).get(c.rarity, 0))
	var dis := UiKit.button("Disenchant (+%d)" % value, func() -> void:
		if col.disenchant(id, db):
			profile.save()
			overlay.queue_free()
			_refresh()
			_show_detail(id), Vector2(220, 60))
	dis.disabled = col.count(id) <= 1
	row.add_child(dis)
	v.add_child(row)
	v.add_child(UiKit.label("Your last copy can't be disenchanted.", 12, Palette.TEXT_DIM))
	v.add_child(UiKit.button("Close", func() -> void: overlay.queue_free()))
