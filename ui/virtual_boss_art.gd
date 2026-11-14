class_name VirtualBossArt
extends RefCounted
## Presentation only. Bounded strip warps preserve the approved raster art;
## effects use the current theme accent and never overlap combat text.
const ANIMATED := ["kiln_mother", "undertow_broker", "chief_surgeon", "zero_prime", "hive_overseer", "dj_feedback"]

# effect, body frequency, body amplitude, effect speed, anchor x/y, radius.
const PROFILES := {
	"furnace_king": ["crown", 3.0, 0.005, 0.7, 0.5, 0.25, 0.20],
	"tidal_exchange": ["vortex", 2.0, 0.014, 1.2, 0.5, 0.67, 0.24],
	"gene_saint": ["spores", 1.5, 0.007, 0.4, 0.5, 0.48, 0.32],
	"the_absence": ["erase", 0.8, 0.018, 0.5, 0.53, 0.48, 0.30],
	"chrome_queen": ["lances", 1.4, 0.004, 0.6, 0.5, 0.46, 0.34],
	"the_broadcast": ["sound", 5.0, 0.012, 0.8, 0.5, 0.30, 0.30],
	"kiln_heart": ["corona", 3.5, 0.008, 0.55, 0.5, 0.52, 0.26],
	"drowned_market": ["vortex", 1.2, 0.017, -0.8, 0.58, 0.55, 0.32],
	"mother_vat": ["cells", 1.0, 0.009, 0.5, 0.5, 0.54, 0.28],
	"zero_point": ["singularity", 0.9, 0.005, -0.7, 0.5, 0.60, 0.24],
	"hive_throne": ["grid", 1.0, 0.003, 0.45, 0.5, 0.5, 0.33],
	"dead_air": ["flatline", 0.6, 0.010, 0.4, 0.5, 0.43, 0.35],
	"hollow_monarch": ["decree", 1.2, 0.006, 0.6, 0.5, 0.5, 0.30],
	"cinder_colossus": ["shock", 2.0, 0.008, 0.6, 0.5, 0.85, 0.28],
	"the_unwritten": ["index", 1.1, 0.019, 0.6, 0.5, 0.5, 0.32],
	"storm_regent": ["storm", 2.7, 0.006, 0.7, 0.5, 0.4, 0.32],
	"root_kernel": ["roots", 0.8, 0.005, 0.5, 0.5, 0.4, 0.30],
	"last_mirror": ["mirror", 1.3, 0.011, 0.5, 0.5, 0.5, 0.32],
}

static func supports(id: String) -> bool:
	return ANIMATED.has(id) or PROFILES.has(id)

static func draw(canvas: CanvasItem, texture: Texture2D, rect: Rect2, id: String, time: float, action: float, tint: Color, accent: Color) -> void:
	var strength := 1.0 + action * 2.5
	var tex_size := texture.get_size()
	# Horizontal slices let each entity's body move without animating the UI.
	for band in 48:
		var v := float(band) / 48.0
		var envelope := sin(v * PI)
		var shift := 0.0
		match id:
			"kiln_mother": shift = sin(v * 24.0 - time * 4.0) * 0.003 * envelope
			"undertow_broker": shift = sin(v * 10.0 - time * 2.5) * 0.013 * envelope
			"chief_surgeon": shift = sin(time * 2.0) * sin(v * 8.0) * 0.006 * envelope
			"zero_prime":
				if fmod(time + v * 0.7, 2.4) < 0.22:
					shift = sin(float(band) * 9.0 + floor(time * 12.0)) * 0.028 * envelope
			"hive_overseer": shift = sin(time * 1.6 + v * 4.0) * 0.003 * envelope
			"dj_feedback": shift = sin(time * 6.0 - v * 16.0) * 0.009 * envelope
		if PROFILES.has(id):
			var profile: Array = PROFILES[id]
			shift = sin(time * float(profile[1]) + v * 12.0) * float(profile[2]) * envelope
		var dest := Rect2(rect.position + Vector2(shift * rect.size.x * strength, v * rect.size.y), Vector2(rect.size.x, rect.size.y / 48.0 + 0.3))
		var source := Rect2(0, v * tex_size.y, tex_size.x, tex_size.y / 48.0)
		canvas.draw_texture_rect_region(texture, dest, source, tint)
	var center := rect.get_center()
	var scale := rect.size.y
	var ink := Color(accent, 0.50 + action * 0.35)
	match id:
		"kiln_mother":
			for i in 12:
				var phase := fposmod(time * 0.24 + i * 0.0833, 1.0)
				var p := rect.position + rect.size * Vector2(0.22 + fposmod(i * 0.317, 0.56), 0.85 - phase * 0.66)
				var r := scale * 0.009 * strength
				canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, r), p + Vector2(-r, r)]), Color(ink, (1.0 - phase) * 0.75))
		"undertow_broker":
			for i in 8:
				var angle := time * 1.2 + i * TAU / 8.0
				var p := center + Vector2(cos(angle) * rect.size.x * 0.34, sin(angle) * scale * 0.12 + scale * 0.15)
				canvas.draw_line(p, p + Vector2(scale * 0.045, -scale * 0.012), ink, 2.0, true)
		"chief_surgeon":
			var p := center + Vector2(scale * 0.05, scale * 0.09)
			for i in 2:
				var radius := scale * (0.07 + 0.012 * sin(time * 2.0 + i * PI))
				canvas.draw_arc(p + Vector2(i * scale * 0.065, 0), radius, time * 0.7, time * 0.7 + PI * 1.6, 24, ink, 1.5, true)
		"zero_prime":
			for i in 7:
				var phase := fposmod(time * 0.3 + i * 0.14, 1.0)
				var p := rect.position + rect.size * Vector2(0.62 + phase * 0.25, 0.15 + i * 0.1)
				canvas.draw_rect(Rect2(p, rect.size * Vector2(0.025 + phase * 0.025, 0.007)), Color(ink, 0.7 * (1.0 - phase)))
		"hive_overseer":
			for i in 6:
				var angle := time * 0.65 + i * TAU / 6.0
				var p := center + Vector2(cos(angle) * rect.size.x * 0.34, sin(angle) * scale * 0.23)
				var r := scale * 0.014
				canvas.draw_line(center, p, Color(ink, 0.13), 1.0, true)
				canvas.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r, r), p + Vector2(-r, r)]), ink)
		"dj_feedback":
			for i in 20:
				var height := (0.015 + 0.055 * absf(sin(time * 6.0 + i * 0.6))) * strength
				var p := rect.position + rect.size * Vector2(0.13 + i * 0.037, 0.86)
				canvas.draw_rect(Rect2(p - Vector2(0, height * scale), Vector2(rect.size.x * 0.014, height * scale)), ink)

	if PROFILES.has(id):
		_draw_system(canvas, rect, PROFILES[id], time, action, accent)

static func _draw_system(c: CanvasItem, rect: Rect2, p: Array, t: float, action: float, accent: Color) -> void:
	var origin := rect.position + rect.size * Vector2(p[4], p[5])
	var radius := minf(rect.size.x, rect.size.y) * float(p[6])
	var clock := t * float(p[3])
	var ink := Color(accent, 0.40 + action * 0.45)
	var effect: String = p[0]
	for i in 12:
		var phase := fposmod(clock + i / 12.0, 1.0)
		var angle := i * TAU / 12.0 + clock
		var direction := Vector2.from_angle(angle)
		var point := origin + direction * radius
		var fade := Color(ink, ink.a * sin(phase * PI))
		match effect:
			"crown", "corona":
				var a := i * TAU / 12.0
				var ray := Vector2.from_angle(a)
				var start := origin + ray * radius * (0.45 + phase * 0.5)
				c.draw_line(start, start + ray * radius * (0.12 + action * 0.2), fade, 2.0, true)
			"vortex":
				var r := radius * (0.15 + phase * 0.85)
				var v := origin + Vector2(cos(angle) * r, sin(angle) * r * 0.45)
				c.draw_line(v, v + Vector2.from_angle(angle + 1.5) * radius * 0.12, fade, 2.0, true)
			"spores", "cells":
				var v := origin + Vector2(cos(angle) * radius * 0.7, sin(angle * 1.7) * radius)
				c.draw_arc(v, radius * (0.035 + phase * 0.06), 0, TAU, 12, fade, 1.5, true)
				if effect == "cells": c.draw_circle(v, radius * 0.02, fade)
			"erase", "singularity":
				var v := origin + direction * radius * (1.0 - phase * 0.8)
				c.draw_line(v, v + direction * radius * 0.08, fade, 2.0, true)
				if effect == "erase": c.draw_rect(Rect2(v, Vector2(radius * 0.07, radius * 0.025)), fade)
			"lances":
				var v := origin + Vector2((i - 5.5) * radius * 0.14, radius * (phase - 0.5))
				c.draw_line(v, v + Vector2(0, radius * (0.12 + action * 0.3)), fade, 1.5, true)
			"sound", "shock":
				if i < 3:
					var r := radius * (0.2 + fposmod(clock + i / 3.0, 1.0) * 0.8)
					if effect == "sound": c.draw_arc(origin, r, 0, TAU, 36, fade, 1.5, true)
					else:
						var pts := PackedVector2Array()
						for j in 33: pts.append(origin + Vector2(cos(j * TAU / 32.0) * r, sin(j * TAU / 32.0) * r * 0.23))
						c.draw_polyline(pts, fade, 2.0, true)
			"grid", "decree":
				var v := origin + Vector2(cos(angle) * radius, sin(angle) * radius * 0.6)
				var pts := PackedVector2Array()
				var sides := 6 if effect == "grid" else 4
				for j in sides + 1: pts.append(v + Vector2.from_angle(j * TAU / sides) * radius * 0.07)
				c.draw_polyline(pts, fade, 1.5, true)
			"flatline":
				var v := origin + Vector2((phase - 0.5) * radius * 2.0, 0)
				c.draw_line(v, v + Vector2(radius * 0.08, 0), fade, 2.0, true)
			"index":
				var v := origin + Vector2((phase - 0.5) * radius * 1.7, (i - 5.5) * radius * 0.13)
				c.draw_rect(Rect2(v, Vector2(radius * 0.12, radius * 0.025)), fade)
			"storm", "roots":
				var ray := Vector2.from_angle(i * TAU / 12.0)
				var start := origin + ray * radius * 0.25
				var end := origin + ray * radius * (0.35 + phase * 0.65)
				var bend := (start + end) * 0.5 + ray.orthogonal() * radius * 0.08 * sin(clock * 8 + i)
				c.draw_polyline(PackedVector2Array([start, bend, end]), fade, 1.5, true)
				if effect == "roots": c.draw_line(bend, end + ray.orthogonal() * radius * 0.12, fade, 1.0, true)
			"mirror":
				var v := origin + direction * radius * (0.5 + phase * 0.4)
				var r := radius * 0.1 * sin(phase * PI)
				c.draw_polyline(PackedVector2Array([v - Vector2(r, 0), v, v + Vector2(0, r)]), fade, 1.5, true)
