class_name SettingsScreen
extends Control
## Settings overlay: real toggles and sliders. Testing cheats stay hidden until the title is
## tapped five times (or they are already on), so players never stumble on them.

signal closed
## A setting changed: key is the settings key ("theme", "anim_speed", "cheats", audio keys).
signal changed(key: String)

var settings: Dictionary
var _title_taps := 0
var _cheat_row: Control


func setup(s: Dictionary) -> SettingsScreen:
	settings = s
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(Palette.PANEL_BG, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var parts := UiKit.screen(18)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	var title := UiKit.label("Settings", 34, Palette.ENERGY)
	title.mouse_filter = Control.MOUSE_FILTER_STOP
	title.gui_input.connect(_on_title_input)
	v.add_child(title)
	v.add_child(_section("Sound"))
	v.add_child(_toggle("Music", "music_muted", true))
	v.add_child(_slider("Music volume", "music_volume", 0.4))
	v.add_child(_toggle("Sound effects", "sfx_muted", true))
	v.add_child(_slider("Effects volume", "sfx_volume", 0.6))
	v.add_child(_section("Display"))
	v.add_child(_cycle("Look", func() -> String: return str(Themes.ALL[Palette.theme_id]["name"]), func() -> void:
		settings["theme"] = Themes.next_after(Palette.theme_id)
		changed.emit("theme")))
	v.add_child(_cycle("Animations", func() -> String:
		var i := clampi(int(settings.get("anim_speed", 0)), 0, ANIM_NAMES.size() - 1)
		return ANIM_NAMES[i], func() -> void:
		settings["anim_speed"] = (int(settings.get("anim_speed", 0)) + 1) % ANIM_NAMES.size()
		changed.emit("anim_speed")))
	_cheat_row = _toggle("Testing cheats", "cheats", false)
	_cheat_row.visible = bool(settings.get("cheats", false))
	v.add_child(_cheat_row)
	var done := UiKit.button("Done", func() -> void:
		queue_free()
		closed.emit(), Vector2(260, 60), 20)
	UiKit.primary(done)
	v.add_child(done)


const ANIM_NAMES := ["Normal", "Fast", "Very fast"]
const ROW_W := 520.0


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_title_taps += 1
		if _title_taps >= 5 and not _cheat_row.visible:
			_cheat_row.visible = true
			UiKit.toast(self, "Testing cheats unlocked.")


func _section(text: String) -> Label:
	var l := UiKit.label(text.to_upper(), 14, Palette.TEXT_DIM)
	l.custom_minimum_size.x = ROW_W
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return l


func _row(text: String) -> HBoxContainer:
	var row := UiKit.hbox(12)
	row.custom_minimum_size = Vector2(ROW_W, 56)
	var l := UiKit.label(text, 19, Palette.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	return row


## On/off switch. `inverted` = the saved key means "muted", so On shows when it is false.
func _toggle(text: String, key: String, inverted: bool) -> Control:
	var row := _row(text)
	var b := CheckButton.new()
	b.button_pressed = bool(settings.get(key, false)) != inverted
	b.custom_minimum_size = Vector2(80, 48)
	b.toggled.connect(func(on: bool) -> void:
		settings[key] = on != inverted
		GameAudio.play("tap")
		changed.emit(key))
	row.add_child(b)
	return row


## Volume 0..100%; plays a sample tick when you let go so you hear the level.
func _slider(text: String, key: String, fallback: float) -> Control:
	var row := _row(text)
	var pct := UiKit.label("", 16, Palette.ENERGY)
	pct.custom_minimum_size.x = 56
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(settings.get(key, fallback))
	s.custom_minimum_size = Vector2(220, 48)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pct.text = "%d%%" % roundi(s.value * 100)
	s.value_changed.connect(func(x: float) -> void:
		settings[key] = x
		pct.text = "%d%%" % roundi(x * 100))
	s.drag_ended.connect(func(_c: bool) -> void:
		changed.emit(key)
		GameAudio.play("ward" if key == "sfx_volume" else "tap"))
	row.add_child(s)
	row.add_child(pct)
	return row


## A value you step through by tapping (themes, animation speed).
func _cycle(text: String, value: Callable, next: Callable) -> Control:
	var row := _row(text)
	var b := UiKit.button(str(value.call()), func() -> void: pass, Vector2(200, 48), 17)
	b.pressed.connect(func() -> void:
		next.call()
		b.text = str(value.call()))
	row.add_child(b)
	return row
