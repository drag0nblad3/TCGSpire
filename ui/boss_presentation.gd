class_name BossPresentation
extends RefCounted
## Display-only portraits, entrance accents and the existing move to spotlight.
## Combat and Intents remain the source of all effects and damage numbers.

const PROFILES := {
	"hollow_monarch": {
		"portrait": preload("res://assets/combat/virtual/hollow_monarch.webp"),
		"faction": "void", "signature": "Root Privilege",
	},
	"cinder_colossus": {
		"portrait": preload("res://assets/combat/virtual/cinder_colossus.webp"),
		"faction": "ember", "signature": "Stomp",
	},
	"the_unwritten": {
		"portrait": preload("res://assets/combat/virtual/the_unwritten.webp"),
		"faction": "void", "signature": "Final Commit",
	},
	"storm_regent": {
		"portrait": preload("res://assets/combat/virtual/storm_regent.webp"),
		"faction": "tide", "signature": "Lightning",
	},
	"kiln_mother": {
		"portrait": preload("res://assets/combat/virtual/kiln_mother.webp"),
		"faction": "ember", "signature": "Meltdown",
	},
	"furnace_king": {
		"portrait": preload("res://assets/combat/virtual/furnace_king.webp"),
		"faction": "ember", "signature": "Slag",
	},
	"undertow_broker": {
		"portrait": preload("res://assets/combat/virtual/undertow_broker.webp"),
		"faction": "tide", "signature": "Margin Call",
	},
	"tidal_exchange": {
		"portrait": preload("res://assets/combat/virtual/tidal_exchange.webp"),
		"faction": "tide", "signature": "Insider Trade",
	},
	"chief_surgeon": {
		"portrait": preload("res://assets/combat/virtual/chief_surgeon.webp"),
		"faction": "bloom", "signature": "Harvest",
	},
	"gene_saint": {
		"portrait": preload("res://assets/combat/virtual/gene_saint.webp"),
		"faction": "bloom", "signature": "Amputate",
	},
	"zero_prime": {
		"portrait": preload("res://assets/combat/virtual/zero_prime.webp"),
		"faction": "void", "signature": "Void Echo",
	},
	"the_absence": {
		"portrait": preload("res://assets/combat/virtual/the_absence.webp"),
		"faction": "void", "signature": "Annihilate",
	},
	"hive_overseer": {
		"portrait": preload("res://assets/combat/virtual/hive_overseer.webp"),
		"faction": "chrome", "signature": "Railshot",
	},
	"chrome_queen": {
		"portrait": preload("res://assets/combat/virtual/chrome_queen.webp"),
		"faction": "chrome", "signature": "Orbital Lance",
	},
	"dj_feedback": {
		"portrait": preload("res://assets/combat/virtual/dj_feedback.webp"),
		"faction": "noise", "signature": "Drop the Bass",
	},
	"the_broadcast": {
		"portrait": preload("res://assets/combat/virtual/the_broadcast.webp"),
		"faction": "noise", "signature": "Signal Crush",
	},
	"root_kernel": {
		"portrait": preload("res://assets/combat/virtual/root_kernel.webp"),
		"faction": "neutral", "signature": "Purge",
	},
	"last_mirror": {
		"portrait": preload("res://assets/combat/virtual/last_mirror.webp"),
		"faction": "void", "signature": "Collapse",
	},
	"kiln_heart": {
		"portrait": preload("res://assets/combat/virtual/kiln_heart.webp"),
		"faction": "ember", "signature": "Pour Slag",
	},
	"drowned_market": {
		"portrait": preload("res://assets/combat/virtual/drowned_market.webp"),
		"faction": "tide", "signature": "Margin Call",
	},
	"mother_vat": {
		"portrait": preload("res://assets/combat/virtual/mother_vat.webp"),
		"faction": "bloom", "signature": "Consume",
	},
	"zero_point": {
		"portrait": preload("res://assets/combat/virtual/zero_point.webp"),
		"faction": "void", "signature": "Delete",
	},
	"hive_throne": {
		"portrait": preload("res://assets/combat/virtual/hive_throne.webp"),
		"faction": "chrome", "signature": "Orbital Strike",
	},
	"dead_air": {
		"portrait": preload("res://assets/combat/virtual/dead_air.webp"),
		"faction": "noise", "signature": "Final Broadcast",
	},
}
