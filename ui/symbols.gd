class_name Symbols
extends RefCounted
## Deliberately shaped, theme-tinted faction emblems and map pictograms.
static var _textures: Dictionary = {}


static func texture(id: String) -> Texture2D:
	if not _textures.has(id):
		var path := "res://assets/symbols/%s.svg" % id
		_textures[id] = load(path if ResourceLoader.exists(path) else "res://assets/symbols/neutral.svg")
	return _textures[id]


static func draw_on(canvas: CanvasItem, center: Vector2, radius: float, id: String, color: Color) -> void:
	canvas.draw_texture_rect(texture(id), Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), false, color)


static func badge(id: String, extent: float = 32.0) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture(id)
	icon.custom_minimum_size = Vector2.ONE * extent
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Palette.faction(id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon
