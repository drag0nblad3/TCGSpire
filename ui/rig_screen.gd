class_name RigScreen
extends Control
## Permanent perks ("rig upgrades"), sold by the job factions for their rep.
## Each rank costs more rep and applies to every future run. Refunds are free.

signal closed
signal changed

var db: CardDB
var profile: Profile
var _list: VBoxContainer


func setup(db_in: CardDB, p: Profile) -> RigScreen:
	db = db_in
	profile = p
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var parts := UiKit.screen(12, BoxContainer.ALIGNMENT_BEGIN)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("Rig upgrades", 30, Palette.ENERGY))
	v.add_child(UiKit.label("Hardware that stays with you between runs. Each crew sells its own, for the rep you earn on its jobs. Refunds are free.", 14, Palette.TEXT_DIM, true))
	_list = UiKit.scroll(v)
	var bottom := UiKit.hbox(16)
	bottom.add_child(UiKit.button("Back", func() -> void: closed.emit(), Vector2(160, 60)))
	bottom.add_child(UiKit.button("Refund all", func() -> void:
		profile.reset_rig(db)
		changed.emit()
		_refresh(), Vector2(200, 60)))
	v.add_child(bottom)
	_refresh()


func _refresh() -> void:
	for n in _list.get_children():
		n.queue_free()
	for f in Jobs.board(db):
		var head := UiKit.label("%s  ·  %s  ·  %d %s" % [Lexicon.faction(f), Jobs.info(db, f).get("client", f), profile.rep_of(f), Jobs.rep_name(db, f)], 19, Palette.faction(f))
		head.add_theme_font_override("font", Palette.display())
		_list.add_child(head)
		for id in Perks.ids(db, "rig"):
			if db.perks[id].get("faction", "") == f:
				_list.add_child(_row(id))


func _row(id: String) -> Control:
	var p: Dictionary = db.perks[id]
	var rank := int(profile.rig.get(id, 0))
	var maxr := int(p.get("max_rank", 1))
	var row := UiKit.hbox(12)
	var info := UiKit.vbox(2, BoxContainer.ALIGNMENT_BEGIN)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UiKit.label("%s   ·   rank %d/%d" % [p["name"], rank, maxr], 17, Palette.UPGRADED if rank > 0 else Palette.TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	info.add_child(title)
	var d := UiKit.label(("Now: " + Perks.describe(p, rank)) if rank > 0 else ("Per rank: " + Perks.describe(p, 1)), 14, Palette.TEXT_DIM, true)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	d.custom_minimum_size.x = 0
	d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(d)
	row.add_child(info)
	var b := UiKit.button("Maxed" if rank >= maxr else "+1  (%d rep)" % profile.rig_cost(db, id), func() -> void:
		if profile.buy_rig(db, id):
			changed.emit()
			_refresh(), Vector2(160, 56), 15)
	b.disabled = not profile.can_buy_rig(db, id)
	row.add_child(b)
	return row
