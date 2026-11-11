class_name Palette
extends RefCounted
## The whole visual identity lives here: change these and every card, glyph
## and panel follows. Keep factions to one strong hue each.

const FACTION := {
	"neutral": Color("#c9c2b0"),
	"ember": Color("#ff7a3d"),
	"tide": Color("#3dc6ff"),
	"bloom": Color("#7ee06a"),
}

const RARITY := {
	"starter": Color("#6f6a60"),
	"common": Color("#a8a8a8"),
	"uncommon": Color("#5fd38a"),
	"rare": Color("#f2c14e"),
	"mythic": Color("#ff4fd8"),
	"curse": Color("#7a4a8c"),
}

const NODE := {
	"fight": Color("#c9c2b0"),
	"elite": Color("#ff5a5a"),
	"rest": Color("#7ee06a"),
	"shop": Color("#ffd65c"),
	"event": Color("#3dc6ff"),
	"treasure": Color("#f2c14e"),
	"boss": Color("#d36bff"),
}

const CARD_BG := Color("#17151f")
const PANEL_BG := Color(0.08, 0.07, 0.12, 0.85)
const TEXT := Color("#f2efe6")
const TEXT_DIM := Color("#9a96a8")
const UPGRADED := Color("#9cff9c")
const HP := Color("#e0485a")
const WARD := Color("#7fb8ff")
const ENERGY := Color("#ffd65c")
const ENEMY := Color("#d36bff")


static func faction(f: String) -> Color:
	return FACTION.get(f, FACTION["neutral"])


static func rarity(r: String) -> Color:
	return RARITY.get(r, RARITY["common"])


static func font() -> Font:
	return ThemeDB.fallback_font
