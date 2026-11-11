class_name CollectionScreen
extends Control
## Browse every card, filter by faction, and craft/disenchant with dust.
## Also used as the pre-run deck picker (pick_mode = true).

signal closed
signal picks_confirmed(picks: Array)

const FILTERS := ["all", "neutral", "ember", "tide", "bloom", "void", "chrome", "noise"]

var db: CardDB
var profile: Profile
var pick_mode := false
var picks: Array = []
## Pick mode for a job: client faction ("" = no rules). Banned factions are hidden.
var job := ""
## Crews the job runs against (banned). Empty = the client's rivals.
var targets: Array = []
var _problem: Label
var _begin: Button
var _filter := "all"
var _grid: HFlowContainer
var _header: Label


func setup(db_in: CardDB, p: Profile, pick: bool = false, job_in: String = "", targets_in: Array = []) -> CollectionScreen:
	db = db_in
	profile = p
	pick_mode = pick
	job = job_in
	targets = targets_in if not targets_in.is_empty() else Jobs.banned(db, job)
	if pick:
		var ban := targets
		for id in p.last_picks:
			if picks.count(id) < p.collection.count(id) and picks.size() < p.starter_picks(db) and db.card(id) != null and db.card(id).faction not in ban:
				picks.append(id)
		if Jobs.check(db, job, picks, p.starter_picks(db), targets) != "":
			picks = RunState.default_picks(db, p, job, targets)
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parts := UiKit.screen(12, BoxContainer.ALIGNMENT_BEGIN)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	_header = UiKit.label("", 20, Palette.TEXT, true)
	v.add_child(_header)
	if pick_mode:
		v.add_child(UiKit.label("Every run starts with your base rig (%s) plus the programs you pick here." % _base_summary(), 14, Palette.TEXT_DIM, true))
		if job != "":
			var ban: Array = targets.map(func(x: String) -> String: return Lexicon.faction(x))
			v.add_child(UiKit.label("Job for %s: at least %d %s programs. %s programs are banned." % [Jobs.info(db, job).get("client", job),
				Jobs.required(db, job, profile.starter_picks(db)), Lexicon.faction(job), " and ".join(ban)], 15, Palette.faction(job), true))
		_problem = UiKit.label("", 14, Palette.HP, true)
		v.add_child(_problem)
	var filters := UiKit.hbox(8)
	for f in FILTERS:
		if pick_mode and f in targets:
			continue
		filters.add_child(UiKit.button("All" if f == "all" else Lexicon.faction(f), func() -> void: _set_filter(f), Vector2(76, 44), 13))
	v.add_child(filters)
	var inner := UiKit.scroll(v)
	_grid = UiKit.flow(10)
	inner.add_child(_grid)
	var bottom := UiKit.hbox(16)
	bottom.add_child(UiKit.button("Back", func() -> void: closed.emit(), Vector2(160, 60)))
	if pick_mode:
		_begin = UiKit.button("Begin run", func() -> void:
			if Jobs.check(db, job, picks, profile.starter_picks(db), targets) == "":
				picks_confirmed.emit(picks.duplicate()), Vector2(220, 60), 22)
		bottom.add_child(_begin)
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
			and (not pick_mode or (profile.collection.owns(c.id) and c.faction not in targets)))
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
		var problem := Jobs.check(db, job, picks, profile.starter_picks(db), targets)
		_problem.text = problem
		if _begin != null:
			_begin.disabled = problem != ""
	else:
		_header.text = "Library %d / %d   ·   %s %d" % [owned, total, Palette.w("dust"), col.dust]
	for n in _grid.get_children():
		n.queue_free()
	for id in _ids():
		var inst := db.instance(id, profile.firmware.has(id))
		inst.foil = int(col.foils.get(id, 0)) > 0
		if profile.firmware_mods.has(id):
			inst.mod = db.mod(profile.firmware_mods[id])
		var cv := CardView.new().setup(inst)
		var n := col.count(id)
		var stars := "*".repeat(profile.mastery_tier(db, id))
		if pick_mode:
			var chosen := picks.count(id)
			cv.badge = "%d/%d" % [chosen, n]
			cv.selected = chosen > 0
		else:
			cv.badge = ("x%d" % n if n > 0 else "new") + (" " + stars if stars != "" else "") + (" FW" if profile.firmware.has(id) else "")
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


## Permanent upgrade: flash the card to firmware so every copy starts runs upgraded.
func _firmware_row(id: String, overlay: Control) -> Control:
	var box := UiKit.vbox(6)
	if profile.firmware.has(id):
		var baked := str(profile.firmware_mods.get(id, ""))
		box.add_child(UiKit.label("In firmware: every copy joins your runs upgraded%s." % ((" with " + db.mod(baked)["name"]) if baked != "" else ""), 15, Palette.UPGRADED, true))
		var fits: Array = db.mods.keys().filter(func(m: String) -> bool: return CardMods.can_apply(db.mod(m), CardInstance.new(db.card(id), true)))
		fits.sort()
		var gate := profile.firmware_mod_block(db, id, fits[0]) if not fits.is_empty() else "No mods fit."
		if gate.begins_with("Run it") or fits.is_empty():
			box.add_child(UiKit.label(gate, 13, Palette.TEXT_DIM, true))
			return box
		box.add_child(UiKit.label("Bake a mod into its firmware:", 14, Palette.TEXT_DIM))
		var row := UiKit.flow(6)
		for m in fits:
			var price := profile.firmware_mod_price(db, id, m)
			var cur := Palette.w("dust").to_lower() if price["faction"] == "" else "rep"
			var mb := UiKit.button("%s\n%d %s" % [db.mod(m)["name"], price["amount"], cur], func() -> void:
				if profile.bake_firmware_mod(db, id, m):
					profile.save()
					overlay.queue_free()
					_refresh()
					_show_detail(id), Vector2(150, 52), 13)
			mb.disabled = profile.firmware_mod_block(db, id, m) != "" or baked == m
			mb.tooltip_text = CardMods.describe(db.mod(m))
			row.add_child(mb)
		box.add_child(row)
		return box
	var price := profile.firmware_price(db, id)
	var cur := Palette.w("dust").to_lower() if price["faction"] == "" else Jobs.rep_name(db, price["faction"])
	var block := profile.firmware_block(db, id).replace("dust", Palette.w("dust").to_lower())
	var b := UiKit.button("Flash to firmware (%d %s)" % [price["amount"], cur], func() -> void:
		if profile.flash_firmware(db, id):
			profile.save()
			overlay.queue_free()
			_refresh()
			_show_detail(id), Vector2(360, 56), 16)
	b.disabled = block != ""
	box.add_child(b)
	box.add_child(UiKit.label(block if block != "" else "Permanent: every copy starts your runs upgraded.", 13, Palette.TEXT_DIM, true))
	return box


func _show_detail(id: String) -> void:
	var col := profile.collection
	var c := db.card(id)
	var overlay := ColorRect.new()
	overlay.color = Color(Palette.PANEL_BG, 0.97)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var parts := UiKit.screen(18)
	overlay.add_child(parts[0])
	var v: VBoxContainer = parts[1]
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(0, CardView.SIZE.y * 1.7)
	var shown := db.instance(id, profile.firmware.has(id))
	if profile.firmware_mods.has(id):
		shown.mod = db.mod(profile.firmware_mods[id])
	var cv := CardView.new().setup(shown)
	cv.scale = Vector2(1.6, 1.6)
	holder.add_child(cv)
	v.add_child(holder)
	var up := db.instance(id, true)
	v.add_child(UiKit.label("Upgrade (+): " + c.upgrade_summary(), 15, Palette.UPGRADED, true))
	v.add_child(UiKit.label("Upgraded text: " + up.text(), 13, Palette.TEXT_DIM, true))
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
	v.add_child(_firmware_row(id, overlay))
	v.add_child(UiKit.button("Close", func() -> void: overlay.queue_free()))
