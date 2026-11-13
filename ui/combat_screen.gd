class_name CombatScreen
extends Control
## Presentation for one Combat. It never changes rules: it calls play_card()/
## end_turn(), then replays the new entries of combat.events one by one as
## animations (input is blocked meanwhile), and only then rebuilds the board.
## Views show the HP/Ward carried by each event, so bars drop with each hit.

signal finished(won: bool)

## Seconds per step; tests and the screenshot tool can set this to 0.
var step_scale := 1.0
## Hand cards are drawn larger than in menus so their text is easy to read:
## as big as possible (up to HAND_ZOOM) while the hand still fits with little overlap.
const HAND_ZOOM := 1.35
const HAND_OVERLAP := 8.0
var combat: Combat
var run: RunState
var _selected := -1
var _event_cursor := 0
var _busy := false

var _floor_label: Label
var _pile_btns := {}
var _enemies_row: HBoxContainer
var _units_row: HBoxContainer
var _player_view: FighterView
var _energy: Control
var _hint: Label
var _hand_row: HBoxContainer
var _end_btn: Button
var _fx: Control
var _views := {}  # fighter id -> FighterView


func setup(c: Combat, r: RunState) -> CombatScreen:
	combat = c
	run = r
	return self


func is_busy() -> bool:
	return _busy


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 6
	col.offset_right = -6
	col.offset_top = 20
	col.offset_bottom = -20
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	_floor_label = UiKit.label("", 14, Palette.TEXT_DIM)
	col.add_child(_floor_label)
	var piles := UiKit.hbox(8)
	for p in ["draw", "discard", "exhaust", "deck"]:
		var b := UiKit.button("", _show_pile.bind(p), Vector2(118, 46), 15)
		_pile_btns[p] = b
		piles.add_child(b)
	piles.add_child(UiKit.button("?", func() -> void: Rules.open(self), Vector2(52, 46), 20))
	col.add_child(piles)
	if not combat.talismans.is_empty():
		var trow := UiKit.hbox(6)
		for t in combat.talismans:
			var tv := TalismanView.new().setup(t["id"], combat.db)
			tv.pressed.connect(func(id: String) -> void: UiKit.toast(self, TalismanView.text(combat.db, id)))
			trow.add_child(tv)
		col.add_child(trow)
	var top_gap := _spacer()
	top_gap.size_flags_stretch_ratio = 0.7
	col.add_child(top_gap)
	_enemies_row = _row(10)
	col.add_child(_enemies_row)
	col.add_child(_spacer())
	_units_row = _row(12)
	_units_row.custom_minimum_size.y = 130
	col.add_child(_units_row)
	_player_view = FighterView.new().setup(combat.player, combat, "player")
	_player_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_player_view.inspected.connect(_inspect_fighter)
	_player_view.pressed.connect(_on_ally_pressed)
	col.add_child(_player_view)

	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 18)
	_energy = Control.new()
	_energy.custom_minimum_size = Vector2(64, 64)
	_energy.draw.connect(_draw_energy)
	bar.add_child(_energy)
	_hint = UiKit.label("", 15, Palette.TEXT_DIM)
	_hint.custom_minimum_size.x = 250
	bar.add_child(_hint)
	_end_btn = Button.new()
	_end_btn.text = "End turn"
	_end_btn.custom_minimum_size = Vector2(150, 56)
	_end_btn.pressed.connect(_on_end_turn)
	bar.add_child(_end_btn)
	col.add_child(bar)

	_hand_row = _row(6)
	_hand_row.custom_minimum_size.y = CardView.SIZE.y * HAND_ZOOM + 20
	col.add_child(_hand_row)

	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)

	_event_cursor = combat.events.size()
	_rebuild()
	_deal_in(combat.hand.size())


func _rebuild() -> void:
	for n in _enemies_row.get_children() + _units_row.get_children() + _hand_row.get_children():
		n.get_parent().remove_child(n)
		n.queue_free()
	_player_view.shown_hp = -1
	_player_view.shown_ward = -1
	_player_view.frozen_intents = null
	_views = {combat.player.id: _player_view}
	for i in combat.enemies.size():
		var e: Fighter = combat.enemies[i]
		if e.is_dead():
			continue
		_add_enemy_view(e, i)
	for u in combat.units:
		_add_unit_view(u)
	var zoom := _hand_zoom(combat.hand.size())
	for i in combat.hand.size():
		var cv := CardView.new().setup(combat.hand[i], zoom)
		cv.playable = combat.can_play(i)
		cv.selected = i == _selected
		cv.pressed.connect(_on_card_pressed.bind(i))
		_hand_row.add_child(cv)
	# Overlap cards just enough that the whole hand fits on screen (every card stays tappable).
	var n := combat.hand.size()
	var avail := get_viewport_rect().size.x - 12
	var sep := 6 if n <= 1 else mini(6, int((avail - n * CardView.SIZE.x * zoom) / (n - 1)))
	_hand_row.add_theme_constant_override("separation", sep)
	_energy.queue_redraw()
	_floor_label.text = "Layer %d · Node %d   ·   %d creds   ·   Turn %d" % [run.act if run else 1, run.floor_num if run else 0, run.gold if run else 0, combat.turn]
	_pile_btns["draw"].text = "Draw %d" % combat.draw_pile.size()
	_pile_btns["discard"].text = "Discard %d" % combat.discard_pile.size()
	_pile_btns["exhaust"].text = "Wiped %d" % combat.exhaust_pile.size()
	_pile_btns["deck"].text = "Deck %d" % _all_cards().size()
	var inc := combat.incoming_damage()
	_player_view.targetable = _ally_mode()
	if _ally_mode():
		_hint.text = "Tap yourself or a daemon\n(tap the card again to cancel)"
	elif _selected >= 0:
		_hint.text = "Tap an enemy to target\n(tap the card again to cancel)"
	else:
		_hint.text = ("Incoming %d damage" % inc if inc > 0 else "No attacks incoming") + ("  ·  Firewall %d" % combat.player.ward if combat.player.ward > 0 else "")
	_end_btn.disabled = combat.phase != Combat.Phase.PLAYER or _busy


func _hand_zoom(n: int) -> float:
	var avail := get_viewport_rect().size.x - 12
	if n <= 0:
		return HAND_ZOOM
	return clampf((avail + (n - 1) * HAND_OVERLAP) / (n * CardView.SIZE.x), 0.85, HAND_ZOOM)


func _add_enemy_view(e: Fighter, i: int) -> FighterView:
	var v := FighterView.new().setup(e, combat, "enemy")
	v.targetable = _selected >= 0 and not _ally_mode()
	v.pressed.connect(_on_enemy_pressed.bind(i))
	v.inspected.connect(_inspect_fighter)
	_enemies_row.add_child(v)
	_views[e.id] = v
	return v


func _add_unit_view(u: Fighter) -> FighterView:
	var v := FighterView.new().setup(u, combat, "unit")
	v.targetable = _ally_mode()
	v.pressed.connect(_on_ally_pressed)
	v.inspected.connect(_inspect_fighter)
	_units_row.add_child(v)
	_views[u.id] = v
	return v


func _draw_energy() -> void:
	var c := _energy.size / 2
	var col := Palette.ENERGY if combat.energy > 0 else Color(Palette.ENERGY, 0.35)
	_energy.draw_circle(c, 30, Color(col, 0.25))
	_energy.draw_circle(c, 24, col)
	_energy.draw_string(Palette.display(), c + Vector2(-30, 8), "%d/%d" % [combat.energy, combat.max_energy], HORIZONTAL_ALIGNMENT_CENTER, 60, 20, Palette.CARD_BG)


func _all_cards() -> Array:
	if run != null:
		return run.deck
	return combat.draw_pile + combat.hand + combat.discard_pile + combat.exhaust_pile


func _show_pile(which: String) -> void:
	var cards: Array
	var title := ""
	match which:
		"draw":
			cards = combat.draw_pile.duplicate()
			# Sorted, so peeking never reveals the draw order.
			cards.sort_custom(func(a: CardInstance, b: CardInstance) -> bool: return a.display_name() < b.display_name())
			title = "Draw pile (%d) · shown in random order" % cards.size()
		"discard":
			cards = combat.discard_pile.duplicate()
			title = "Discard pile (%d)" % cards.size()
		"exhaust":
			cards = combat.exhaust_pile.duplicate()
			title = "Wiped this fight (%d)" % cards.size()
		_:
			cards = _all_cards()
			title = "Your deck (%d)" % cards.size()
	get_tree().root.add_child(DeckOverlay.new().setup(title, cards, "Close", func(_i: int) -> void: pass))


func _inspect_fighter(v: FighterView) -> void:
	if v == null:
		return
	UiKit.toast(self, v.describe(), 3.5)


# --- input ----------------------------------------------------------------------

func _on_card_pressed(_view: CardView, idx: int) -> void:
	if _busy or combat.phase != Combat.Phase.PLAYER:
		return
	if _selected == idx:
		_selected = -1
		_rebuild()
		return
	if not combat.can_play(idx):
		var c: CardInstance = combat.hand[idx]
		if c.has_keyword("unplayable"):
			UiKit.toast(self, "%s can't be played." % c.display_name())
		elif c.cost() > combat.energy:
			UiKit.toast(self, "Not enough RAM (%d needed)." % c.cost())
		return
	var card: CardInstance = combat.hand[idx]
	if (combat.needs_target(card) and combat.living(combat.enemies).size() > 1) or (combat.needs_ally(card) and not combat.units.is_empty()):
		_selected = idx
		_rebuild()
		return
	_act(func() -> void: combat.play_card(idx, -1), idx)


## True while the selected program wants you or one of your daemons as its target.
func _ally_mode() -> bool:
	return _selected >= 0 and _selected < combat.hand.size() and combat.needs_ally(combat.hand[_selected])


func _on_ally_pressed(view: FighterView) -> void:
	if _busy:
		return
	if not _ally_mode():
		_inspect_fighter(view)
		return
	var idx := _selected
	var ally_idx := ([combat.player] + combat.units).find(view.fighter)
	_selected = -1
	_act(func() -> void: combat.play_card(idx, ally_idx), idx)


func _on_enemy_pressed(view: FighterView, enemy_idx: int) -> void:
	if _busy:
		return
	if _selected < 0 or _ally_mode():
		_inspect_fighter(view)
		return
	var idx := _selected
	_selected = -1
	_act(func() -> void: combat.play_card(idx, enemy_idx), idx)


func _on_end_turn() -> void:
	if _busy:
		return
	_selected = -1
	_act(func() -> void: combat.end_turn())


func _act(f: Callable, hand_idx: int = -1) -> void:
	_busy = true
	_end_btn.disabled = true
	for v in _views.values():
		v.freeze()
		v.targetable = false
	var played: CardView = _hand_row.get_child(hand_idx) if hand_idx >= 0 and hand_idx < _hand_row.get_child_count() else null
	f.call()
	var draws := await _play_events(played)
	_busy = false
	_rebuild()
	_deal_in(draws)
	if combat.is_over():
		_end_btn.disabled = true
		await _wait(0.6)
		finished.emit(combat.phase == Combat.Phase.WON)


# --- playback -------------------------------------------------------------------

## Waits on a tween owned by this screen, so a freed screen simply never resumes.
func _wait(t: float) -> void:
	if t * step_scale <= 0.0:
		return
	var tw := create_tween()
	tw.tween_interval(t * step_scale)
	await tw.finished


## Replays new log entries. Returns how many cards were drawn (to deal them in).
## Add new event types here, not in Combat.
func _play_events(played: CardView) -> int:
	var draws := 0
	while _event_cursor < combat.events.size():
		var e: Dictionary = combat.events[_event_cursor]
		_event_cursor += 1
		var v: FighterView = _views.get(str(e.get("target", "")))
		if v != null and not is_instance_valid(v):
			v = null
		match e["t"]:
			"play":
				if played != null and is_instance_valid(played):
					_fly_card(played, _views.get(str(e["target"])))
					played = null
					await _wait(0.22)
			"damage":
				if v != null:
					v.shown_hp = int(e.get("hp", v.fighter.hp))
					if e.get("kind", "") != "lose_hp":
						v.shown_ward = int(e.get("ward", v.fighter.ward))
					v.flash = 1.0 if e["amount"] > 0 else 0.4
					_recoil(v, e["amount"])
				var txt := "-%d" % e["amount"] if e["amount"] > 0 else "Blocked"
				if e["amount"] > 0 and e["blocked"] > 0:
					txt += "  (%d blocked)" % e["blocked"]
				_float_text(v, txt, Palette.HP if e["amount"] > 0 else Palette.WARD)
				if v == _player_view and e["amount"] > 0:
					_shake(6.0)
				await _wait(0.16)
			"ward":
				if v != null:
					v.shown_ward = int(e.get("ward", v.fighter.ward))
				_float_text(v, "+%d Firewall" % e["amount"], Palette.WARD)
				await _wait(0.12)
			"heal":
				if v != null:
					v.shown_hp = int(e.get("hp", v.fighter.hp))
				_float_text(v, "+%d HP" % e["amount"], Palette.UPGRADED)
				await _wait(0.12)
			"status":
				var debuff: bool = Statuses.DEFS.get(e["status"], {}).get("debuff", false)
				_float_text(v, "%s %s%d" % [Lexicon.status(str(e["status"])), "+" if e["stacks"] >= 0 else "", e["stacks"]], Palette.ENEMY if debuff else Palette.UPGRADED)
				await _wait(0.1)
			"expire":
				var xv: FighterView = _views.get(str(e["target"]))
				if xv != null and is_instance_valid(xv):
					_float_text(xv, "Closed", Palette.TEXT_DIM)
					xv.create_tween().tween_property(xv, "modulate:a", 0.0, 0.3)
				await _wait(0.15)
			"rule":
				var rv: FighterView = _views.get(str(e["id"]))
				if rv != null and is_instance_valid(rv):
					rv.flash = 0.6
					rv.create_tween().tween_property(rv, "flash", 0.0, 0.3)
				await _wait(0.1)
			"uptime":
				var tv: FighterView = _views.get(str(e["target"]))
				if tv != null and is_instance_valid(tv):
					tv.shown_hp = int(e["hp"])
					tv.queue_redraw()
			"refresh":
				var fv: FighterView = _views.get(str(e["target"]))
				if fv != null and is_instance_valid(fv):
					_float_text(fv, "Refreshed", Palette.ENERGY)
				await _wait(0.12)
			"death":
				if v != null:
					var tw := v.create_tween()
					tw.tween_property(v, "modulate", Color(Palette.HP, 0.0), 0.35)
					v.flash = 1.0
				await _wait(0.3)
			"enemy_phase":
				for cv in _hand_row.get_children():
					cv.create_tween().tween_property(cv, "modulate:a", 0.0, 0.2)
				await _banner("Enemy turn", Palette.ENEMY)
			"enemy_move":
				var src: FighterView = _views.get(str(e["source"]))
				if src != null and is_instance_valid(src):
					if src.fighter.status("fortify") <= 0:
						src.shown_ward = 0
					src.frozen_intents = []
					_float_text(src, str(e["move"]), Palette.ENEMY, -40)
					var tw := src.create_tween()
					tw.tween_property(src, "offset", Vector2(0, 36), 0.12 * step_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					tw.tween_property(src, "offset", Vector2.ZERO, 0.2 * step_scale)
				await _wait(0.2)
			"turn_start":
				if combat.player.status("fortify") <= 0 and combat.rule_sum("keep_ward") <= 0:
					_player_view.shown_ward = 0
				if int(e["turn"]) > 1:
					await _banner("Your turn", Palette.ENERGY)
			"summon":
				var u: Fighter = _find(combat.units, str(e["target"]))
				if u != null:
					_pop_in(_add_unit_view(u))
				await _wait(0.2)
			"spawn":
				var en: Fighter = _find(combat.enemies, str(e["target"]))
				if en != null:
					var nv := _add_enemy_view(en, combat.enemies.find(en))
					nv.freeze()
					_pop_in(nv)
				await _wait(0.25)
			"talisman":
				_float_text(_player_view, str(combat.db.talismans.get(e["id"], combat.db.perks.get(e["id"], {})).get("name", "")), Palette.RARITY["rare"], -30)
				await _wait(0.18)
			"echo":
				_float_text(_player_view, "Echo!", Palette.faction("void"), -30)
			"reshuffle":
				_float_text(_player_view, "Discard shuffled into draw pile", Palette.TEXT_DIM, -60)
			"draw":
				draws += 1
			"rally":
				for uv in _units_row.get_children():
					_float_text(uv, "+%d HP" % int(e["amount"]), Palette.ENERGY)
				await _wait(0.12)
			"combat_end":
				await _banner("Victory" if e["won"] else "Defeated", Palette.ENERGY if e["won"] else Palette.HP)
	return draws


func _find(arr: Array, id: String) -> Fighter:
	for f in arr:
		if f.id == id:
			return f
	return null


func _fly_card(cv: CardView, target: Variant) -> void:
	var start := cv.global_position
	cv.get_parent().remove_child(cv)
	_fx.add_child(cv)
	cv.global_position = start
	cv.selected = false
	var dest := size / 2 - cv.size / 2 + Vector2(0, -80)
	if target is FighterView and is_instance_valid(target) and target != _player_view:
		dest = target.global_position - global_position + target.size / 2 - cv.size / 2
	var tw := cv.create_tween().set_parallel()
	tw.tween_property(cv, "position", dest, 0.25 * step_scale).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2(0.55, 0.55), 0.25 * step_scale)
	tw.chain().tween_property(cv, "modulate:a", 0.0, 0.15 * step_scale)
	tw.chain().tween_callback(cv.queue_free)


func _recoil(v: FighterView, amount: int) -> void:
	if amount <= 0:
		return
	var dir := -1.0 if v.kind == "enemy" else 1.0
	var tw := v.create_tween()
	tw.tween_property(v, "offset", Vector2(randf_range(-6, 6), dir * 10), 0.05 * step_scale)
	tw.tween_property(v, "offset", Vector2.ZERO, 0.12 * step_scale)


func _pop_in(v: Control) -> void:
	v.modulate.a = 0.0
	v.pivot_offset = v.custom_minimum_size / 2
	v.scale = Vector2(0.4, 0.4)
	var tw := v.create_tween().set_parallel()
	tw.tween_property(v, "modulate:a", 1.0, 0.2 * step_scale)
	tw.tween_property(v, "scale", Vector2.ONE, 0.25 * step_scale).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Newly drawn cards (the last `n` in hand) fade and grow in, one after another.
func _deal_in(n: int) -> void:
	var kids := _hand_row.get_children()
	var first := maxi(kids.size() - n, 0)
	for i in range(first, kids.size()):
		var cv: CardView = kids[i]
		cv.modulate.a = 0.0
		cv.scale = Vector2(0.7, 0.7)
		var tw := cv.create_tween()
		tw.tween_interval((i - first) * 0.06 * step_scale)
		tw.set_parallel()
		tw.tween_property(cv, "modulate:a", 1.0, 0.15 * step_scale)
		tw.tween_property(cv, "scale", Vector2.ONE, 0.2 * step_scale).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _banner(text: String, col: Color) -> void:
	var l := UiKit.label(text, 40, col)
	l.add_theme_font_override("font", Palette.display())
	l.add_theme_color_override("font_outline_color", Palette.CARD_BG)
	l.add_theme_constant_override("outline_size", 8)
	_fx.add_child(l)
	l.size = Vector2(size.x, 60)
	l.position = Vector2(0, size.y * 0.42)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.12 * step_scale)
	tw.tween_interval(0.3 * step_scale)
	tw.tween_property(l, "modulate:a", 0.0, 0.15 * step_scale)
	tw.tween_callback(l.queue_free)
	await _wait(0.45)


func _float_text(v: Control, text: String, col: Color, dy: float = 0.0) -> void:
	if v == null or not is_instance_valid(v):
		return
	var l := UiKit.label(text, 22, col)
	l.add_theme_font_override("font", Palette.display())
	l.add_theme_color_override("font_outline_color", Palette.CARD_BG)
	l.add_theme_constant_override("outline_size", 6)
	l.z_index = 10
	_fx.add_child(l)
	l.size = Vector2(v.size.x + 80, 30)
	l.global_position = v.global_position + Vector2(-40, v.size.y * 0.35 + dy)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.05)
	tw.parallel().tween_property(l, "position:y", l.position.y - 50, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)


func _shake(amount: float) -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(self, "position", Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.03)
	tw.tween_property(self, "position", Vector2.ZERO, 0.03)


func _row(sep: int) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", sep)
	return r


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s
