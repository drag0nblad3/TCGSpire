extends Control
## App shell: owns the Profile and the current RunState and swaps screens.
## Flow: Hub -> deck picker -> Map -> node screen (fight/rest/shop/event/
## treasure) -> Map ... -> boss -> run summary -> Hub. Packs open from the Hub.

const BACKDROP := preload("res://shaders/backdrop.gdshader")

var db: CardDB
var profile: Profile
var run: RunState
var _screen: Control
var _combat: Combat
var _bg_mat: ShaderMaterial
## Screenshot/smoke tools turn this off so they never touch the real save.
var persist := true


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = BACKDROP
	bg.material = _bg_mat
	add_child(bg)
	db = CardDB.shared()
	profile = Profile.load_or_new(db)
	apply_theme(str(profile.settings.get("theme", Themes.DEFAULT)))
	show_hub()


## Restyles everything: colors, fonts, frames, backdrop. Screens built after
## this call pick it up (call show_hub()/show_map() to rebuild the current one).
func apply_theme(id: String) -> void:
	Palette.apply(id)
	theme = Palette.make_theme()
	# Overlays (deck, rules, inspector) live on the root window, so theme it too.
	get_tree().root.theme = theme
	var b: Dictionary = Palette.BACKDROP
	_bg_mat.set_shader_parameter("style", b["style"])
	_bg_mat.set_shader_parameter("top_color", b["top"])
	_bg_mat.set_shader_parameter("bottom_color", b["bottom"])
	_bg_mat.set_shader_parameter("glow_color", b["glow"])
	_bg_mat.set_shader_parameter("glow2_color", b["glow2"])


func _save() -> void:
	if persist:
		profile.save()


func _show(node: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = node
	add_child(node)


## Shifts the backdrop glow toward `col` (elites, shops...). No arg = theme default.
func _tint(col: Color = Color.TRANSPARENT) -> void:
	var g: Color = Palette.BACKDROP["glow"]
	_bg_mat.set_shader_parameter("glow_color", g if col == Color.TRANSPARENT else g.lerp(col, 0.6))


# --- hub / collection / packs ---------------------------------------------------

func show_hub() -> void:
	_tint()
	var hub := HubScreen.new().setup(db, profile)
	hub.theme_pressed.connect(func() -> void:
		profile.settings["theme"] = Themes.next_after(Palette.theme_id)
		_save()
		apply_theme(profile.settings["theme"])
		show_hub())
	hub.start_pressed.connect(_show_jobs)
	hub.collection_pressed.connect(func() -> void:
		var cs := CollectionScreen.new().setup(db, profile)
		cs.closed.connect(show_hub)
		_show(cs))
	hub.packs_pressed.connect(_show_pack)
	hub.rig_pressed.connect(func() -> void:
		var rs := RigScreen.new().setup(db, profile)
		rs.changed.connect(_save)
		rs.closed.connect(show_hub)
		_show(rs))
	_show(hub)


## Job board: every run is a job for one faction (see Jobs).
func _show_jobs(heat: int) -> void:
	var parts := UiKit.screen(16)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("Job board", 32, Palette.ENERGY))
	var n := profile.starter_picks(db)
	# Same board until the next run ends, so browsing doesn't reroll the targets.
	for offer in Jobs.offers(db, heat, GameRng.new(int(profile.stats.get("runs", 0)) * 7919 + heat)):
		var f: String = offer["client"]
		var j := Jobs.info(db, f)
		var against: Array = offer["targets"].map(func(x: String) -> String: return Lexicon.faction(x))
		var b := UiKit.button("%s  (%s)\n%s\nLoad %d+ %s programs. Against: %s (banned). Pays %s (you have %d)." % [
			j.get("client", f), Lexicon.faction(f), j.get("job", ""), Jobs.required(db, f, n), Lexicon.faction(f),
			" + ".join(against), Jobs.rep_name(db, f), profile.rep_of(f)],
			_show_picker.bind(heat, f, offer["targets"]), Vector2(620, 104), 15)
		b.add_theme_color_override("font_color", Palette.faction(f))
		v.add_child(b)
	v.add_child(UiKit.button("Back", show_hub, Vector2(200, 56)))
	_show(parts[0])


func _show_picker(heat: int, job: String = "", targets: Array = []) -> void:
	var cs := CollectionScreen.new().setup(db, profile, true, job, targets)
	cs.closed.connect(_show_jobs.bind(heat))
	cs.picks_confirmed.connect(func(picks: Array) -> void:
		profile.last_picks = picks
		_save()
		run = RunState.start(db, profile, picks, int(Time.get_unix_time_from_system()), heat, job, targets)
		show_map())
	_show(cs)


func _show_pack() -> void:
	if profile.packs_unopened <= 0:
		show_hub()
		return
	var pulled := profile.open_pack(db, GameRng.new(int(Time.get_ticks_usec())))
	_save()
	var parts := UiKit.screen(24)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("%s: tap cards to reveal" % Palette.w("pack"), 24))
	var grid := UiKit.flow(12)
	var views: Array = []
	for p in pulled:
		var inst := db.instance(p["id"])
		inst.foil = p["foil"]
		var cv := CardView.new().setup(inst)
		cv.face_down = true
		cv.pressed.connect(func(view: CardView) -> void:
			if view.face_down:
				view.flip_reveal())
		views.append(cv)
		grid.add_child(cv)
	v.add_child(grid)
	v.add_child(UiKit.button("Reveal all", func() -> void:
		for cv in views:
			if cv.face_down:
				cv.flip_reveal()))
	var left := profile.packs_unopened
	v.add_child(UiKit.button("Next pack (%d left)" % left if left > 0 else "Done", func() -> void:
		_show_pack() if profile.packs_unopened > 0 else show_hub()))
	_show(parts[0])


# --- map ------------------------------------------------------------------------

func show_map() -> void:
	_tint()
	var m := MapScreen.new().setup(run)
	m.node_chosen.connect(_enter_node)
	_show(m)


func _enter_node(id: int) -> void:
	var node := run.enter(id)
	match node.get("type", ""):
		"fight", "elite", "boss":
			_start_combat(node)
		"rest":
			_show_rest()
		"shop":
			_show_shop(run.make_shop())
		"event":
			_show_event(run.pick_event())
		"treasure":
			var tid := run.roll_talisman("", run.rng.fork("treasure:%d" % run.floor_num))
			run.add_talisman(tid)
			_show_message(Palette.w("treasure"), ["You pull %s from the cache." % db.talismans[tid]["name"] if tid != "" else "The cache is empty."], [tid] if tid != "" else [])


func _start_combat(node: Dictionary) -> void:
	_tint(Palette.NODE[node["type"]] if node["type"] != "fight" else Color.TRANSPARENT)
	_combat = run.start_combat(node["encounter"])
	_combat.start()
	var s := CombatScreen.new().setup(_combat, run)
	s.finished.connect(_on_combat_finished)
	_show(s)


func _on_combat_finished(_won: bool) -> void:
	var rewards := run.finish_combat(_combat)
	if run.over:
		_end_run()
		return
	var lines := ["+%d creds" % rewards["gold"]]
	if int(rewards.get("healed", 0)) > 0:
		lines.append("Nanites repair %d HP" % int(rewards["healed"]))
	if rewards.has("act_started"):
		lines.push_front("Layer %d breached. You reboot (now %d/%d HP)." % [rewards["act_started"], run.hp, run.max_hp])
		if run.double_crossed and int(rewards["act_started"]) == run.total_acts():
			lines.insert(1, "Double cross! %s sold you out. Their crew now hunts you, and their Core guards the last layer." % Jobs.info(db, run.job).get("client", Lexicon.faction(run.job)))
	var tals: Array = []
	if rewards["talisman"] != "":
		run.add_talisman(rewards["talisman"])
		lines.append("Recovered implant: %s" % db.talismans[rewards["talisman"]]["name"])
		tals.append(rewards["talisman"])
	_show_reward(lines, tals, rewards["cards"], rewards.get("perks", []))


func _show_reward(lines: Array, tals: Array, choices: Array, perks: Array = []) -> void:
	var next := show_map if perks.is_empty() else _show_perk_pick.bind(perks)
	var parts := UiKit.screen(20)
	var v: VBoxContainer = parts[1]
	v.add_child(RunHeader.new().setup(run))
	v.add_child(UiKit.label("Sentries crashed", 34, Palette.ENERGY))
	for l in lines:
		v.add_child(UiKit.label(l, 18))
	_add_talisman_row(v, tals)
	v.add_child(UiKit.label("Rip one program into your deck", 20, Palette.TEXT_DIM))
	var row := UiKit.flow(12)
	for id in choices:
		var cv := CardView.new().setup(db.instance(id))
		cv.pressed.connect(func(_v: CardView) -> void:
			run.add_card(id)
			next.call())
		row.add_child(cv)
	v.add_child(row)
	v.add_child(UiKit.button("Skip", next))
	_show(parts[0])


## After black sentries and Cores: load one of a few subroutines (run perks).
func _show_perk_pick(choices: Array) -> void:
	var parts := UiKit.screen(18)
	var v: VBoxContainer = parts[1]
	v.add_child(RunHeader.new().setup(run))
	v.add_child(UiKit.label("Load a subroutine", 32, Palette.ENERGY))
	v.add_child(UiKit.label("Subroutines run in the background for the rest of this run.", 16, Palette.TEXT_DIM, true))
	for pid in choices:
		var p: Dictionary = db.perks[pid]
		v.add_child(UiKit.button("%s\n%s" % [p["name"], Perks.describe(p)], func() -> void:
			var lines := run.add_perk(pid)
			if lines.size() > 1:
				_show_message(p["name"], lines)
			else:
				show_map(), Vector2(560, 80), 17))
	v.add_child(UiKit.button("Skip", show_map, Vector2(200, 56)))
	_show(parts[0])


# --- rest / shop / event ----------------------------------------------------------

func _show_rest() -> void:
	_tint(Palette.NODE["rest"])
	var parts := UiKit.screen(24)
	var v: VBoxContainer = parts[1]
	v.add_child(RunHeader.new().setup(run))
	v.add_child(UiKit.label(Palette.w("rest"), 30))
	if Palette.w("rest_text") != "":
		v.add_child(UiKit.label(Palette.w("rest_text"), 16, Palette.TEXT_DIM, true))
	v.add_child(UiKit.label("Pick one:", 16, Palette.TEXT_DIM))
	v.add_child(UiKit.button("Reboot (+%d HP)" % run.rest_heal_amount(), func() -> void:
		run.rest_heal()
		show_map(), Vector2(320, 70), 22))
	v.add_child(UiKit.button("Recompile a program\nRaise one card a level (v1, v2) for the rest of this run", func() -> void:
		add_child(DeckOverlay.new().setup("Choose a program to recompile", run.deck, "Cancel", func(i: int) -> void:
			if i >= 0 and run.upgrade_card(i):
				show_map(), true, true)), Vector2(440, 78), 19))
	var mods := run.mod_choices(int(db.balance.get("rest_mod_choices", 2)), run.rng.fork("tinker:%d" % run.floor_num))
	if not mods.is_empty():
		v.add_child(UiKit.label("or tinker: install one mod (one per card, lasts this run)", 16, Palette.TEXT_DIM))
		for mid in mods:
			v.add_child(_mod_button(mid, "", func() -> void:
				_pick_mod_target(mid, func(i: int) -> void:
					if run.install_mod(i, mid):
						show_map())))
	_show(parts[0])


## Button showing a mod's name, rules and fit. suffix e.g. a price.
func _mod_button(mid: String, suffix: String, on_press: Callable) -> Button:
	var m := db.mod(mid)
	var fit := CardMods.restriction_text(m)
	var b := UiKit.button("%s%s\n%s%s" % [m["name"], suffix, CardMods.describe(m), (" " + fit) if fit != "" else ""], on_press, Vector2(520, 70), 16)
	b.add_theme_color_override("font_color", Palette.rarity(str(m["rarity"])))
	return b


func _pick_mod_target(mid: String, on_pick: Callable) -> void:
	var m := db.mod(mid)
	add_child(DeckOverlay.new().setup("Install %s on which program?" % m["name"], run.deck, "Cancel", func(i: int) -> void:
		if i >= 0:
			on_pick.call(i), true, false, m))


func _show_shop(shop: Dictionary) -> void:
	_tint(Palette.NODE["shop"])
	var parts := UiKit.screen(16, BoxContainer.ALIGNMENT_BEGIN)
	var v: VBoxContainer = parts[1]
	v.add_child(RunHeader.new().setup(run))
	v.add_child(UiKit.label(Palette.w("shop"), 30))
	var cards := UiKit.flow(10)
	for item in shop["cards"]:
		var cv := CardView.new().setup(db.instance(item["id"]))
		cv.badge = "sold" if item.get("sold", false) else "%dc" % item["price"]
		cv.playable = not item.get("sold", false) and run.gold >= int(item["price"])
		cv.pressed.connect(func(_v: CardView) -> void:
			if run.buy(item, false):
				_show_shop(shop))
		cards.add_child(cv)
	v.add_child(cards)
	var trow := UiKit.hbox(20)
	for item in shop["talismans"]:
		var box := UiKit.vbox(4)
		var tv := TalismanView.new().setup(item["id"], db, true)
		tv.pressed.connect(func(id: String) -> void: UiKit.toast(self, TalismanView.text(db, id)))
		box.add_child(tv)
		var sold: bool = item.get("sold", false)
		var b := UiKit.button("sold" if sold else "Buy %dc" % item["price"], func() -> void:
			if run.buy(item, true):
				_show_shop(shop), Vector2(120, 44), 15)
		b.disabled = sold or run.gold < int(item["price"])
		box.add_child(b)
		trow.add_child(box)
	v.add_child(trow)
	for item in shop.get("mods", []):
		var sold: bool = item.get("sold", false)
		var mb := _mod_button(item["id"], "  ·  sold" if sold else "  ·  %dc" % item["price"], func() -> void:
			_pick_mod_target(item["id"], func(i: int) -> void:
				if run.buy_mod(item, i):
					_show_shop(shop)))
		mb.custom_minimum_size = Vector2(520, 60)
		mb.disabled = sold or run.gold < int(item["price"])
		v.add_child(mb)
	var rm := UiKit.button("Delete a program (%dc)" % run.remove_price(), func() -> void:
		add_child(DeckOverlay.new().setup("Choose a program to delete", run.deck, "Cancel", func(i: int) -> void:
			if i >= 0 and run.remove_card(i):
				shop["remove"] = run.remove_price()
				_show_shop(shop), true)), Vector2(300, 56))
	rm.disabled = run.gold < run.remove_price() or shop.get("removed", false)
	v.add_child(rm)
	v.add_child(UiKit.button("Jack out", show_map))
	_show(parts[0])


func _show_event(ev: Dictionary) -> void:
	_tint(Palette.NODE["event"])
	var parts := UiKit.screen(20)
	var v: VBoxContainer = parts[1]
	v.add_child(RunHeader.new().setup(run))
	var art := Control.new()
	art.custom_minimum_size = Vector2(160, 160)
	art.draw.connect(func() -> void:
		Sigil.draw(art, art.size / 2, 64.0, "event:" + str(ev["id"]), Palette.NODE["event"], Time.get_ticks_msec() / 1000.0)
		art.queue_redraw())
	v.add_child(art)
	v.add_child(UiKit.label(ev["title"], 30))
	v.add_child(UiKit.label(ev["text"], 17, Palette.TEXT_DIM, true))
	for ch in ev["choices"]:
		var desc: Array[String] = []
		for o in ch.get("outcomes", []):
			desc.append(RunOutcomes.describe(o))
		var label: String = ch["label"] + ("\n" + " ".join(desc) if not desc.is_empty() else "")
		var b := UiKit.button(label, func() -> void:
			var before := run.talismans.duplicate()
			var lines := run.choose(ch)
			var gained := run.talismans.filter(func(t: String) -> bool: return t not in before)
			_show_message(ev["title"], lines if not lines.is_empty() else ["Nothing happens."], gained), Vector2(520, 72), 16)
		b.disabled = not run.can_choose(ch)
		v.add_child(b)
	_show(parts[0])


func _show_message(title: String, lines: Array, tals: Array = []) -> void:
	var parts := UiKit.screen(20)
	var v: VBoxContainer = parts[1]
	v.add_child(RunHeader.new().setup(run))
	v.add_child(UiKit.label(title, 30))
	for l in lines:
		v.add_child(UiKit.label(str(l), 18, Palette.TEXT, true))
	_add_talisman_row(v, tals)
	v.add_child(UiKit.button("Continue", show_map))
	_show(parts[0])


func _add_talisman_row(v: VBoxContainer, tals: Array) -> void:
	for tid in tals:
		var tv := TalismanView.new().setup(tid, db, true)
		tv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(tv)
		v.add_child(UiKit.label(Talismans.describe(db.talismans[tid]), 15, Palette.TEXT_DIM, true))


# --- end of run -------------------------------------------------------------------

func _end_run() -> void:
	var lines := profile.finish_run(db, run)
	_save()
	var parts := UiKit.screen(16)
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("Root access. You own the Stack." if run.boss_won else "Flatlined on node %d" % run.floor_num, 34, Palette.ENERGY if run.boss_won else Palette.HP))
	v.add_child(UiKit.label("Fights won %d   Black sentries %d   Deck %d programs" % [run.combats_won, run.elites_won, run.deck.size()], 16, Palette.TEXT_DIM))
	for l in lines:
		v.add_child(UiKit.label(str(l), 17))
	v.add_child(UiKit.button(Palette.w("camp"), show_hub, Vector2(360, 64)))
	_show(parts[0])
