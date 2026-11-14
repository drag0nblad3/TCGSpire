class_name CombatScreen
extends Control
## Presentation for one Combat. It never changes rules: it calls play_card()/
## end_turn(), then replays the new entries of combat.events one by one as
## animations (input is blocked meanwhile), and only then rebuilds the board.
## Views show the HP/Ward carried by each event, so bars drop with each hit.

signal finished(won: bool)
## After every program, end turn or cheat has finished animating (the tutorial coach listens).
signal acted

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
var _implant_views: Dictionary = {}
var _implant_tracker := ImplantTracker.new()
var _busy := false

var _floor_label: Label
var _pile_btns := {}
var _enemies_row: HBoxContainer
var _units_row: HBoxContainer
var _player_view: FighterView
var _energy: Control
var _hint: Label
var _action_label: Label
var _hand_row: HBoxContainer
var _end_btn: Button
var _fx: Control
var _views := {}  # fighter id -> FighterView
## Multi-hit playback: "source>target" of the last damage event and how many hits in a row it has taken.
var _combo_key := ""
var _combo_n := 0


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
	col.offset_left = 10
	col.offset_right = -10
	col.offset_top = 20
	col.offset_bottom = -20
	col.add_theme_constant_override("separation", 10)
	add_child(col)

	_floor_label = UiKit.label("", 14, Palette.TEXT_DIM)
	col.add_child(_floor_label)
	if not combat.talismans.is_empty():
		var trow := TalismanView.strip(col)
		for t in combat.talismans:
			var tv := TalismanView.new().setup(t["id"], combat.db)
			tv.tracker = _implant_tracker
			_implant_views[t["id"]] = tv
			tv.pressed.connect(func(_id: String) -> void: tv.inspect())
			trow.add_child(tv)
	var board := PanelContainer.new()
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color(Palette.PANEL_BG, 0.34)
	glass.border_color = Color(Palette.ENERGY, 0.35)
	glass.set_border_width_all(1)
	glass.set_corner_radius_all(maxi(Palette.RADIUS, 8))
	for side in [SIDE_LEFT, SIDE_RIGHT, SIDE_TOP, SIDE_BOTTOM]:
		glass.set_content_margin(side, 8)
	board.add_theme_stylebox_override("panel", glass)
	col.add_child(board)

	var field := UiKit.vbox(8)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(field)
	_action_label = UiKit.label("", 16, Palette.ENERGY)
	field.add_child(_action_label)
	field.add_child(_spacer())
	_enemies_row = _row(8)
	field.add_child(_enemies_row)
	field.add_child(_spacer())
	_units_row = _row(8)
	field.add_child(_units_row)
	_player_view = FighterView.new().setup(combat.player, combat, "player")
	_player_view.inspected.connect(_inspect_fighter)
	_player_view.pressed.connect(_on_ally_pressed)
	field.add_child(_player_view)

	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 18)
	_energy = Control.new()
	_energy.custom_minimum_size = Vector2(64, 64)
	_energy.tooltip_text = "RAM"
	_energy.draw.connect(_draw_energy)
	bar.add_child(_energy)
	_hint = UiKit.label("", 15, Palette.TEXT_DIM)
	_hint.custom_minimum_size.x = 250
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar.add_child(_hint)
	_end_btn = Button.new()
	_end_btn.text = "End turn"
	_end_btn.custom_minimum_size = Vector2(150, 56)
	_end_btn.pressed.connect(_on_end_turn)
	UiKit.primary(_end_btn)
	bar.add_child(_end_btn)
	col.add_child(bar)

	_hand_row = _row(6)
	_hand_row.custom_minimum_size.y = CardView.SIZE.y * HAND_ZOOM + 20
	col.add_child(_hand_row)

	# Pile viewers sit under the hand, in thumb reach.
	var piles := UiKit.hbox(8)
	piles.alignment = BoxContainer.ALIGNMENT_CENTER
	for p in ["draw", "discard", "exhaust", "deck"]:
		var b := UiKit.button("", _show_pile.bind(p), Vector2(118, 46), 15)
		b.pivot_offset = Vector2(118, 46) / 2
		_pile_btns[p] = b
		piles.add_child(b)
	piles.add_child(UiKit.button("?", func() -> void: Rules.open(self, "Turn flow"), Vector2(52, 46), 20))
	col.add_child(piles)

	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)
	_fx.draw.connect(_draw_target_line)

	for event in combat.events:
		_present_implant_event(event, false)
	for id in _implant_tracker.counts:
		if _implant_views.has(id) and step_scale > 0.0:
			_implant_views[id].activate()
	_event_cursor = combat.events.size()
	_rebuild()
	_deal_in(_all_drawn(combat.hand.size()))


func _process(_dt: float) -> void:
	if _fx != null:
		_fx.queue_redraw()


func _draw_target_line() -> void:
	for view: FighterView in _enemies_row.get_children():
		view.aimed = false
	if _busy or _selected < 0 or _selected >= _hand_row.get_child_count():
		return
	var destination: FighterView
	for view: FighterView in _enemies_row.get_children():
		if view.targetable and view.get_global_rect().has_point(get_global_mouse_position()):
			destination = view
			break
	if destination == null:
		return
	destination.aimed = true
	var card_view: CardView = _hand_row.get_child(_selected)
	var start := card_view.global_position + Vector2(card_view.size.x * 0.5, -18) - _fx.global_position
	var end := destination.global_position + Vector2(destination.size.x * 0.5, destination.size.y - 8) - _fx.global_position
	var points := PackedVector2Array()
	var bend := Vector2(start.x, end.y + (start.y - end.y) * 0.3)
	for i in 25:
		var t := float(i) / 24.0
		points.append(start.lerp(bend, t).lerp(bend.lerp(end, t), t))
	_fx.draw_polyline(points, Color(Palette.ENERGY, 0.16), 9.0, true)
	_fx.draw_polyline(points, Palette.ENERGY, 2.5, true)
	_fx.draw_circle(end, 5.0, Palette.ENERGY)


func _rebuild() -> void:
	var lingering := {}
	for id in _views:
		var old: FighterView = _views[id]
		if is_instance_valid(old):
			lingering[id] = [old.flash, old.firewall_flash, old.virus_flash]
	# Where each hand card sits now, so the rebuilt hand can glide from there (see _settle_hand).
	var hand_was := _hand_spots()
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
	for id in lingering:
		if _views.has(id):
			var view: FighterView = _views[id]
			view.flash = lingering[id][0]
			view.firewall_flash = lingering[id][1]
			view.virus_flash = lingering[id][2]
	var zoom := _hand_zoom(combat.hand.size())
	for i in combat.hand.size():
		var cv := CardView.new().setup(combat.hand[i], zoom)
		cv.playable = combat.can_play(i)
		cv.selected = i == _selected
		cv.pressed.connect(_on_card_pressed.bind(i))
		_hand_row.add_child(cv)
	# Overlap cards just enough that the whole hand fits on screen (every card stays tappable).
	var n := combat.hand.size()
	var avail := _layout_width() - 20
	var sep := 6 if n <= 1 else mini(6, int((avail - n * CardView.SIZE.x * zoom) / (n - 1)))
	_hand_row.add_theme_constant_override("separation", sep)
	if step_scale > 0.0 and not hand_was.is_empty():
		_hand_row.sort_children.connect(_settle_hand.bind(hand_was), CONNECT_ONE_SHOT)
	_energy.queue_redraw()
	_floor_label.text = ("Layer %d · Node %d   ·   %d creds   ·   Turn %d" % [run.act, run.floor_num, run.gold, combat.turn]) if run else "Practice fight   ·   Turn %d" % combat.turn
	if run and run.act_start_eased():
		_floor_label.text += "   ·   Soft entry: enemies %d%% HP, %d%% dmg" % [roundi(run.act_start_mult("enemy_hp_pct") * 100.0 - 100.0), roundi(run.act_start_mult("enemy_dmg_pct") * 100.0 - 100.0)]
	_pile_btns["draw"].text = "Draw %d" % combat.draw_pile.size()
	_pile_btns["discard"].text = "Discard %d" % combat.discard_pile.size()
	_pile_btns["exhaust"].text = "Wiped %d" % combat.exhaust_pile.size()
	_pile_btns["deck"].text = "Deck %d" % _all_cards().size()
	var inc := combat.incoming_damage()
	_player_view.targetable = _ally_mode()
	if _ally_mode():
		_hint.text = "%s\nTap yourself or a daemon" % combat.hand[_selected].display_name()
	elif _selected >= 0:
		_hint.text = "%s\nTap a highlighted enemy" % combat.hand[_selected].display_name()
	else:
		_hint.text = ("Incoming %d damage" % inc if inc > 0 else "No attacks incoming") + ("  ·  Firewall %d" % combat.player.ward if combat.player.ward > 0 else "")
	# Lethal: what's coming beats your HP and Firewall together. Red hint, red pulse on you
	# and on every enemy lining up an attack.
	var lethal := combat.phase == Combat.Phase.PLAYER and inc > 0 and inc >= combat.player.hp + combat.player.ward and combat.player.hp > 0
	_player_view.danger = lethal
	for ev in _enemies_row.get_children():
		if ev is FighterView:
			(ev as FighterView).danger = lethal and combat.intent_damage((ev as FighterView).fighter) > 0
	if lethal and _selected < 0:
		_hint.text = ("LETHAL: %d incoming vs %d HP + %d Firewall" % [inc, combat.player.hp, combat.player.ward]) if combat.player.ward > 0 else ("LETHAL: %d incoming vs %d HP" % [inc, combat.player.hp])
	_hint.add_theme_color_override("font_color", Palette.HP if lethal and _selected < 0 else Palette.TEXT_DIM)
	if combat.hand.any(func(card: CardInstance) -> bool: return card.effects().any(func(e: Dictionary) -> bool: return e.get("op") == "sequence")):
		var recent: Array = combat.played_types.slice(-2)
		_hint.text += "\nSequence: " + (" → ".join(recent.map(func(t: String) -> String: return Lexicon.type_name(t))) if not recent.is_empty() else "—")
	var ready: Array[String] = []
	for card in combat.hand:
		for effect in card.effects():
			if effect.get("op") == "handshake" and effect.get("card") in combat.played_ids and card.display_name() not in ready:
				ready.append(card.display_name())
	if not ready.is_empty():
		_hint.text += "\nHandshake: " + ", ".join(ready)
	_action_label.text = "Choose a target" if _selected >= 0 else ("Your turn" if combat.phase == Combat.Phase.PLAYER else "Enemy turn")
	_end_btn.disabled = combat.phase != Combat.Phase.PLAYER or _busy


func _layout_width() -> float:
	return get_viewport_rect().size.x if is_inside_tree() else float(ProjectSettings.get("display/window/size/viewport_width"))


func _hand_zoom(n: int) -> float:
	var avail := _layout_width() - 20
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
	# Reinforcements can take the row up to five enemies. Keep every tile on-screen.
	var enemy_count := _enemies_row.get_child_count()
	var width := minf(250.0, (_layout_width() - 38 - 8 * (enemy_count - 1)) / enemy_count)
	for tile in _enemies_row.get_children():
		var solo_boss: bool = not tile.boss_profile.is_empty() and enemy_count == 1
		tile.set_enemy_width(minf(432.0, _layout_width() - 38.0) if solo_boss else width)
	return v


## Reveal the opening boss portrait and report its accent to the shared backdrop.
func reveal_boss() -> Color:
	for portrait: FighterView in _enemies_row.get_children():
		if portrait.boss_profile.is_empty():
			continue
		portrait.modulate.a = 0.20
		portrait.offset.y = -22.0
		var reveal := portrait.create_tween().set_parallel()
		reveal.tween_property(portrait, "modulate:a", 1.0, 0.45)
		reveal.tween_property(portrait, "offset", Vector2.ZERO, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		return portrait.boss_accent
	return Color.TRANSPARENT


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
	var col := Palette.ENERGY if combat.energy > 0 else Color(Palette.ENERGY, 0.55)
	_energy.draw_circle(c, 30, Color(col, 0.26))
	_energy.draw_circle(c, 26, Palette.CARD_BG)
	_energy.draw_arc(c, 26, 0, TAU, 32, col, 2, true)
	_energy.draw_string(Palette.display(), c + Vector2(-30, 1), "%d/%d" % [combat.energy, combat.max_energy], HORIZONTAL_ALIGNMENT_CENTER, 60, 19, col)
	_energy.draw_string(Palette.font(), c + Vector2(-30, 16), "RAM", HORIZONTAL_ALIGNMENT_CENTER, 60, 12, Palette.TEXT)


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
		GameAudio.play("error")
		var c: CardInstance = combat.hand[idx]
		if c.has_keyword("unplayable"):
			UiKit.toast(self, "%s can't be played." % c.display_name())
		elif combat.was_played_this_turn(c):
			UiKit.toast(self, "%s can be played again next turn." % c.display_name())
		elif c.cost() > combat.energy:
			UiKit.toast(self, "Not enough RAM (%d needed)." % c.cost())
		return
	var card: CardInstance = combat.hand[idx]
	if (combat.needs_target(card) and combat.living(combat.enemies).size() > 1) or (combat.needs_ally(card) and not combat.units.is_empty()):
		GameAudio.play("select")
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


func cheat_full_heal() -> void:
	if _busy or combat.is_over():
		return
	Effects.resolve(combat, {"op": "heal", "amount": combat.player.max_hp, "to": "self"}, combat.player, combat.player)
	run.hp = combat.player.hp
	_event_cursor = combat.events.size()
	_rebuild()


func cheat_win() -> void:
	if _busy or combat.is_over():
		return
	_selected = -1
	_act(combat.cheat_win, -1, "Winning fight")


func _act(f: Callable, hand_idx: int = -1, action: String = "Enemy turn") -> void:
	_busy = true
	_action_label.text = "Running program" if hand_idx >= 0 else action
	_end_btn.disabled = true
	for v in _views.values():
		v.freeze()
		v.targetable = false
	var played: CardView = _hand_row.get_child(hand_idx) if hand_idx >= 0 and hand_idx < _hand_row.get_child_count() else null
	_hint.text = played.card.display_name() if played != null else ""
	f.call()
	_energy.queue_redraw()
	var draws := await _play_events(played)
	_busy = false
	_rebuild()
	_deal_in(draws)
	acted.emit()
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


## Replays new log entries. Returns one entry per card that reached the hand, in order:
## true if it came off the draw pile, false if it was made on the spot (to deal them in).
## Add new event types here, not in Combat.
func _play_events(played: CardView) -> Array:
	var draws := []
	while _event_cursor < combat.events.size():
		var e: Dictionary = combat.events[_event_cursor]
		_event_cursor += 1
		_present_implant_event(e, step_scale > 0.0)
		if step_scale > 0.0:
			GameAudio.play(GameAudio.event_cue(e))
		var v: FighterView = _views.get(str(e.get("target", "")))
		if v != null and not is_instance_valid(v):
			v = null
		if e["t"] not in ["damage", "death"]:
			_combo_key = ""
		match e["t"]:
			"play":
				if step_scale > 0.0 and played != null:
					GameAudio.play(played.card.def.faction)
				if played != null and is_instance_valid(played):
					_fly_card(played, _views.get(str(e["target"])))
					played = null
					await _wait(0.22)
			"damage":
				var damage := int(e["amount"])
				var blocked := int(e.get("blocked", 0))
				# Multi-hit attacks: each hit lands on its own beat, its number stacked above the last.
				var combo_key := "%s>%s" % [e.get("source", ""), e.get("target", "")]
				_combo_n = _combo_n + 1 if combo_key == _combo_key and e.get("kind", "") == "attack" else 0
				_combo_key = combo_key
				var next: Dictionary = combat.events[_event_cursor] if _event_cursor < combat.events.size() else {}
				var more_hits: bool = next.get("t", "") == "damage" and "%s>%s" % [next.get("source", ""), next.get("target", "")] == combo_key
				var lift := -26.0 * (_combo_n % 4)
				if v != null:
					# The event amount can include overkill. Report the HP actually lost.
					var remaining := int(e.get("hp", v.fighter.hp))
					damage = maxi(0, v.hp() - remaining)
					v.shown_hp = remaining
					if e.get("kind", "") != "lose_hp":
						v.shown_ward = int(e.get("ward", v.fighter.ward))
					v.flash = 1.0 if damage > 0 else 0.0
					v.firewall_flash = 1.0 if blocked > 0 else 0.0
					_recoil(v, damage)
				if blocked > 0:
					_float_text(v, "%d Firewall absorbed" % blocked, Palette.WARD, (-24 if damage > 0 else 0) + lift, true)
				if damage > 0:
					# Bigger hits get bigger numbers and a harder shake.
					_float_text(v, "−%d HP" % damage, Palette.HP, (10 if blocked > 0 else 0) + lift, true, clampi(20 + damage, 22, 40))
				if v == _player_view and damage > 0:
					_shake(clampf(4.0 + damage * 0.5, 5.0, 16.0))
				elif damage >= 12:
					_shake(clampf(damage * 0.25, 3.0, 9.0))
				await _wait(0.3 if more_hits or _combo_n > 0 else 0.16)
			"ward":
				if v != null:
					v.firewall_flash = 1.0
					v.shown_ward = int(e.get("ward", v.fighter.ward))
				_float_text(v, "+%d Firewall" % e["amount"], Palette.WARD)
				await _wait(0.12)
			"heal":
				if v != null:
					v.shown_hp = int(e.get("hp", v.fighter.hp))
				_float_text(v, "+%d HP" % e["amount"], Palette.UPGRADED)
				await _wait(0.12)
			"status":
				if v != null and e["status"] == "burn" and e["stacks"] > 0:
					v.virus_flash = 1.0
				var debuff: bool = Statuses.DEFS.get(e["status"], {}).get("debuff", false)
				_float_text(v, "%s %s%d" % [Lexicon.status(str(e["status"])), "+" if e["stacks"] >= 0 else "", e["stacks"]], Palette.ENEMY if debuff else Palette.UPGRADED)
				await _wait(0.1)
			"interrupt":
				if v != null:
					_float_text(v, "Interrupted", Palette.UPGRADED)
				await _wait(0.1)
			"strip":
				if v != null:
					_float_text(v, "Stripped", Palette.faction("void"))
				await _wait(0.1)
			"expire":
				var xv: FighterView = _views.get(str(e["target"]))
				if xv != null and is_instance_valid(xv):
					_float_text(xv, "Crashed" if e.get("crashed", false) else "Closed", Palette.TEXT_DIM)
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
					if v.kind == "unit":
						v.offline = true
						_float_text(v, "Daemon crashed", Palette.HP, 8, true)
					var tw := v.create_tween()
					tw.tween_property(v, "modulate", Color(Palette.HP, 0.0), 0.35)
				await _wait(0.3)
			"daemon_explosion":
				_float_text(v, "Detonate", Palette.HP)
				await _wait(0.12)
			"enemy_phase":
				# Unplayed programs leave the hand for their pile; Retain ones stay put.
				var k := 0
				_glide_after_change()
				for cv: CardView in _hand_row.get_children():
					if combat.hand.has(cv.card):
						continue
					_send_to_pile(cv, "exhaust" if combat.exhaust_pile.has(cv.card) else "discard", k * 0.04)
					k += 1
				await _banner("Enemy turn", Palette.ENEMY)
			"enemy_move":
				var src: FighterView = _views.get(str(e["source"]))
				if src != null and is_instance_valid(src):
					src.boss_action = 1.0
					if src.fighter.status("fortify") <= 0:
						src.shown_ward = 0
					src.frozen_intents = []
					_float_text(src, str(e["move"]), Palette.ENEMY, -40)
					var tw := src.create_tween()
					tw.tween_property(src, "offset", Vector2(0, 36), 0.12 * step_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					tw.tween_property(src, "offset", Vector2.ZERO, 0.2 * step_scale)
				await _wait(0.2)
			"turn_start":
				_player_view.shown_ward = int(e["ward"])
				if int(e["turn"]) > 1:
					await _banner("Your turn", Palette.ENERGY)
			"summon":
				var u: Fighter = _find(combat.units, str(e["target"]))
				if u == null:
					# A daemon can be summoned and destroyed before this action is replayed.
					u = Fighter.make(str(e["target"]), str(e["name"]), int(e["hp"]))
				var nv := _add_unit_view(u)
				nv.shown_hp = int(e["hp"])
				nv.shown_ward = 0
				_pop_in(nv)
				await _wait(0.2)
			"spawn":
				var en: Fighter = _find(combat.enemies, str(e["target"]))
				if en != null:
					var nv := _add_enemy_view(en, combat.enemies.find(en))
					nv.freeze()
					nv.shown_hp = en.max_hp
					nv.shown_ward = 0
					_pop_in(nv)
				await _wait(0.25)
			"talisman":
				_float_text(_player_view, str(combat.db.talismans.get(e["id"], combat.db.perks.get(e["id"], {})).get("name", "")), Palette.RARITY["rare"], -30)
				await _wait(0.18)
			"loop":
				_float_text(_player_view, "Loop: +%d now" % int(e.get("grown", e["loops"])), Palette.faction("void"), -30)
			"reshuffle":
				_float_text(_player_view, "Discard shuffled into draw pile", Palette.TEXT_DIM, -60)
			"draw":
				draws.append(not e.get("created", false))
			"rally":
				for uv in _units_row.get_children():
					_float_text(uv, "+%d HP" % int(e["amount"]), Palette.ENERGY)
				await _wait(0.12)
			"combat_end":
				await _banner("Victory" if e["won"] else "Defeated", Palette.ENERGY if e["won"] else Palette.HP)
	return draws


func _all_drawn(n: int) -> Array:
	var out := []
	out.resize(n)
	out.fill(true)
	return out


func _find(arr: Array, id: String) -> Fighter:
	for f in arr:
		if f.id == id:
			return f
	return null


func _fly_card(cv: CardView, target: Variant) -> void:
	_glide_after_change()
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
	# Then it drops into the pile it went to (Wiped for powers and Wipe programs), so it is clear where it went.
	var pile := "exhaust" if combat.exhaust_pile.has(cv.card) else ("discard" if combat.discard_pile.has(cv.card) else "")
	if pile == "":
		tw.chain().tween_property(cv, "modulate:a", 0.0, 0.15 * step_scale)
		tw.chain().tween_callback(cv.queue_free)
		return
	tw.chain().tween_interval(0.06 * step_scale)
	_to_pile(tw.chain(), cv, pile)


## Where each hand card sits now (centre and zoom), keyed by card, for _settle_hand.
func _hand_spots() -> Dictionary:
	var out := {}
	for cv: CardView in _hand_row.get_children():
		out[cv.card] = [cv.global_position + cv.size * 0.5, cv.zoom]
	return out


## Call just before cards leave the hand row: the cards left behind slide over to close the gap.
func _glide_after_change() -> void:
	if step_scale > 0.0:
		_hand_row.sort_children.connect(_settle_hand.bind(_hand_spots()), CONNECT_ONE_SHOT)


## Where a pile's button sits on screen (centre, global coordinates).
func _pile_point(which: String) -> Vector2:
	var b: Control = _pile_btns[which]
	return b.global_position + b.size * 0.5


## Pulls a hand card out of the row and slides it into a pile's button after `delay` seconds.
func _send_to_pile(cv: CardView, which: String, delay: float) -> void:
	var start := cv.global_position
	cv.get_parent().remove_child(cv)
	_fx.add_child(cv)
	cv.global_position = start
	cv.selected = false
	var tw := cv.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay * step_scale)
	_to_pile(tw, cv, which)


## Appends the shrink-and-slide into a pile's button to `tw`, then frees the card and nudges the button.
func _to_pile(tw: Tween, cv: CardView, which: String) -> void:
	var dest := _pile_point(which) - cv.size * 0.5
	var t := 0.2 * step_scale
	tw.set_parallel()
	tw.tween_property(cv, "global_position", dest, t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cv, "scale", Vector2(0.22, 0.22), t).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(cv, "modulate:a", 0.35, t).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void:
		_bump_pile(which)
		cv.queue_free())


## A small pop on a pile's button when a card lands in (or leaves) it.
func _bump_pile(which: String) -> void:
	var b: Control = _pile_btns[which]
	if step_scale <= 0.0 or not is_instance_valid(b):
		return
	b.scale = Vector2(1.1, 1.1)
	b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.14 * step_scale).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


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


## After a rebuild the hand's cards have new spots and maybe a new size. Each one glides from
## where (and as big as) it was into place, so the hand closes up instead of snapping.
func _settle_hand(was: Dictionary) -> void:
	for cv: CardView in _hand_row.get_children():
		if not was.has(cv.card):
			continue
		var from: Vector2 = was[cv.card][0]
		var ratio: float = float(was[cv.card][1]) / maxf(cv.zoom, 0.01)
		if from.distance_to(cv.global_position + cv.size * 0.5) < 1.0 and absf(ratio - 1.0) < 0.01:
			continue
		_glide(cv, from, ratio, 0.0, 0.22, false)


## Newly drawn cards (the last ones in hand, one entry each in `drawn`) slide out of the Draw
## pile's button into their spots, one after another. Cards made on the spot pop in where they sit.
func _deal_in(drawn: Array) -> void:
	if drawn.is_empty() or step_scale <= 0.0:
		return
	var kids := _hand_row.get_children()
	var first := maxi(kids.size() - drawn.size(), 0)
	for i in range(first, kids.size()):
		var cv: CardView = kids[i]
		var delay := (i - first) * 0.07
		if drawn[mini(i - first, drawn.size() - 1)]:
			_glide(cv, _pile_point("draw"), 0.22, delay, 0.24, true, "draw")
		else:
			cv.modulate.a = 0.0
			cv.scale = Vector2(0.7, 0.7)
			var tw := cv.create_tween()
			tw.tween_interval(delay * step_scale)
			tw.set_parallel()
			tw.tween_property(cv, "modulate:a", 1.0, 0.15 * step_scale)
			tw.tween_property(cv, "scale", Vector2.ONE, 0.2 * step_scale).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Moves a stand-in copy of a hand card from `from` (centre, global) at `from_scale` to wherever the
## real card sits, then shows the real one. Following the live spot keeps it right even if the row
## lays itself out again mid-move; the real card stays put and tappable throughout.
func _glide(cv: CardView, from: Vector2, from_scale: float, delay: float, dur: float, fade_in: bool, pile: String = "") -> void:
	var ghost := CardView.new().setup(cv.card, cv.zoom)
	ghost.playable = cv.playable
	ghost.selected = cv.selected
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(ghost)
	ghost.scale = Vector2(from_scale, from_scale)
	ghost.global_position = from - ghost.size * 0.5
	ghost.modulate.a = 0.0 if fade_in else 1.0
	cv.modulate.a = 0.0
	var follow := func(t: float) -> void:
		if not is_instance_valid(cv) or not cv.is_inside_tree():
			return
		var k := ease(t, 0.4)  # fast start, soft landing
		ghost.global_position = from.lerp(cv.global_position + cv.size * 0.5, k) - ghost.size * 0.5
		var sc := lerpf(from_scale, 1.0, k)
		ghost.scale = Vector2(sc, sc)
		if fade_in:
			ghost.modulate.a = minf(t * 3.0, 1.0)
	var tw := ghost.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay * step_scale)
	if pile != "":
		tw.tween_callback(_bump_pile.bind(pile))
	tw.tween_method(follow, 0.0, 1.0, dur * step_scale)
	tw.tween_callback(func() -> void:
		if is_instance_valid(cv):
			cv.modulate.a = 1.0
		ghost.queue_free())


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


func _float_text(v: Control, text: String, col: Color, dy: float = 0.0, chip: bool = false, font_size: int = 22) -> void:
	if v == null or not is_instance_valid(v):
		return
	var l := UiKit.label(text, font_size, col)
	l.add_theme_font_override("font", Palette.display())
	l.add_theme_color_override("font_outline_color", Palette.CARD_BG)
	l.add_theme_constant_override("outline_size", 6)
	if chip:
		var panel := StyleBoxFlat.new()
		panel.bg_color = Color(Palette.CARD_BG, 0.97)
		panel.border_color = col
		panel.set_border_width_all(1)
		panel.set_corner_radius_all(6)
		panel.content_margin_left = 8
		panel.content_margin_right = 8
		l.add_theme_stylebox_override("normal", panel)
	l.z_index = 10
	_fx.add_child(l)
	l.size = l.get_combined_minimum_size() if chip else Vector2(v.size.x + 80, 30)
	var left := clampf(v.global_position.x + (v.size.x - l.size.x) * 0.5, 4.0, maxf(4.0, size.x - l.size.x - 4.0))
	l.global_position = Vector2(left, v.global_position.y + v.size.y * 0.35 + dy)
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

func _present_implant_event(event: Dictionary, animate: bool = true) -> void:
	var had_daemons := not _implant_tracker.daemons.is_empty()
	_implant_tracker.consume(event)
	if animate and not had_daemons and not _implant_tracker.daemons.is_empty():
		for view in _implant_views.values():
			if view.definition.get("flags_while_daemon", false):
				view.activate()
	var id := str(event.get("id", ""))
	if animate and event.get("t", "") == "talisman" and _implant_views.has(id):
		_implant_views[id].activate()
	for view in _implant_views.values():
		view.queue_redraw()
