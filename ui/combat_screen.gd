class_name CombatScreen
extends Control
## Presentation for one Combat. It never changes rules: it calls play_card()/
## end_turn(), then reads new entries from combat.events to animate them.

signal finished(won: bool)

var combat: Combat
var run: RunState
var _selected := -1
var _event_cursor := 0

var _top: Label
var _enemies_row: HBoxContainer
var _units_row: HBoxContainer
var _player_view: FighterView
var _energy: Label
var _hint: Label
var _hand_row: HBoxContainer
var _end_btn: Button
var _fx: Control
var _views := {}  # fighter id -> FighterView


func setup(c: Combat, r: RunState) -> CombatScreen:
	combat = c
	run = r
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 16
	col.offset_right = -16
	col.offset_top = 24
	col.offset_bottom = -24
	col.add_theme_constant_override("separation", 12)
	add_child(col)

	_top = _label(16, Palette.TEXT_DIM)
	col.add_child(_top)
	var top_gap := _spacer()
	top_gap.size_flags_stretch_ratio = 0.5
	col.add_child(top_gap)
	_enemies_row = _row(16)
	col.add_child(_enemies_row)
	col.add_child(_spacer())
	_units_row = _row(12)
	_units_row.custom_minimum_size.y = 120
	col.add_child(_units_row)
	_player_view = FighterView.new().setup(combat.player, combat, "player")
	_player_view.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_views[combat.player.id] = _player_view
	col.add_child(_player_view)

	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 24)
	_energy = _label(22, Palette.ENERGY)
	bar.add_child(_energy)
	_hint = _label(14, Palette.TEXT_DIM)
	_hint.custom_minimum_size.x = 260
	bar.add_child(_hint)
	_end_btn = Button.new()
	_end_btn.text = "End turn"
	_end_btn.custom_minimum_size = Vector2(150, 56)
	_end_btn.pressed.connect(_on_end_turn)
	bar.add_child(_end_btn)
	col.add_child(bar)

	_hand_row = _row(-14)
	_hand_row.custom_minimum_size.y = CardView.SIZE.y + 20
	col.add_child(_hand_row)

	_fx = Control.new()
	_fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)

	_event_cursor = combat.events.size()
	_rebuild()


func _rebuild() -> void:
	for n in _enemies_row.get_children() + _units_row.get_children() + _hand_row.get_children():
		n.queue_free()
	_views = {combat.player.id: _player_view}
	for i in combat.enemies.size():
		var e: Fighter = combat.enemies[i]
		if e.is_dead():
			continue
		var v := FighterView.new().setup(e, combat, "enemy")
		v.targetable = _selected >= 0
		v.pressed.connect(_on_enemy_pressed.bind(i))
		_enemies_row.add_child(v)
		_views[e.id] = v
	for u in combat.units:
		var v := FighterView.new().setup(u, combat, "unit")
		_units_row.add_child(v)
		_views[u.id] = v
	for i in combat.hand.size():
		var cv := CardView.new().setup(combat.hand[i])
		cv.playable = combat.can_play(i)
		cv.selected = i == _selected
		cv.pressed.connect(_on_card_pressed.bind(i))
		_hand_row.add_child(cv)
	_hand_row.add_theme_constant_override("separation", -14 if combat.hand.size() > 5 else 6)
	_energy.text = "Energy %d/%d" % [combat.energy, combat.max_energy]
	_top.text = "Floor %d   Draw %d   Discard %d   Exhaust %d" % [run.floor_num if run else 0, combat.draw_pile.size(), combat.discard_pile.size(), combat.exhaust_pile.size()]
	_hint.text = "Choose a target" if _selected >= 0 else ("Incoming: %d" % combat.incoming_damage())
	_end_btn.disabled = combat.phase != Combat.Phase.PLAYER


func _on_card_pressed(_view: CardView, idx: int) -> void:
	if _selected == idx:
		_selected = -1
		_rebuild()
		return
	if not combat.can_play(idx):
		return
	var card: CardInstance = combat.hand[idx]
	if combat.needs_target(card) and combat.living(combat.enemies).size() > 1:
		_selected = idx
		_rebuild()
		return
	_act(func() -> void: combat.play_card(idx, -1))


func _on_enemy_pressed(_view: FighterView, enemy_idx: int) -> void:
	if _selected < 0:
		return
	var idx := _selected
	_selected = -1
	_act(func() -> void: combat.play_card(idx, enemy_idx))


func _on_end_turn() -> void:
	_selected = -1
	_act(func() -> void: combat.end_turn())


func _act(f: Callable) -> void:
	f.call()
	_play_events()
	_rebuild()
	if combat.is_over():
		_end_btn.disabled = true
		await get_tree().create_timer(0.9).timeout
		finished.emit(combat.phase == Combat.Phase.WON)


## Turns new log entries into juice. Add new event types here, not in Combat.
func _play_events() -> void:
	var delay := 0.0
	while _event_cursor < combat.events.size():
		var e: Dictionary = combat.events[_event_cursor]
		_event_cursor += 1
		match e["t"]:
			"damage":
				_float_text(e["target"], "-%d" % e["amount"] if e["amount"] > 0 else "blocked", Palette.HP, delay)
				delay += 0.08
			"ward":
				_float_text(e["target"], "+%d ward" % e["amount"], Palette.WARD, delay)
			"heal":
				_float_text(e["target"], "+%d" % e["amount"], Palette.UPGRADED, delay)
			"status":
				_float_text(e["target"], "%s %d" % [str(e["status"]).capitalize(), e["stacks"]], Palette.ENERGY, delay)
	if delay > 0.0:
		_shake(4.0)


func _float_text(target_id: String, text: String, col: Color, delay: float) -> void:
	var v: Control = _views.get(target_id)
	if v == null or not is_instance_valid(v):
		return
	var l := _label(22, col)
	l.text = text
	l.z_index = 10
	_fx.add_child(l)
	l.global_position = v.global_position + Vector2(v.size.x / 2 - 30, 20)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(l, "modulate:a", 1.0, 0.05)
	tw.parallel().tween_property(l, "position:y", l.position.y - 50, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)


func _shake(amount: float) -> void:
	var tw := create_tween()
	for i in 4:
		tw.tween_property(self, "position", Vector2(randf_range(-amount, amount), randf_range(-amount, amount)), 0.03)
	tw.tween_property(self, "position", Vector2.ZERO, 0.03)


func _label(font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _row(sep: int) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.alignment = BoxContainer.ALIGNMENT_CENTER
	r.add_theme_constant_override("separation", sep)
	return r


func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s
