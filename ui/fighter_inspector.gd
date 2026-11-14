class_name FighterInspector
extends Control
## Press-and-hold (or tap, when no program is selected) a fighter: a panel with its HP,
## Firewall, next move, daemon rule and what each status on it does. The board stays
## visible behind a light dim. Tap anywhere to close.

var _view: FighterView


static func show_for(host: Node, view: FighterView) -> void:
	if view == null or view.fighter == null or not host.is_inside_tree():
		return
	for n in host.get_tree().root.get_children():
		if n is FighterInspector:
			n.queue_free()
	var fi := FighterInspector.new()
	fi._view = view
	host.get_tree().root.add_child(fi)


## [heading, body, color] rows for one fighter (also used by tests).
static func rows(view: FighterView) -> Array:
	var f: Fighter = view.fighter
	var out: Array = []
	if view.kind == "enemy" and not f.is_dead():
		out.append(["Next move", Intents.explain(f), Palette.ENEMY])
	if view.kind == "unit":
		out.append(["Daemon rule", DaemonRules.describe(f.rule), Palette.ENERGY])
		out.append(["Countdown", "Its HP is its countdown: it loses 1 at the start of each of your turns and 1 per hit taken. Purge moves take more. At 0 it closes and the rule ends.", Palette.TEXT_DIM])
	if f.ward > 0:
		out.append(["%s %d" % [Lexicon.term("ward"), f.ward], "Absorbs damage first.", Palette.ENERGY])
	for k in f.statuses:
		var def: Dictionary = Statuses.DEFS.get(k, {})
		var col: Color = Palette.ENEMY if def.get("debuff", false) else Palette.UPGRADED
		out.append(["%s %d" % [Lexicon.status(str(k)), f.statuses[k]], str(def.get("desc", "")), col])
	return out


func _ready() -> void:
	if get_child_count() > 0 or not is_instance_valid(_view):
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 90
	var bg := ColorRect.new()
	bg.color = Color(Palette.PANEL_BG, 0.55)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var width := minf(620.0, get_viewport_rect().size.x - 40.0)
	var v := UiKit.vbox(10, BoxContainer.ALIGNMENT_BEGIN)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f: Fighter = _view.fighter
	var name_text := Palette.w("hero") if _view.kind == "player" else f.name
	var col := Palette.ENEMY if _view.kind == "enemy" else Palette.TEXT
	var title := UiKit.label(name_text, 28, col)
	title.add_theme_font_override("font", Palette.display())
	v.add_child(title)
	v.add_child(UiKit.label("%d / %d HP" % [f.hp, f.max_hp], 18, Palette.HP))
	for r in rows(_view):
		v.add_child(_row(r[0], r[1], r[2], width - 28))
	if rows(_view).is_empty():
		v.add_child(UiKit.label("No statuses.", 16, Palette.TEXT_DIM))
	v.add_child(UiKit.label("Tap anywhere to close", 14, Palette.TEXT_DIM))
	var p := UiKit.panel(v, Color(Palette.PANEL_BG, 0.98))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size.x = width
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	sb.border_color = Color(col, 0.8)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(18)
	center.add_child(p)
	UiKit.tap_to_close(self)
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.12)


func _row(heading: String, body: String, col: Color, w: float) -> Control:
	var box := UiKit.vbox(2, BoxContainer.ALIGNMENT_BEGIN)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiKit.label(heading, 18, col)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(h)
	var b := UiKit.label(body, 15, Palette.TEXT, true)
	b.custom_minimum_size.x = w
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(b)
	return box
