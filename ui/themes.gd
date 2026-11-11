class_name Themes
extends RefCounted
## Visual themes, one per world concept being explored. Each sets colors,
## fonts, frame shape and the backdrop style. Add a theme = add an entry here.

const DEFAULT := "starforge"
const ORDER := ["starforge", "archive", "cathedral", "undercity"]

const ALL := {
	"starforge": {
		"name": "Star-Forge",
		"blurb": "Astral navy, constellations and gold.",
		"words": {
			"title": "STAR-FORGE", "hero": "Pilgrim",
			"tagline": "A star fell and left its tether standing. Climb it, chart its constellations, and forge them into cards.",
			"pack": "Star chart", "packs": "Star charts", "dust": "Stardust",
			"rest": "Observatory", "rest_text": "You rest beneath slow constellations.",
			"shop": "Comet trader", "treasure": "Fallen star", "camp": "Back to the foot of the tether",
			"neutral": "Dust", "ember": "Solar", "tide": "Lunar", "bloom": "Nebula", "void": "Abyss",
		},
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
		"faction": {"neutral": "#d6d2c4", "ember": "#ff8a4c", "tide": "#4fd0ff", "bloom": "#8be879", "void": "#b49bff"},
	},
	"archive": {
		"name": "Archive Spire",
		"blurb": "Parchment, ink and illuminated margins.",
		"words": {
			"title": "THE ARCHIVE SPIRE", "hero": "Binder",
			"tagline": "The tower's stories have slipped out of their books. You are a Binder: catch them, bind them into cards, and climb to the Unwritten.",
			"pack": "Folio", "packs": "Folios", "dust": "Ink",
			"rest": "Reading room", "rest_text": "Lamplight, a soft chair, and a book that stays put.",
			"shop": "Bookseller", "treasure": "Lost chapter", "camp": "Back to the scriptorium",
			"neutral": "Prose", "ember": "Pyre", "tide": "Ink", "bloom": "Margin", "void": "Erasure",
		},
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
		"faction": {"neutral": "#5a4a3a", "ember": "#b8431f", "tide": "#1f5f8f", "bloom": "#3f7a2a", "void": "#5b3c8c"},
		"rarity": {"starter": "#8a7a66", "common": "#6e5a43", "uncommon": "#2f7a3a", "rare": "#b8860b", "mythic": "#8c1f6a"},
		"node": {"fight": "#3a2a1c", "elite": "#a2391f", "rest": "#3f7a2a", "shop": "#b8860b", "event": "#1f5f8f", "treasure": "#b8860b", "boss": "#5b3c8c"},
	},
	"cathedral": {
		"name": "Cathedral of Glass",
		"blurb": "Jewel-toned glass held in heavy black leading.",
		"words": {
			"title": "CATHEDRAL OF GLASS", "hero": "Glazier",
			"tagline": "A god shattered, and their cathedral with them. Gather the stained-glass shards and set them back into the windows.",
			"pack": "Reliquary", "packs": "Reliquaries", "dust": "Glass dust",
			"rest": "Quiet chapel", "rest_text": "Coloured light falls across the pews.",
			"shop": "Pardoner", "treasure": "Reliquary chest", "camp": "Back to the nave",
			"neutral": "Laity", "ember": "Flame", "tide": "Font", "bloom": "Garden", "void": "Eclipse",
		},
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
		"faction": {"neutral": "#e8e0c8", "ember": "#ff6a2b", "tide": "#2b8cff", "bloom": "#33d17a", "void": "#9b5cff"},
	},
	"undercity": {
		"name": "Neon Undercity",
		"blurb": "Black glass, cyan and magenta circuitry.",
		"words": {
			"title": "NEON UNDERCITY", "hero": "Runner",
			"tagline": "Under the arcology, spells run as code. Jack in, rip spellware from rival covens, and reach the top of the stack.",
			"pack": "Data cache", "packs": "Data caches", "dust": "Scrap",
			"rest": "Safehouse", "rest_text": "A locked door, a cot, and a cooling rig.",
			"shop": "Fixer", "treasure": "Loot crate", "camp": "Back to the hideout",
			"neutral": "Street", "ember": "Burners", "tide": "Flux", "bloom": "Wetware", "void": "Null",
		},
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
		"faction": {"neutral": "#b8c4d6", "ember": "#ff7a00", "tide": "#00e5ff", "bloom": "#39ff9e", "void": "#b04dff"},
	},
}


static func next_after(id: String) -> String:
	var i := ORDER.find(id)
	return ORDER[(i + 1) % ORDER.size()]
