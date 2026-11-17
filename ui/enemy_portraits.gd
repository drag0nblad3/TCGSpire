class_name EnemyPortraits
extends RefCounted
## Neon creature bases, animated faction signals, and separate elite overlays.
## Design coordinates remain 220 × 170; raster atlases use double resolution.

const CELL := Vector2(220, 170)
const ATLASES := {
	"ember": preload("res://assets/combat/neon/ember.webp"),
	"tide": preload("res://assets/combat/neon/tide.webp"),
	"bloom": preload("res://assets/combat/neon/bloom.webp"),
	"void": preload("res://assets/combat/neon/void.webp"),
	"chrome": preload("res://assets/combat/neon/chrome.webp"),
	"noise": preload("res://assets/combat/neon/noise.webp"),
	"neutral": preload("res://assets/combat/neon/neutral.webp"),
}
const ROSTER := {
	"burner_tagger": ["ember", 0, "vents"],
	"kiln_enforcer": ["ember", 1, "vents"],
	"furnace_hulk": ["ember", 2, "vents"],
	"pyre_warlord": ["ember", 3, "reactor"],
	"ash_runner": ["ember", 4, "vents"],
	"slag_titan": ["ember", 5, "reactor"],
	"ember_marshal": ["ember", 6, "vents"],
	"flux_courier": ["tide", 0, "coolant"],
	"broker_guard": ["tide", 1, "coolant"],
	"data_leviathan": ["tide", 2, "coolant"],
	"ledger_warden": ["tide", 3, "coolant"],
	"margin_agent": ["tide", 4, "coolant"],
	"deep_ledger": ["tide", 5, "coolant"],
	"riptide_auditor": ["tide", 6, "coolant"],
	"vat_grub": ["bloom", 0, "bio"],
	"clinic_orderly": ["bloom", 1, "bio"],
	"flesh_golem": ["bloom", 2, "bio"],
	"gene_surgeon": ["bloom", 3, "bio"],
	"spore_nurse": ["bloom", 4, "bio"],
	"chimera": ["bloom", 5, "bio"],
	"head_geneticist": ["bloom", 6, "bio"],
	"null_flicker": ["void", 0, "fracture"],
	"cell_eraser": ["void", 1, "fracture"],
	"void_maw": ["void", 2, "fracture"],
	"zero_prophet": ["void", 3, "fracture"],
	"blank": ["void", 4, "fracture"],
	"event_horizon": ["void", 5, "fracture"],
	"null_cardinal": ["void", 6, "fracture"],
	"sentry_drone": ["chrome", 0, "chrome"],
	"plated_guard": ["chrome", 1, "chrome"],
	"riot_mech": ["chrome", 2, "chrome"],
	"hive_controller": ["chrome", 3, "chrome"],
	"strike_drone": ["chrome", 4, "chrome"],
	"siege_walker": ["chrome", 5, "chrome"],
	"swarm_admiral": ["chrome", 6, "chrome"],
	"pirate_jammer": ["noise", 0, "signal"],
	"shock_jock": ["noise", 1, "signal"],
	"signal_tower": ["noise", 2, "signal"],
	"the_anchor": ["noise", 3, "signal"],
	"feedback_loop": ["noise", 4, "signal"],
	"speaker_stack": ["noise", 5, "signal"],
	"the_headliner": ["noise", 6, "signal"],
	"cinder_mite": ["neutral", 0, "core"],
	"hollow_wisp": ["neutral", 1, "core"],
	"ember_imp": ["neutral", 2, "core"],
	"bramble_crawler": ["neutral", 3, "core"],
	"tide_lurker": ["neutral", 4, "core"],
	"spore_pod": ["neutral", 5, "core"],
	"shard_golem": ["neutral", 6, "core"],
	"hex_knight": ["neutral", 7, "core"],
	"brood_mother": ["neutral", 8, "core"],
	"glass_wraith": ["neutral", 9, "fracture"],
	"black_ice": ["neutral", 10, "core"],
	"worm_larva": ["neutral", 11, "core"],
	"orphan_daemon": ["neutral", 12, "chrome"],
	"deadman_switch": ["neutral", 13, "core"],
	"archivist": ["neutral", 14, "core"],
	"kill_switch": ["neutral", 15, "core"],
	"worm_queen": ["neutral", 16, "core"],
	"storm_harpy": ["neutral", 17, "core"],
	"rust_sentinel": ["neutral", 18, "core"],
	"void_tick": ["neutral", 19, "fracture"],
	"ash_shaman": ["neutral", 20, "core"],
	"mire_beast": ["neutral", 21, "core"],
	"reaver": ["neutral", 22, "core"],
	"chorus_of_echoes": ["neutral", 23, "signal"],
	"warden_construct": ["neutral", 24, "chrome"],
}

# Offsets are intentionally discontinuous. The middle band jumps on its own beats.
const GLITCH_OUTER := [
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(14, -7), Vector2(-17, 12), Vector2(5, -13),
	Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(-19, 10),
	Vector2(11, -16), Vector2(-5, 4), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
	Vector2(16, 6), Vector2(-12, -11), Vector2(20, 9), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO,
]
# Effect ink that matches the painted glow where the crew colour does not (Noise art is magenta,
# its crew colour is amber).
const ART_GLOW := {"noise": "#ff4bd8"}
const GLITCH_MIDDLE := [0, -13, 17, 0, 0, 0, 0, 0, 14, -10, 0, 0, 0, 0, 0, 16, -12, 0, 0, 0, 0, 0, 19, -9]


## Overlays are transparent atlas cells, never baked into a normal creature.
static func _draw_elite_layer(view: CanvasItem, atlas: Texture2D, faction: String, origin: Vector2, scale: float, front: bool, time: float, effect: String) -> void:
	var columns := 5 if faction == "neutral" else 3
	var slot := (25 if faction == "neutral" else 7) + (1 if front else 0)
	var source := Rect2(Vector2(slot % columns, floori(float(slot) / columns)) * CELL * 2.0, CELL * 2.0)
	_draw_body(view, atlas, source, origin, scale, effect, time)


## Continuous strip deformation keeps the original ink and alpha intact. The feet
## anchor while the upper silhouette bends; no generated frames or fog overlays.
static func idle_point(point: Vector2, effect: String, time: float) -> Vector2:
	var height := 1.0 - point.y / CELL.y
	var spread := (point.x - CELL.x * 0.5) / (CELL.x * 0.5)
	var beat := sin(time * 2.7)
	var delta := Vector2.ZERO
	match effect:
		"vents", "reactor":
			delta = Vector2(spread * beat * 3.0, -height * beat * 3.5)
		"coolant":
			delta = Vector2(sin(time * 2.2 + height * 3.0) * height * 6.0, sin(time * 1.8) * height * 2.0)
		"bio":
			delta = Vector2(spread * sin(time * 2.5 + height * 2.0) * 4.0, -height * beat * 5.0)
		"chrome":
			delta = Vector2(sin(time * 1.7) * height * 2.5, -height * sin(time * 3.4) * 2.0)
		"signal":
			delta = Vector2(sin(time * 3.8 + height * 2.0) * height * 4.0, -height * absf(beat) * 4.0)
		"fracture":
			delta = Vector2(sin(time * 1.9 + height * 2.0) * height * 4.0, -height * sin(time * 2.1) * 4.0)
		_:
			delta = Vector2(sin(time * 2.0 + height) * height * 4.0 + spread * beat * 2.0, -height * beat * 3.0)
	return point + delta


static func _draw_body(view: CanvasItem, atlas: Texture2D, source: Rect2, origin: Vector2, scale: float, effect: String, time: float) -> void:
	# Shared edges and UVs avoid gaps, and never sample a neighbouring atlas cell.
	for row in 12:
		var top := CELL.y * row / 12.0
		var bottom := CELL.y * (row + 1) / 12.0
		var vertices := PackedVector2Array()
		var uv := PackedVector2Array()
		for point in [Vector2(0, top), Vector2(CELL.x, top), Vector2(CELL.x, bottom), Vector2(0, bottom)]:
			vertices.append(origin + idle_point(point, effect, time) * scale)
			uv.append((source.position + point * 2.0) / atlas.get_size())
		view.draw_polygon(vertices, PackedColorArray([Color.WHITE]), uv, atlas)


static func draw(view: CanvasItem, center: Vector2, bounds: Vector2, profile: Array, time: float, elite := false) -> void:
	var faction: String = profile[0]
	var slot: int = profile[1]
	var effect: String = profile[2]
	time += float(slot) * 0.73
	var atlas: Texture2D = ATLASES[faction]
	var columns := 5 if faction == "neutral" else 3
	var source := Rect2(Vector2(slot % columns, floori(float(slot) / columns)) * CELL * 2.0, CELL * 2.0)
	var scale := minf(bounds.x / CELL.x, bounds.y / CELL.y)
	var origin := center - CELL * scale * 0.5
	var accent := Color(ART_GLOW.get(faction, Themes.FACTIONS_DARK[faction]))
	if elite:
		_draw_elite_layer(view, atlas, faction, origin, scale, false, time, effect)

	if effect == "fracture":
		_draw_glitch(view, atlas, source, origin, scale, accent, time)
	else:
		_draw_background_effect(view, effect, origin, scale, accent, time)
		_draw_body(view, atlas, source, origin, scale, effect, time)
		if effect == "coolant":
			_draw_coolant(view, origin, scale, time)
		elif effect == "bio":
			var intensity := 0.5 + 0.5 * sin(time * 3.4)
			view.draw_circle(origin + Vector2(110, 124) * scale, (15.0 + 5.0 * intensity) * scale, Color(accent, 0.21), true, -1, true)
			view.draw_circle(origin + Vector2(110, 124) * scale, 5.0 * scale, Color.WHITE.lerp(accent, 0.32 + 0.25 * intensity), true, -1, true)
	if elite:
		_draw_elite_layer(view, atlas, faction, origin, scale, true, time, effect)


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
			view.draw_arc(o + Vector2(110, 94) * s, (65.0 + 4.0 * pulse) * s, 0.2, PI - 0.2, 36, Color(ink, 0.18 + 0.12 * pulse), maxf(1.0, s), true)
		"chrome":
			var hex := PackedVector2Array()
			for point in [Vector2(110, 12), Vector2(190, 51), Vector2(190, 116), Vector2(110, 159), Vector2(30, 116), Vector2(30, 51), Vector2(110, 12)]:
				hex.append(o + point * s)
			view.draw_polyline(hex, Color(ink, 0.42 + 0.24 * sin(time * 3.0)), maxf(1.0, s * 1.7), true)
			var scan := fposmod(time * 0.65, 1.0)
			var y := 48.0 + scan * 72.0
			view.draw_line(o + Vector2(40, y) * s, o + Vector2(180, y) * s, Color(ink, 0.48 * sin(PI * scan)), maxf(1.0, s * 2.0), true)
		"signal":
			# Broadcast rings spread from the chest behind the body; the painted horns and
			# antennae stay readable on top.
			for i in 3:
				var age := fposmod(time * 0.9 + float(i) / 3.0, 1.0)
				var radius := Vector2(40.0 + age * 66.0, 30.0 + age * 48.0)
				var ring := PackedVector2Array()
				for j in 41:
					var angle := TAU * j / 40.0
					ring.append(o + (Vector2(110, 92) + Vector2(cos(angle) * radius.x, sin(angle) * radius.y)) * s)
				view.draw_polyline(ring, Color(ink, 0.34 * (1.0 - age) * minf(1.0, age * 4.0)), maxf(1.0, s * 1.6), true)


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


static func _draw_glitch(view: CanvasItem, atlas: Texture2D, source: Rect2, origin: Vector2, scale: float, accent: Color, time: float) -> void:
	var step := posmod(floori(time * 15.0), GLITCH_OUTER.size())
	var outer: Vector2 = GLITCH_OUTER[step]
	var middle: float = GLITCH_MIDDLE[step]
	if outer == Vector2.ZERO and middle == 0.0:
		_draw_body(view, atlas, source, origin, scale, "fracture", time)
		return
	var bands := [[0, 53, 0.0], [53, 18, outer.x], [71, 18, 0.0], [89, 13, middle],
		[102, 9, 0.0], [111, 14, outer.y], [125, 45, 0.0]]
	for band in bands:
		var area := Rect2(Vector2(0, band[0]), Vector2(CELL.x, band[1]))
		var dest := Rect2(origin + Vector2(band[2], band[0]) * scale, area.size * scale)
		view.draw_texture_rect_region(atlas, dest, Rect2(source.position + area.position * 2.0, area.size * 2.0))
		if band[2] != 0.0:
			var y: float = band[0] + band[1] * 0.55
			for edge in [52.0, 150.0]:
				var start := origin + Vector2(edge + band[2], y) * scale
				view.draw_line(start, start + Vector2(19.0 * scale, 0), Color(accent, 0.85), maxf(1.0, 2.0 * scale), true)
