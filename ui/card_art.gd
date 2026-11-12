class_name CardArt
extends RefCounted
## Shared atlas: one texture for all 88 Field Service illustrations.
## Manifest keys are stable card ids; upgrades and firmware share their base art.
const ATLAS: Texture2D = preload("res://assets/cards/field_service.webp")
static var _regions: Dictionary = {}
static var _textures: Dictionary = {}
static var _loaded := false


static func regions() -> Dictionary:
	if not _loaded:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/card_art.json"))
		if parsed is Dictionary:
			_regions = parsed
		_loaded = true
	return _regions


static func texture_for(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var bounds: Array = regions().get(id, [])
	if bounds.size() != 4:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = ATLAS
	texture.region = Rect2(bounds[0], bounds[1], bounds[2], bounds[3])
	texture.filter_clip = true
	_textures[id] = texture
	return texture
