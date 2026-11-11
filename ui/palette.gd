class_name Palette
extends RefCounted
## The active visual theme. Every screen reads colors and fonts from here, so
## switching theme (Palette.apply) restyles the whole game. Themes are defined
## in ui/themes.gd. Values below are the defaults ("starforge").

static var theme_id := "starforge"

static var FACTION := {
	"neutral": Color("#c9c2b0"),
	"ember": Color("#ff7a3d"),
	"tide": Color("#3dc6ff"),
	"bloom": Color("#7ee06a"),
	"void": Color("#a98bff"),
}

static var RARITY := {
	"starter": Color("#6f6a60"),
	"common": Color("#a8a8a8"),
	"uncommon": Color("#5fd38a"),
	"rare": Color("#f2c14e"),
	"mythic": Color("#ff4fd8"),
	"curse": Color("#7a4a8c"),
}

static var NODE := {
	"fight": Color("#c9c2b0"),
	"elite": Color("#ff5a5a"),
	"rest": Color("#7ee06a"),
	"shop": Color("#ffd65c"),
	"event": Color("#3dc6ff"),
	"treasure": Color("#f2c14e"),
	"boss": Color("#d36bff"),
}

static var CARD_BG := Color("#17151f")
static var CARD_TEXT := Color("#f2efe6")
static var CARD_TEXT_DIM := Color("#9a96a8")
static var PANEL_BG := Color(0.08, 0.07, 0.12, 0.85)
static var TEXT := Color("#f2efe6")
static var TEXT_DIM := Color("#9a96a8")
static var UPGRADED := Color("#9cff9c")
static var HP := Color("#e0485a")
static var WARD := Color("#7fb8ff")
static var ENERGY := Color("#ffd65c")
static var ENEMY := Color("#d36bff")
static var BUTTON := Color("#2a2340")
static var BUTTON_TEXT := Color("#f2efe6")
## Card frame shape.
static var RADIUS := 10
static var BORDER := 2
static var LINE := 2.0
## Backdrop shader: style 0 nebula, 1 paper, 2 grid, 3 glass shards.
static var BACKDROP := {"style": 0, "top": Color(0.09, 0.07, 0.15), "bottom": Color(0.02, 0.02, 0.05), "glow": Color(0.55, 0.28, 0.85)}

## World-specific words (title, hero, pack, dust, faction names...). See Palette.w().
static var WORDS := {}
const DEFAULT_WORDS := {
	"title": "TCG SPIRE", "hero": "You", "tagline": "", "pack": "Pack", "packs": "Packs", "dust": "Dust",
	"rest": "A quiet campfire", "rest_text": "", "shop": "Merchant", "treasure": "Treasure", "camp": "Back to camp",
}

static var _display_font: Font
static var _body_font: Font


## Themed word for `key`, e.g. w("dust") -> "Ink" in the Archive theme.
static func w(key: String) -> String:
	return str(WORDS.get(key, DEFAULT_WORDS.get(key, key.capitalize())))


## Display name of a faction in the current world ("ember" -> "Pyre").
static func faction_name(f: String) -> String:
	return str(WORDS.get(f, f.capitalize()))


static func faction(f: String) -> Color:
	return FACTION.get(f, FACTION["neutral"])


static func rarity(r: String) -> Color:
	return RARITY.get(r, RARITY["common"])


## Body text font (rules text, labels).
static func font() -> Font:
	return _body_font if _body_font != null else ThemeDB.fallback_font


## Titles and card names.
static func display() -> Font:
	return _display_font if _display_font != null else font()


## Applies a theme from Themes.ALL. Unknown ids fall back to the default.
static func apply(id: String) -> void:
	var t: Dictionary = Themes.ALL.get(id, Themes.ALL[Themes.DEFAULT])
	theme_id = id if Themes.ALL.has(id) else Themes.DEFAULT
	for k in t.get("colors", {}):
		set_color(k, t["colors"][k])
	for group in ["FACTION", "RARITY", "NODE"]:
		var src: Dictionary = t.get(group.to_lower(), {})
		var dst: Dictionary = _group(group)
		for k in src:
			dst[k] = Color(src[k])
	WORDS = t.get("words", {})
	RADIUS = int(t.get("radius", 10))
	BORDER = int(t.get("border", 2))
	LINE = float(t.get("line", 2.0))
	var b: Dictionary = t.get("backdrop", {})
	BACKDROP = {"style": int(b.get("style", 0)), "top": Color(b.get("top", "#171226")),
		"bottom": Color(b.get("bottom", "#05050c")), "glow": Color(b.get("glow", "#8c47d9"))}
	_display_font = _load_font(t.get("display_font", ""))
	_body_font = _load_font(t.get("body_font", ""))


static func set_color(key: String, v: Variant) -> void:
	var c := Color(v)
	match key:
		"card_bg": CARD_BG = c
		"card_text": CARD_TEXT = c
		"card_text_dim": CARD_TEXT_DIM = c
		"panel": PANEL_BG = c
		"text": TEXT = c
		"text_dim": TEXT_DIM = c
		"upgraded": UPGRADED = c
		"hp": HP = c
		"ward": WARD = c
		"accent": ENERGY = c
		"enemy": ENEMY = c
		"button": BUTTON = c
		"button_text": BUTTON_TEXT = c


static func _group(g: String) -> Dictionary:
	match g:
		"FACTION": return FACTION
		"RARITY": return RARITY
	return NODE


static func _load_font(path: String) -> Font:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path)


## A Godot Theme for built-in controls (buttons, labels, scroll bars).
static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font = font()
	th.default_font_size = 16
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = BUTTON
		if state == "hover":
			sb.bg_color = BUTTON.lightened(0.12)
		elif state == "pressed":
			sb.bg_color = ENERGY.darkened(0.2)
		elif state == "disabled":
			sb.bg_color = Color(BUTTON, 0.45)
		elif state == "focus":
			sb.bg_color = Color(0, 0, 0, 0)
			sb.draw_center = false
		sb.border_color = Color(ENERGY, 0.0 if state == "focus" else 0.55)
		sb.set_border_width_all(BORDER if state != "focus" else 0)
		sb.set_corner_radius_all(RADIUS)
		sb.set_content_margin_all(10)
		th.set_stylebox(state, "Button", sb)
	th.set_color("font_color", "Button", BUTTON_TEXT)
	th.set_color("font_hover_color", "Button", BUTTON_TEXT)
	th.set_color("font_pressed_color", "Button", CARD_BG)
	th.set_color("font_disabled_color", "Button", Color(BUTTON_TEXT, 0.4))
	th.set_color("font_color", "Label", TEXT)
	return th
