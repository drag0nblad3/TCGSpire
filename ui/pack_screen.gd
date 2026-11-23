class_name PackScreen
extends Control
## Opening one cache: the pulled cards face down in a 2 x 2 grid, tap (or Reveal all) to flip,
## quick scrap for copies beyond the deck limit. Main opens the pack and saves; this screen only shows it.

signal changed  # the profile changed (quick scrap): save it
signal next_pack(kind: String)
signal done

const PACK_ZOOM := 1.55

var db: CardDB
var profile: Profile
var kind := ""
var pulled: Array = []
## Screenshots: show the cards face up straight away.
var reveal_now := false


func setup(db_in: CardDB, p: Profile, kind_in: String, pulled_in: Array, reveal_now_in: bool = false) -> PackScreen:
	db = db_in
	profile = p
	kind = kind_in
	pulled = pulled_in
	reveal_now = reveal_now_in
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parts := UiKit.screen(14)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	var head := UiKit.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(PackArt.new().setup(db, kind, 1).as_icon(64))
	head.add_child(UiKit.label("%s: tap cards to reveal" % PackArt.title(db, kind), 24, PackArt.tint(kind)))
	v.add_child(head)
	var hot_text := "The last card is the hot slot: uncommon or better."
	if Packs.odds_at_least(db, kind, "rare") >= 0.999:
		hot_text = "The last card is the hot slot: rare or better. Every card has a %d%% glitch foil chance." % roundi(float(Packs.config(db, kind).get("foil_chance", 0)) * 100)
	if Packs.crew_of(kind) != "":
		hot_text = "Only %s programs. %s" % [Lexicon.faction(Packs.crew_of(kind)), hot_text]
	v.add_child(UiKit.label(hot_text, 14, Palette.TEXT_DIM, true))
	# Big cards in a 2 x 2 grid: the reveal is the moment, so it gets the screen.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var views: Array = []
	var summary := UiKit.label("", 16, Palette.UPGRADED, true)
	var revealed := [0]
	var scrap_btns: Array = []
	var on_reveal := func(view: CardView, p: Dictionary) -> void:
		view.badge = _pack_badge(p)
		view.pips = profile.copy_pips(db, p["id"])
		view.fresh = p.get("new", false)
		revealed[0] += 1
		if revealed[0] >= pulled.size():
			summary.text = _pack_summary(pulled)
		# Quick scrap: a copy beyond the two a deck can hold.
		var sb: Button = scrap_btns[views.find(view)]
		sb.visible = Profile.can_quick_scrap(db, profile, p["id"])
		sb.text = "Scrap +%d" % _quick_scrap_value(p)
	for p in pulled:
		var inst := db.instance(p["id"])
		inst.foil = p["foil"]
		var cv := CardView.new().setup(inst, PACK_ZOOM)
		cv.face_down = true
		cv.hot = p.get("hot", false)
		cv.pressed.connect(func(view: CardView) -> void:
			if view.face_down:
				_reveal_pack_card(view, p, on_reveal))
		views.append(cv)
		var cell := UiKit.vbox(6, BoxContainer.ALIGNMENT_BEGIN)
		cell.custom_minimum_size.y = CardView.SIZE.y * PACK_ZOOM + 46
		cell.add_child(cv)
		var sb := UiKit.button("", func() -> void: pass, Vector2(CardView.SIZE.x * PACK_ZOOM, 40), 15)
		sb.visible = false
		sb.tooltip_text = "Turn this copy into %s. You keep %d." % [Palette.w("dust").to_lower(), Profile.deck_limit(db)]
		sb.pressed.connect(func() -> void:
			var got := profile.quick_scrap(db, p["id"], p["foil"])
			if got <= 0:
				sb.visible = false
				return
			changed.emit()
			p["scrapped"] = true
			sb.text = "Scrapped +%d" % got
			sb.disabled = true
			cv.pips = profile.copy_pips(db, p["id"])
			cv.badge = _pack_badge(p)
			cv.modulate.a = 0.45
			# Other copies of the same program in this pack may have dropped to the limit.
			for k in pulled.size():
				if not scrap_btns[k].disabled and not views[k].face_down:
					scrap_btns[k].visible = Profile.can_quick_scrap(db, profile, pulled[k]["id"]))
		scrap_btns.append(sb)
		cell.add_child(sb)
		grid.add_child(cell)
	v.add_child(grid)
	v.add_child(summary)
	v.add_child(UiKit.label(PackArt.odds_line(db, profile, kind), 14, Palette.TEXT_DIM, true))
	var reveal_all := UiKit.button("Reveal all", func() -> void: pass)
	reveal_all.pressed.connect(func() -> void:
		reveal_all.disabled = true
		for k in views.size():
			if views[k].face_down:
				_reveal_pack_card(views[k], pulled[k], on_reveal, k * 0.18))
	v.add_child(UiKit.primary(reveal_all))
	var left := profile.pack_count(kind)
	if left > 0:
		v.add_child(UiKit.button("Next %s (%d left)" % [PackArt.title(db, kind), left], func() -> void: next_pack.emit(kind)))
	var others := profile.packs_unopened - left
	v.add_child(UiKit.button("Cache shelf (%d more)" % others if others > 0 else "Done", func() -> void: done.emit(), Vector2(220, 52)))
	if not reveal_now:
		_play_pack_opening(self, kind)
	else:
		for k in views.size():
			views[k].face_down = false
			on_reveal.call(views[k], pulled[k])


## Flips one pack card slowly. A rare or better gets a burst of light in its rarity color
## first, so the good pulls announce themselves before they turn over.
func _reveal_pack_card(view: CardView, p: Dictionary, on_reveal: Callable, delay: float = 0.0) -> void:
	if view.has_meta("revealing"):
		return
	view.set_meta("revealing", true)
	var rarity := db.instance(p["id"]).def.rarity
	var big := rarity in ["rare", "mythic"]
	var tw := view.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	if big:
		tw.tween_callback(func() -> void: _rarity_burst(view, Palette.rarity(rarity), rarity == "mythic"))
		tw.tween_interval(0.45)
	tw.tween_callback(func() -> void:
		GameAudio.play(rarity)
		view.flip_reveal(0.22)
		on_reveal.call(view, p))


## Light rays and an expanding ring behind a pack card (rare: rarity color; mythic: bigger).
func _rarity_burst(view: CardView, col: Color, mythic: bool) -> void:
	var fx := Control.new()
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.z_index = -1
	fx.show_behind_parent = true
	view.add_child(fx)
	fx.size = view.size
	var t := [0.0]
	var reach := (1.0 if mythic else 0.75) * view.size.y
	fx.draw.connect(func() -> void:
		var c := fx.size / 2
		var k: float = t[0]
		var fade := 1.0 - k
		for i in 12:
			var a := TAU * i / 12.0 + k * 0.6
			fx.draw_line(c, c + Vector2.from_angle(a) * reach * (0.4 + k * 0.6), Color(col, 0.55 * fade), 10.0 * fade + 2.0, true)
		fx.draw_arc(c, reach * 0.3 + reach * 0.7 * k, 0, TAU, 48, Color(col, 0.9 * fade), 6.0, true)
		fx.draw_circle(c, reach * 0.35 * (1.0 - k * 0.5), Color(col.lightened(0.5), 0.35 * fade)))
	var tw := fx.create_tween()
	tw.tween_method(func(x: float) -> void:
		t[0] = x
		fx.queue_redraw(), 0.0, 1.0, 1.1 if mythic else 0.8)
	tw.tween_callback(fx.queue_free)
	var pulse := view.create_tween()
	pulse.tween_property(view, "scale", Vector2(1.08, 1.08), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pulse.tween_property(view, "scale", Vector2.ONE, 0.2)


## A short encrypted-packet break, owned by the pack screen so navigation cancels it.
func _play_pack_opening(host: Control, kind: String = Packs.NORMAL) -> void:
	GameAudio.play("pack")
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = 10
	host.add_child(overlay)
	var progress := [0.0]
	overlay.draw.connect(func() -> void:
		var center := overlay.size * 0.5
		var packet := Rect2(center - Vector2(90, 120), Vector2(180, 240))
		overlay.draw_rect(Rect2(Vector2.ZERO, overlay.size), Color(Palette.PANEL_BG, 0.96))
		var split := maxf(0.0, progress[0] - 0.45) * 180.0
		PackArt.draw_packet(overlay, packet, kind, split, progress[0])
		var scan_y: float = packet.position.y + progress[0] * packet.size.y
		overlay.draw_line(Vector2(packet.position.x - 14 - split, scan_y), Vector2(packet.end.x + 14 + split, scan_y), PackArt.accent(kind), 3.0)
	)
	var tween := overlay.create_tween()
	tween.tween_method(func(value: float) -> void:
		progress[0] = value
		overlay.queue_redraw(), 0.0, 1.0, 0.5)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.15)
	tween.tween_callback(overlay.queue_free)


## Collector pill on a revealed pack card: an available firmware level or its level (NEW is a ribbon, copies are pips).
func _pack_badge(p: Dictionary) -> String:
	if p.get("unlocked", false):
		return "v%d available!" % (profile.firmware_level(p["id"]) + 1)
	return profile.copy_badge(db, p["id"])


## Scrap a pulled copy pays: its foil value if it was a foil.
func _quick_scrap_value(p: Dictionary) -> int:
	if p["foil"] and int(profile.collection.foils.get(p["id"], 0)) > 0:
		return Collection.foil_value(p["id"], db)
	var c := db.card(p["id"])
	return int(db.balance.get("dust", {}).get("disenchant", {}).get(c.rarity, 0)) if c != null else 0


## One line under a fully revealed pack: what it did for the collection.
func _pack_summary(pulled: Array) -> String:
	var bits: Array[String] = []
	var fresh := pulled.filter(func(p: Dictionary) -> bool: return p.get("new", false)).size()
	var unlocked := pulled.filter(func(p: Dictionary) -> bool: return p.get("unlocked", false)).size()
	if fresh > 0:
		bits.append("%d new program%s" % [fresh, "" if fresh == 1 else "s"])
	if unlocked > 0:
		bits.append("%d firmware upgrade%s available" % [unlocked, "" if unlocked == 1 else "s"])
	var foils := pulled.filter(func(p: Dictionary) -> bool: return p["foil"]).size()
	if foils > 0:
		bits.append("%d glitch foil%s" % [foils, "" if foils == 1 else "s"])
	bits.append("Library %d / %d" % CollectionScreen.library_progress(db, profile))
	var ready := profile.ready_to_flash(db).size()
	if ready > 0:
		bits.append("%d ready to flash" % ready)
	return "   ·   ".join(bits)
