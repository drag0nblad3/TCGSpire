class_name EnemyPortraits
extends RefCounted
## Artwork atlases for non-boss enemies. Each cell is a 220 × 170 design canvas.

const CELL := Vector2(220, 170)
const ATLASES := {
	"ember": preload("res://assets/combat/regular/ember.svg"),
	"tide": preload("res://assets/combat/regular/tide.svg"),
	"bloom": preload("res://assets/combat/regular/bloom.svg"),
	"void": preload("res://assets/combat/regular/void.svg"),
	"chrome": preload("res://assets/combat/regular/chrome.svg"),
	"noise": preload("res://assets/combat/regular/noise.svg"),
	"neutral": preload("res://assets/combat/regular/neutral.svg"),
}
const ROSTER := {
	"burner_tagger": ["ember", 0, "vents", false],
	"kiln_enforcer": ["ember", 1, "vents", false],
	"furnace_hulk": ["ember", 2, "vents", false],
	"pyre_warlord": ["ember", 3, "reactor", false],
	"ash_runner": ["ember", 4, "vents", false],
	"slag_titan": ["ember", 5, "reactor", false],
	"ember_marshal": ["ember", 6, "vents", false],
	"flux_courier": ["tide", 0, "coolant", false],
	"broker_guard": ["tide", 1, "coolant", false],
	"data_leviathan": ["tide", 2, "coolant", false],
	"ledger_warden": ["tide", 3, "coolant", false],
	"margin_agent": ["tide", 4, "coolant", false],
	"deep_ledger": ["tide", 5, "coolant", false],
	"riptide_auditor": ["tide", 6, "coolant", false],
	"vat_grub": ["bloom", 0, "bio", false],
	"clinic_orderly": ["bloom", 1, "bio", false],
	"flesh_golem": ["bloom", 2, "bio", false],
	"gene_surgeon": ["bloom", 3, "bio", false],
	"spore_nurse": ["bloom", 4, "bio", false],
	"chimera": ["bloom", 5, "bio", false],
	"head_geneticist": ["bloom", 6, "bio", false],
	"null_flicker": ["void", 0, "fracture", false],
	"cell_eraser": ["void", 1, "fracture", false],
	"void_maw": ["void", 2, "fracture", false],
	"zero_prophet": ["void", 3, "fracture", false],
	"blank": ["void", 4, "fracture", false],
	"event_horizon": ["void", 5, "fracture", false],
	"null_cardinal": ["void", 6, "fracture", false],
	"sentry_drone": ["chrome", 0, "chrome", false],
	"plated_guard": ["chrome", 1, "chrome", false],
	"riot_mech": ["chrome", 2, "chrome", false],
	"hive_controller": ["chrome", 3, "chrome", false],
	"strike_drone": ["chrome", 4, "chrome", false],
	"siege_walker": ["chrome", 5, "chrome", false],
	"swarm_admiral": ["chrome", 6, "chrome", false],
	"pirate_jammer": ["noise", 0, "signal", true],
	"shock_jock": ["noise", 1, "signal", true],
	"signal_tower": ["noise", 2, "signal", false],
	"the_anchor": ["noise", 3, "signal", false],
	"feedback_loop": ["noise", 4, "signal", false],
	"speaker_stack": ["noise", 5, "signal", false],
	"the_headliner": ["noise", 6, "signal", true],
	"cinder_mite": ["neutral", 0, "core", false],
	"hollow_wisp": ["neutral", 1, "core", false],
	"ember_imp": ["neutral", 2, "core", false],
	"bramble_crawler": ["neutral", 3, "core", false],
	"tide_lurker": ["neutral", 4, "core", false],
	"spore_pod": ["neutral", 5, "core", false],
	"shard_golem": ["neutral", 6, "core", false],
	"hex_knight": ["neutral", 7, "core", false],
	"brood_mother": ["neutral", 8, "core", false],
	"glass_wraith": ["neutral", 9, "fracture", false],
	"black_ice": ["neutral", 10, "core", false],
	"worm_larva": ["neutral", 11, "core", false],
	"orphan_daemon": ["neutral", 12, "chrome", false],
	"deadman_switch": ["neutral", 13, "core", false],
	"archivist": ["neutral", 14, "core", false],
	"kill_switch": ["neutral", 15, "core", false],
	"worm_queen": ["neutral", 16, "core", false],
	"storm_harpy": ["neutral", 17, "core", false],
	"rust_sentinel": ["neutral", 18, "core", false],
	"void_tick": ["neutral", 19, "fracture", false],
	"ash_shaman": ["neutral", 20, "core", false],
	"mire_beast": ["neutral", 21, "core", false],
	"reaver": ["neutral", 22, "core", false],
	"chorus_of_echoes": ["neutral", 23, "signal", false],
	"warden_construct": ["neutral", 24, "chrome", false],
}

# Offsets are intentionally discontinuous. The middle band jumps on its own beats.
const GLITCH_OUTER := [
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(14, -7), Vector2(-17, 12), Vector2(5, -13),
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(-19, 10),
	Vector2(11, -16), Vector2(-5, 4), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
	Vector2(16, 6), Vector2(-12, -11), Vector2(20, 9), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
]
const GLITCH_MIDDLE := [0, -13, 17, 0, 0, 0, 0, 0, 14, -10, 0, 0, 0, 0, 0, 16, -12, 0, 0, 0, 0, 0, 19, -9]


# One shoulder silhouette and its illuminated inset, mirrored around the atlas center.
# Burner stacks, Flux fins, Wetware growth, Null fragments, Chrome rails, Static antennae.
const ELITE_GEAR := {
	"ember": [[Vector2(23, 102), Vector2(19, 48), Vector2(12, 25), Vector2(34, 20), Vector2(50, 39), Vector2(57, 101)],
		[Vector2(23, 31), Vector2(34, 29), Vector2(42, 40), Vector2(43, 57), Vector2(29, 56)]],
	"tide": [[Vector2(30, 108), Vector2(9, 61), Vector2(9, 30), Vector2(26, 47), Vector2(37, 34), Vector2(51, 62), Vector2(69, 101)],
		[Vector2(16, 47), Vector2(26, 59), Vector2(36, 49), Vector2(44, 67), Vector2(31, 77)]],
	"bloom": [[Vector2(28, 107), Vector2(12, 77), Vector2(19, 56), Vector2(16, 35), Vector2(37, 41), Vector2(52, 20), Vector2(57, 49), Vector2(70, 61), Vector2(64, 103)],
		[Vector2(29, 58), Vector2(48, 35), Vector2(49, 63), Vector2(59, 74), Vector2(38, 80)]],
	"void": [[Vector2(12, 37), Vector2(39, 18), Vector2(53, 43), Vector2(27, 57), Vector2(41, 65), Vector2(60, 51), Vector2(69, 96), Vector2(32, 104), Vector2(19, 77), Vector2(24, 67)],
		[Vector2(19, 38), Vector2(37, 26), Vector2(44, 40), Vector2(26, 49)]],
	"chrome": [[Vector2(15, 103), Vector2(15, 46), Vector2(29, 32), Vector2(53, 32), Vector2(65, 45), Vector2(65, 103), Vector2(48, 112), Vector2(27, 111)],
		[Vector2(22, 51), Vector2(32, 40), Vector2(50, 40), Vector2(57, 48), Vector2(49, 59), Vector2(30, 59)]],
	"noise": [[Vector2(25, 104), Vector2(21, 62), Vector2(10, 23), Vector2(20, 16), Vector2(38, 46), Vector2(49, 38), Vector2(55, 44), Vector2(42, 66), Vector2(61, 104)],
		[Vector2(17, 24), Vector2(21, 22), Vector2(35, 47), Vector2(31, 53)]],
	"neutral": [[Vector2(22, 104), Vector2(14, 61), Vector2(21, 32), Vector2(42, 42), Vector2(55, 30), Vector2(63, 58), Vector2(61, 102)],
		[Vector2(21, 48), Vector2(42, 56), Vector2(53, 45), Vector2(56, 52), Vector2(44, 65), Vector2(19, 56)]],
}


# Draw the lower mounts in front of the portrait so the attachments wrap into the armor.
const ELITE_MOUNTS := {
	"ember": [[Vector2(22, 76), Vector2(55, 75), Vector2(62, 98), Vector2(92, 116), Vector2(88, 132), Vector2(61, 123), Vector2(33, 108)],
		[Vector2(33, 85), Vector2(45, 84), Vector2(50, 100), Vector2(77, 119), Vector2(75, 122), Vector2(42, 107)]],
	"tide": [[Vector2(20, 76), Vector2(49, 72), Vector2(69, 96), Vector2(92, 113), Vector2(92, 126), Vector2(65, 120), Vector2(40, 104)],
		[Vector2(32, 85), Vector2(44, 81), Vector2(61, 102), Vector2(83, 116), Vector2(81, 120), Vector2(58, 109)]],
	"bloom": [[Vector2(17, 74), Vector2(62, 72), Vector2(60, 91), Vector2(81, 103), Vector2(93, 121), Vector2(85, 129), Vector2(60, 114), Vector2(42, 115), Vector2(26, 99)],
		[Vector2(28, 82), Vector2(50, 81), Vector2(48, 94), Vector2(66, 104), Vector2(83, 121), Vector2(79, 122), Vector2(56, 108), Vector2(38, 106)]],
	"void": [[Vector2(20, 76), Vector2(48, 69), Vector2(65, 81), Vector2(63, 94), Vector2(83, 107), Vector2(92, 128), Vector2(67, 123), Vector2(56, 111), Vector2(38, 109)],
		[Vector2(29, 81), Vector2(47, 76), Vector2(58, 86), Vector2(48, 99), Vector2(40, 99)]],
	"chrome": [[Vector2(15, 78), Vector2(65, 77), Vector2(66, 96), Vector2(91, 108), Vector2(91, 125), Vector2(62, 125), Vector2(48, 112), Vector2(27, 111), Vector2(15, 103)],
		[Vector2(23, 86), Vector2(57, 85), Vector2(57, 91), Vector2(23, 92)]],
	"noise": [[Vector2(22, 65), Vector2(43, 65), Vector2(54, 89), Vector2(73, 98), Vector2(94, 120), Vector2(85, 129), Vector2(62, 114), Vector2(37, 107)],
		[Vector2(29, 73), Vector2(37, 72), Vector2(47, 96), Vector2(66, 104), Vector2(80, 120), Vector2(74, 119), Vector2(42, 104)]],
	"neutral": [[Vector2(18, 78), Vector2(62, 77), Vector2(62, 95), Vector2(92, 116), Vector2(85, 130), Vector2(59, 121), Vector2(34, 105)],
		[Vector2(30, 87), Vector2(50, 85), Vector2(54, 99), Vector2(79, 118), Vector2(75, 121), Vector2(45, 102)]],
}


static func _draw_elite_gear(view: CanvasItem, origin: Vector2, scale: float, layers: Array, accent: Color) -> void:
	for side in [1, -1]:
		for i in layers.size():
			var points := PackedVector2Array()
			for point: Vector2 in layers[i]:
				points.append(origin + Vector2(CELL.x * 0.5 + (point.x - CELL.x * 0.5) * side, point.y) * scale)
			var fill := Color("#263247").lerp(accent, 0.20) if i == 0 else Color(accent, 0.92)
			view.draw_colored_polygon(points, fill)
			if i == 0:
				points.append(points[0])
				view.draw_polyline(points, accent, maxf(1.0, scale * 2.5), true)


static func draw(view: CanvasItem, center: Vector2, bounds: Vector2, profile: Array, time: float, elite := false) -> void:
	var faction: String = profile[0]
	var slot: int = profile[1]
	var effect: String = profile[2]
	var waveform: bool = profile[3]
	var atlas: Texture2D = ATLASES[faction]
	var columns := 5 if faction == "neutral" else 3
	var source := Rect2(Vector2(slot % columns, floori(float(slot) / columns)) * CELL, CELL)
	var scale := minf(bounds.x / CELL.x, bounds.y / CELL.y)
	var origin := center - CELL * scale * 0.5
	var accent := Color(Themes.FACTIONS_DARK[faction])
	if elite:
		_draw_elite_gear(view, origin, scale, ELITE_GEAR[faction], accent)

	if effect == "fracture":
		_draw_glitch(view, atlas, source, origin, scale, accent, time)
	else:
		_draw_background_effect(view, effect, origin, scale, accent, time)
		view.draw_texture_rect_region(atlas, Rect2(origin, CELL * scale), source)
		if effect == "coolant":
			_draw_coolant(view, origin, scale, time)
		elif effect == "bio":
			var intensity := 0.5 + 0.5 * sin(time * 3.4)
			view.draw_circle(origin + Vector2(110, 124) * scale, (15.0 + 5.0 * intensity) * scale, Color(accent, 0.21), true, -1, true)
			view.draw_circle(origin + Vector2(110, 124) * scale, 5.0 * scale, Color.WHITE.lerp(accent, 0.32 + 0.25 * intensity), true, -1, true)
		if waveform:
			_draw_waveform(view, origin, scale, accent, time)
	if elite:
		_draw_elite_gear(view, origin, scale, ELITE_MOUNTS[faction], accent)


static func _draw_background_effect(view: CanvasItem, effect: String, o: Vector2, s: float, ink: Color, time: float) -> void:
	match effect:
		"vents", "reactor":
			for i in 6:
				var age := fposmod(time * 0.7 + float(i) / 6.0, 1.0)
				var x := 47.0 + (i % 3 - 1) * 7.0 - age * 15.0
				for side in [x, 220.0 - x]:
					view.draw_circle(o + Vector2(side, 101.0 - age * 70.0) * s, (2.8 - 1.8 * age) * s, Color(ink, 0.85 * (1.0 - age)), true, -1, true)
		"bio":
			var pulse := 0.55 + 0.45 * sin(time * 3.4)
			for i in 6:
				var radius := 103.0 - i * 10.0
				view.draw_circle(o + Vector2(110, 94) * s, radius * s, Color(ink, 0.022 + 0.019 * pulse), true, -1, true)
		"chrome":
			var hex := PackedVector2Array()
			for point in [Vector2(110, 12), Vector2(190, 51), Vector2(190, 116), Vector2(110, 159), Vector2(30, 116), Vector2(30, 51), Vector2(110, 12)]:
				hex.append(o + point * s)
			view.draw_polyline(hex, Color(ink, 0.42 + 0.24 * sin(time * 3.0)), maxf(1.0, s * 1.7), true)
			var scan := fposmod(time * 0.65, 1.0)
			var y := 48.0 + scan * 72.0
			view.draw_line(o + Vector2(40, y) * s, o + Vector2(180, y) * s, Color(ink, 0.48 * sin(PI * scan)), maxf(1.0, s * 2.0), true)
		"signal":
			for i in 3:
				var age := fposmod(time * 1.4 + float(i) / 3.0, 1.0)
				var arc := PackedVector2Array()
				for j in 19:
					var angle := PI + PI * j / 18.0
					var local := Vector2(110, 70) + Vector2(cos(angle) * (52.0 + age * 49.0), sin(angle) * (29.0 + age * 33.0))
					arc.append(o + local * s)
				view.draw_polyline(arc, Color(ink, 0.72 * (1.0 - age)), maxf(1.0, s * 2.3), true)


static func _draw_coolant(view: CanvasItem, origin: Vector2, scale: float, time: float) -> void:
	# Follow the same four sections as the painted coolant conduit.
	var points := [Vector2(44, 121), Vector2(64, 106), Vector2(85, 106), Vector2(110, 114),
		Vector2(135, 106), Vector2(156, 106), Vector2(176, 121)]
	var head := fposmod(time * 0.72, 1.0) * (points.size() - 1)
	var streak := PackedVector2Array()
	for i in 5:
		var progress := clampf(head - float(i) * 0.06, 0.0, points.size() - 1.001)
		var segment := floori(progress)
		var local: Vector2 = points[segment].lerp(points[segment + 1], progress - segment)
		streak.append(origin + local * scale)
	view.draw_polyline(streak, Color("#e1fcff"), maxf(1.0, scale * 2.6), true)


static func _draw_waveform(view: CanvasItem, origin: Vector2, scale: float, accent: Color, time: float) -> void:
	var trace := PackedVector2Array()
	for i in 26:
		var ratio := float(i) / 25.0
		var phase := i * 1.03 - time * 12.0
		var y := 63.0 + sin(PI * ratio) * (6.0 * sin(phase) + 3.0 * sin(2.0 * phase + time * 8.0))
		trace.append(origin + Vector2(82.0 + 56.0 * ratio, y) * scale)
	view.draw_polyline(trace, Color(accent, 0.22), maxf(1.0, scale * 6.0), true)
	view.draw_polyline(trace, accent, maxf(1.0, scale * 2.8), true)


static func _draw_glitch(view: CanvasItem, atlas: Texture2D, source: Rect2, origin: Vector2, scale: float, accent: Color, time: float) -> void:
	var step := posmod(floori(time * 15.0), GLITCH_OUTER.size())
	var outer: Vector2 = GLITCH_OUTER[step]
	var middle: float = GLITCH_MIDDLE[step]
	if outer == Vector2.ZERO and middle == 0.0:
		view.draw_texture_rect_region(atlas, Rect2(origin, CELL * scale), source)
		return
	var bands := [[0, 53, 0.0], [53, 18, outer.x], [71, 18, 0.0], [89, 13, middle],
		[102, 9, 0.0], [111, 14, outer.y], [125, 45, 0.0]]
	for band in bands:
		var area := Rect2(Vector2(0, band[0]), Vector2(CELL.x, band[1]))
		var dest := Rect2(origin + Vector2(band[2], band[0]) * scale, area.size * scale)
		view.draw_texture_rect_region(atlas, dest, Rect2(source.position + area.position, area.size))
		if band[2] != 0.0:
			var y: float = band[0] + band[1] * 0.55
			for edge in [52.0, 150.0]:
				var start := origin + Vector2(edge + band[2], y) * scale
				view.draw_line(start, start + Vector2(19.0 * scale, 0), Color(accent, 0.85), maxf(1.0, 2.0 * scale), true)
