extends Control
## App shell: owns the Profile and the current RunState and swaps screens.
## Prototype loop: fixed 3-fight route -> card reward after each win ->
## packs earned at the end -> open them -> new run. The map comes later.

const ROUTE := ["mites", "wisp_pack", "golem"]
const BACKDROP := preload("res://shaders/backdrop.gdshader")

var db: CardDB
var profile: Profile
var run: RunState
var _step := 0
var _screen: Control
var _combat: Combat


func _ready() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = BACKDROP
	bg.material = mat
	add_child(bg)
	db = CardDB.shared()
	profile = Profile.load_or_new(db)
	_new_run()


func _new_run() -> void:
	run = RunState.start(db, profile, RunState.default_picks(db, profile), int(Time.get_unix_time_from_system()))
	_step = 0
	_next_combat()


func _show(node: Control) -> void:
	if _screen != null:
		_screen.queue_free()
	_screen = node
	add_child(node)


func _next_combat() -> void:
	if _step >= ROUTE.size():
		_end_run(true)
		return
	_combat = run.start_combat(ROUTE[_step])
	_combat.start()
	var s := CombatScreen.new().setup(_combat, run)
	s.finished.connect(_on_combat_finished)
	_show(s)


func _on_combat_finished(won: bool) -> void:
	run.finish_combat(_combat)
	if not won:
		_end_run(false)
		return
	_step += 1
	var choices := run.reward_choices()
	_show(_card_picker("Choose a card for your deck", db.make_deck(choices), "Skip", func(i: int) -> void:
		if i >= 0:
			run.add_card(choices[i])
		_next_combat()))


func _end_run(won: bool) -> void:
	profile.stats["runs"] = int(profile.stats.get("runs", 0)) + 1
	if won:
		profile.stats["wins"] = int(profile.stats.get("wins", 0)) + 1
	# Packs are earned by playing: one per combat won.
	profile.packs_unopened += run.combats_won
	profile.save()
	_show_packs("Victory!" if won else "Defeated on floor %d" % run.floor_num)


func _show_packs(title: String) -> void:
	if profile.packs_unopened <= 0:
		_show(_card_picker(title + "\nNo packs to open.", [], "New run", func(_i: int) -> void: _new_run()))
		return
	var rng := GameRng.new(int(Time.get_ticks_usec()))
	var pulled := profile.open_pack(db, rng)
	profile.save()
	var cards: Array = []
	for p in pulled:
		var inst := db.instance(p["id"])
		inst.foil = p["foil"]
		cards.append(inst)
	var next_label := "Open next (%d)" % profile.packs_unopened if profile.packs_unopened > 0 else "New run"
	_show(_card_picker("%s\nPack opened! Collection: %d cards, %d dust" % [title, profile.collection.owned_ids().size(), profile.collection.dust],
		cards, next_label, func(_i: int) -> void:
			if profile.packs_unopened > 0:
				_show_packs(title)
			else:
				_new_run()))


## Generic screen: title, a row of cards, and one button. on_done(index) gets
## the tapped card index, or -1 for the button. With cards shown only as a
## display (packs), tapping a card does nothing.
func _card_picker(title: String, cards: Array, button_text: String, on_done: Callable) -> Control:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 28)
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 26)
	root.add_child(l)
	var grid := HFlowContainer.new()
	grid.alignment = FlowContainer.ALIGNMENT_CENTER
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	var is_choice := button_text == "Skip"
	for i in cards.size():
		var cv := CardView.new().setup(cards[i])
		if is_choice:
			cv.pressed.connect(func(_v: CardView) -> void: on_done.call(i))
		grid.add_child(cv)
	root.add_child(grid)
	var b := Button.new()
	b.text = button_text
	b.custom_minimum_size = Vector2(220, 64)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void: on_done.call(-1))
	root.add_child(b)
	return root
