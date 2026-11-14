class_name ImplantArt
extends RefCounted
## Approved field-service hardware artwork, shared by every implant view.
const ATLASES := [preload("res://assets/implants/hardware_1.webp"), preload("res://assets/implants/hardware_2.webp")]
const ACTIVE := [preload("res://assets/implants/active_1.webp"), preload("res://assets/implants/active_2.webp")]
static var _regions: Dictionary = {}
static var _textures: Dictionary = {}

static func regions() -> Dictionary:
	if _regions.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/implant_art.json"))
		if data is Dictionary:
			_regions = data
	return _regions

static func texture_for(id: String, active: bool = false) -> Texture2D:
	var key := id + (":active" if active else ":idle")
	if _textures.has(key):
		return _textures[key]
	var entry: Dictionary = regions().get(id, {})
	if entry.is_empty():
		return null
	var r: Array = entry["region"]
	var texture := AtlasTexture.new()
	texture.atlas = (ACTIVE if active else ATLASES)[int(entry["atlas"]) - 1]
	texture.region = Rect2(r[0], r[1], r[2], r[3])
	texture.filter_clip = true
	_textures[key] = texture
	return texture
