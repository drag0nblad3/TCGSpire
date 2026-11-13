class_name CardArt
extends RefCounted
## Shared Field Service atlases for base and expansion illustrations.
## Manifest keys are stable card ids; upgrades and firmware share their base art.
const ATLAS: Texture2D = preload("res://assets/cards/field_service.webp")
const EXPANSION_ATLAS: Texture2D = preload("res://assets/cards/field_service_expansion.webp")
static var _expansion_regions: Dictionary = {}
static var _regions: Dictionary = {}
static var _textures: Dictionary = {}
static var _loaded := false


static func regions() -> Dictionary:
	if not _loaded:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/card_art.json"))
		if parsed is Dictionary:
			_regions = parsed
		var expansion: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/card_art_expansion.json"))
		if expansion is Dictionary:
			_expansion_regions = expansion
			_regions.merge(expansion)
		_loaded = true
	return _regions


static func texture_for(id: String) -> Texture2D:
	if _textures.has(id):
		return _textures[id]
	var bounds: Array = regions().get(id, [])
	if bounds.size() != 4:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = EXPANSION_ATLAS if _expansion_regions.has(id) else ATLAS
	texture.region = Rect2(bounds[0], bounds[1], bounds[2], bounds[3])
	texture.filter_clip = true
	_textures[id] = texture
	return texture


## Find the primary summon card, rather than a secondary summon on a carrier/power.
static func daemon_card(name: String, db: CardDB) -> CardDef:
	for definition: CardDef in db.cards.values():
		if definition.type != "unit" or definition.effects.is_empty():
			continue
		var effect: Dictionary = definition.effects[0]
		if effect.get("op", "") == "summon" and effect.get("name", "") == name:
			return definition
	return null
