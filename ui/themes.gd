class_name Themes
extends RefCounted
## Visual skins. The world (names, story) is always the cyberpunk Undercity;
## see Palette.DEFAULT_WORDS and core/lexicon.gd. Each skin sets colors, fonts,
## frame shape and backdrop style. Add a skin = add an entry here.

const DEFAULT := "glassnet"
const ORDER := ["glassnet", "undercity", "cathedral", "starforge", "archive"]

## Keep faction hues recognizable when switching skins. Parchment uses darker inks.
const FACTIONS_DARK := {
	"neutral": "#aaa194", "ember": "#ff865a", "tide": "#59b7ff",
	"bloom": "#67f482", "void": "#cc91ff", "chrome": "#e2efff", "noise": "#ffe064",
}
const FACTIONS_LIGHT := {
	"neutral": "#65594b", "ember": "#a33c17", "tide": "#17588b",
	"bloom": "#286631", "void": "#703c95", "chrome": "#485e75", "noise": "#765600",
}

const ALL := {
	"glassnet": {
		"name": "Glassnet",
		"blurb": "Shattered holo-glass with neon running through the cracks.",
		"display_font": "res://assets/fonts/Orbitron.ttf",
		"body_font": "res://assets/fonts/Rajdhani.ttf",
		"radius": 12, "border": 2, "line": 2.0, "frame": "circuit",
		"backdrop": {"style": 4, "top": "#081226", "bottom": "#020308", "glow": "#00e5ff", "glow2": "#ff2bd6"},
		"colors": {
			"card_bg": "#0a1122", "card_text": "#eafcff", "card_text_dim": "#8aa3bd",
			"panel": "#050a18eb", "text": "#eafcff", "text_dim": "#8aa3bd",
			"accent": "#2ef2ff", "hp": "#ff2b6a", "ward": "#6f8dff", "enemy": "#ff2bd6",
			"button": "#0f1a36", "button_text": "#eafcff", "upgraded": "#39ff9e",
		},
		"faction": FACTIONS_DARK,
		"node": {"fight": "#b8c4d6", "elite": "#ff2b6a", "rest": "#39ff9e", "shop": "#ffd23a", "event": "#2ef2ff", "treasure": "#ffd23a", "boss": "#ff2bd6"},
	},
	"starforge": {
		"name": "Star-Forge",
		"blurb": "Astral navy, constellations and gold.",
		"display_font": "res://assets/fonts/Cinzel.ttf",
		"body_font": "res://assets/fonts/Nunito.ttf",
		"radius": 10, "border": 2, "line": 2.0,
		"backdrop": {"style": 0, "top": "#141a33", "bottom": "#04050d", "glow": "#5b6cff"},
		"colors": {
			"card_bg": "#141729", "card_text": "#eef0ff", "card_text_dim": "#9aa1c4",
			"panel": "#0d1024d9", "text": "#eef0ff", "text_dim": "#9aa1c4",
			"accent": "#ffd65c", "hp": "#ff5470", "ward": "#7fb8ff", "enemy": "#c58bff",
			"button": "#232a52", "button_text": "#eef0ff", "upgraded": "#9cff9c",
		},
		"faction": FACTIONS_DARK,
	},
	"archive": {
		"name": "Parchment",
		"blurb": "Parchment, ink and illuminated margins.",
		"display_font": "res://assets/fonts/Cinzel.ttf",
		"body_font": "res://assets/fonts/EBGaramond.ttf",
		"radius": 4, "border": 2, "line": 2.2,
		"backdrop": {"style": 1, "top": "#e9dcc0", "bottom": "#c9b48a", "glow": "#8a6a3a"},
		"colors": {
			"card_bg": "#f4ead3", "card_text": "#2b1d12", "card_text_dim": "#6e5a43",
			"panel": "#f1e4c8e6", "text": "#2b1d12", "text_dim": "#6e5a43",
			"accent": "#a2391f", "hp": "#a2391f", "ward": "#2f5d8a", "enemy": "#4b2a6b",
			"button": "#3a2a1c", "button_text": "#f4ead3", "upgraded": "#2f7a3a",
		},
		"faction": FACTIONS_LIGHT,
		"rarity": {"starter": "#8a7a66", "common": "#6e5a43", "uncommon": "#2f7a3a", "rare": "#b8860b", "mythic": "#8c1f6a"},
		"node": {"fight": "#3a2a1c", "elite": "#a2391f", "rest": "#3f7a2a", "shop": "#b8860b", "event": "#1f5f8f", "treasure": "#b8860b", "boss": "#5b3c8c"},
	},
	"cathedral": {
		"name": "Cathedral Glass",
		"blurb": "Jewel-toned glass held in heavy black leading.",
		"display_font": "res://assets/fonts/Marcellus.ttf",
		"body_font": "res://assets/fonts/Nunito.ttf",
		"radius": 16, "border": 4, "line": 3.0,
		"backdrop": {"style": 3, "top": "#0d1a3a", "bottom": "#050814", "glow": "#2fb3a8"},
		"colors": {
			"card_bg": "#0b0f1c", "card_text": "#fff8e7", "card_text_dim": "#b9b2a0",
			"panel": "#080b16e6", "text": "#fff8e7", "text_dim": "#b9b2a0",
			"accent": "#ffcf4a", "hp": "#e8334f", "ward": "#4aa3ff", "enemy": "#e04ad0",
			"button": "#1c2450", "button_text": "#fff8e7", "upgraded": "#7dffb0",
		},
		"faction": FACTIONS_DARK,
	},
	"undercity": {
		"name": "Neon Grid",
		"blurb": "Black glass, cyan and magenta circuitry.",
		"display_font": "res://assets/fonts/Orbitron.ttf",
		"body_font": "res://assets/fonts/Rajdhani.ttf",
		"radius": 2, "border": 2, "line": 1.6,
		"backdrop": {"style": 2, "top": "#06040d", "bottom": "#000000", "glow": "#00e5ff"},
		"colors": {
			"card_bg": "#07060c", "card_text": "#e9fbff", "card_text_dim": "#7d93a6",
			"panel": "#05040acc", "text": "#e9fbff", "text_dim": "#7d93a6",
			"accent": "#ff2bd6", "hp": "#ff2b6a", "ward": "#00e5ff", "enemy": "#ff2bd6",
			"button": "#140f24", "button_text": "#e9fbff", "upgraded": "#39ff9e",
		},
		"faction": FACTIONS_DARK,
	},
}


static func next_after(id: String) -> String:
	var i := ORDER.find(id)
	return ORDER[(i + 1) % ORDER.size()]
