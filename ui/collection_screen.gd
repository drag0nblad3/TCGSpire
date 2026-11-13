class_name CollectionScreen
extends Control
## Browse every card, filter by faction, and craft/disenchant with dust.
## Also used as the pre-run deck picker (pick_mode = true).

signal closed
signal picks_confirmed(picks: Array)

const FILTERS := ["all", "upgradable", "neutral", "ember", "tide", "bloom", "void", "chrome", "noise"]

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
			if picks.count(id) < p.deck_copies(db_in, id) and picks.size() < p.starter_picks(db) and db.card(id) != null and db.card(id).faction not in ban:
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
		v.add_child(_loadout_row())
	var filters := UiKit.hbox(8)
	for f in FILTERS:
		if pick_mode and f in targets:
			continue
		if pick_mode and f == "upgradable":
			continue
		var filter := UiKit.button({"all": "All", "upgradable": "Upgrades"}.get(f, Lexicon.faction(f)), func() -> void: _set_filter(f), Vector2(76, 44), 13)
		if f == "upgradable":
			filter.tooltip_text = "Programs with enough copies for their next firmware level."
		elif f != "all":
			filter.icon = Symbols.texture(f)
			filter.add_theme_constant_override("icon_max_width", 14)
			var accent := Palette.faction(f)
			# Filter buttons retain their dark fill even in Parchment.
			if Palette.CARD_BG.get_luminance() > 0.5:
				accent = Color(Themes.FACTIONS_DARK[f])
			for state in ["normal", "hover", "pressed", "focus"]:
				filter.add_theme_color_override("icon_" + state + "_color", accent)
		filters.add_child(filter)
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


## Saved loadouts for this crew: tap a slot to load it, "Save" stores the current picks there.
func _loadout_row() -> Control:
	var row := UiKit.hbox(8)
	row.add_child(UiKit.label("Loadouts", 14, Palette.TEXT_DIM))
	for slot in Profile.LOADOUT_SLOTS:
		var saved := profile.loadout(job, slot)
		var load_b := UiKit.button("Slot %d\n%s" % [slot + 1, ("%d programs" % saved.size()) if not saved.is_empty() else "empty"], func() -> void:
			var got := profile.usable_loadout(db, job, slot, targets)
			if got.is_empty():
				UiKit.toast(self, "Slot %d is empty." % (slot + 1))
				return
			picks = got
			_refresh(), Vector2(104, 52), 13)
		load_b.disabled = saved.is_empty()
		row.add_child(load_b)
		row.add_child(UiKit.button("Save", func() -> void:
			profile.save_loadout(job, slot, picks)
			profile.save()
			UiKit.toast(self, "Saved to slot %d." % (slot + 1))
			_rebuild(), Vector2(64, 52), 13))
	return row


## Rebuilds the whole screen (loadout labels change after a save).
func _rebuild() -> void:
	for n in get_children():
		n.queue_free()
	_ready()


func _base_summary() -> String:
	var counts := {}
	for id in profile.base_deck(db):
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
		return c.rarity not in ["starter", "curse"] and (_filter == "all" or c.faction == _filter or (_filter == "upgradable" and _copies_ready(c.id))) \
			and (not pick_mode or (profile.collection.owns(c.id) and c.faction not in targets)))
	var order := CardDef.RARITIES
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ca := db.card(a)
		var cb := db.card(b)
		return [ca.faction, order.find(ca.rarity), ca.cost, a] < [cb.faction, order.find(cb.rarity), cb.cost, b])
	return ids


## Owns enough copies for the next firmware level (rep/dust may still be short).
func _copies_ready(id: String) -> bool:
	return profile.copies_ready(db, id)


## [owned, total] collectible programs (no base programs or malware).
static func library_progress(db_in: CardDB, p: Profile) -> Array:
	var total := db_in.ids_where(func(c: CardDef) -> bool: return c.rarity not in ["starter", "curse"]).size()
	var owned := p.collection.owned_ids().filter(func(id: String) -> bool: return db_in.card(id) != null and db_in.card(id).rarity not in ["starter", "curse"]).size()
	return [owned, total]


func _refresh() -> void:
	var col := profile.collection
	var lib := library_progress(db, profile)
	var owned: int = lib[0]
	var total: int = lib[1]
	if pick_mode:
		_header.text = "Pick your starting cards: %d / %d" % [picks.size(), profile.starter_picks(db)]
		var problem := Jobs.check(db, job, picks, profile.starter_picks(db), targets)
		_problem.text = problem
		if _begin != null:
			_begin.disabled = problem != ""
	else:
		var ready := profile.ready_to_flash(db).size()
		_header.text = "Library %d / %d   ·   %s %d%s" % [owned, total, Palette.w("dust"), col.dust, ("   ·   %d ready to flash" % ready) if ready > 0 else ""]
	for n in _grid.get_children():
		n.queue_free()
	for id in _ids():
		var inst := db.instance(id, false, profile.firmware_level(id))
		inst.foil = int(col.foils.get(id, 0)) > 0
		if profile.firmware_mods.has(id):
			inst.mod = db.mod(profile.firmware_mods[id])
		var cv := CardView.new().setup(inst)
		var n := col.count(id)
		var stars := "*".repeat(profile.mastery_tier(db, id))
		if pick_mode:
			var chosen := picks.count(id)
			cv.badge = "%d/%d" % [chosen, profile.deck_copies(db, id)]
			cv.selected = chosen > 0
		else:
			cv.badge = profile.copy_badge(db, id) + (" " + stars if stars != "" else "")
			cv.playable = n > 0
		cv.pressed.connect(func(_v: CardView) -> void: _on_card(id))
		_grid.add_child(cv)


func _on_card(id: String) -> void:
	if pick_mode:
		var chosen := picks.count(id)
		if chosen < profile.deck_copies(db, id) and picks.size() < profile.starter_picks(db):
			picks.append(id)
		else:
			while id in picks:
				picks.erase(id)
		_refresh()
		return
	_show_detail(id)


## Permanent upgrade: flash the card's firmware (two levels) so every copy starts runs stronger.
func _firmware_row(id: String, overlay: Control) -> Control:
	var box := UiKit.vbox(6)
	var lvl := profile.firmware_level(id)
	var scale := db.firmware_scale()
	if lvl < Profile.firmware_max(db):
		box.add_child(_flash_button(id, overlay, lvl, scale))
	if lvl > 0:
		var baked := str(profile.firmware_mods.get(id, ""))
		box.add_child(UiKit.label("Firmware v%d: every copy joins your runs with +%d%% numbers%s." % [lvl, roundi((float(scale[lvl]) - 1.0) * 100), (" and " + db.mod(baked)["name"]) if baked != "" else ""], 15, Palette.UPGRADED, true))
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


func _flash_button(id: String, overlay: Control, lvl: int, scale: Array) -> Control:
	var box := UiKit.vbox(4)
	var price := profile.firmware_price(db, id)
	var cur := Palette.w("dust").to_lower() if price["faction"] == "" else Jobs.rep_name(db, price["faction"])
	var block := profile.firmware_block(db, id).replace("dust", Palette.w("dust").to_lower())
	var b := UiKit.button("Flash firmware v%d (%d %s)" % [lvl + 1, price["amount"], cur], func() -> void:
		if profile.flash_firmware(db, id):
			profile.save()
			overlay.queue_free()
			_refresh()
			_show_detail(id), Vector2(360, 56), 16)
	b.disabled = block != ""
	box.add_child(b)
	box.add_child(UiKit.label(block if block != "" else "Permanent: every copy starts your runs with +%d%% numbers (Firewall, damage, statuses, daemons)." % roundi((float(scale[lvl + 1]) - 1.0) * 100), 13, Palette.TEXT_DIM, true))
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
	var shown := db.instance(id, false, profile.firmware_level(id))
	if profile.firmware_mods.has(id):
		shown.mod = db.mod(profile.firmware_mods[id])
	shown.foil = int(col.foils.get(id, 0)) > 0
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
	var need := profile.firmware_copies_needed(db, id)
	if need > 0:
		var spare := profile.spare_copies(db, id)
		var short := need - spare
		v.add_child(UiKit.label(("Extra copies %d / %d for firmware v%d (your first %d are deck copies; flashing uses the extras up)" % [spare, need, profile.firmware_level(id) + 1, Profile.deck_limit(db)]) + \
			(": compile %d more" % short if short > 0 else ": ready to flash below"), 16, Palette.UPGRADED if short <= 0 else Palette.ENERGY, true))
	elif profile.copies_complete(db, id):
		v.add_child(UiKit.label("Firmware maxed and a full deck's worth owned. Spare copies are %s." % Palette.w("dust").to_lower(), 14, Palette.TEXT_DIM, true))
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
		if profile.disenchant(db, id):
			profile.save()
			overlay.queue_free()
			_refresh()
			_show_detail(id), Vector2(220, 60))
	dis.disabled = col.count(id) <= 1
	row.add_child(dis)
	if int(col.foils.get(id, 0)) > 0:
		var fdis := UiKit.button("Disenchant foil (+%d)" % Collection.foil_value(id, db), func() -> void:
			if profile.disenchant_foil(db, id):
				profile.save()
				overlay.queue_free()
				_refresh()
				_show_detail(id), Vector2(240, 60))
		fdis.disabled = col.count(id) <= 1
		row.add_child(fdis)
	v.add_child(row)
	v.add_child(UiKit.label("Your last copy can't be disenchanted.", 12, Palette.TEXT_DIM, true))
	v.add_child(_firmware_row(id, overlay))
	v.add_child(UiKit.button("Close", func() -> void: overlay.queue_free()))
