class_name BossSupportArt
extends RefCounted
## Separate boss bodies and support units; never change boss layout or rules.
const PROFILES := {
	"bear_desk": [preload("res://assets/combat/support/bear_desk.webp"), "tide"],
	"bull_desk": [preload("res://assets/combat/support/bull_desk.webp"), "tide"],
	"surgeon_clone": [preload("res://assets/combat/support/surgeon_clone.webp"), "bloom"],
	"co_anchor": [preload("res://assets/combat/support/co_anchor.webp"), "noise"],
	"aegis_drone": [preload("res://assets/combat/support/aegis_drone.webp"), "chrome"],
	"capacitor": [preload("res://assets/combat/support/capacitor.webp"), "tide"],
	"mirror_shard": [preload("res://assets/combat/support/mirror_shard.webp"), "void"],
}

static func draw(canvas: CanvasItem, id: String, center: Vector2, bounds: Vector2, time: float, action: float, alive: bool) -> void:
	var profile: Array = PROFILES[id]
	var texture: Texture2D = profile[0]
	var size := texture.get_size()
	size *= minf(bounds.x / size.x, bounds.y / size.y)
	var rect := Rect2(center - size * 0.5, size)
	if alive:
		VirtualBossArt.draw(canvas, texture, rect, id, time, action, Color.WHITE, Palette.faction(profile[1]))
	else:
		canvas.draw_texture_rect(texture, rect, false)
