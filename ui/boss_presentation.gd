class_name BossPresentation
extends RefCounted
## Display-only portraits, entrance accents and the existing move to spotlight.
## Combat and Intents remain the source of all effects and damage numbers.

const PROFILES := {
	"hollow_monarch": {
		"portrait": preload("res://assets/combat/hollow_monarch.svg"),
		"faction": "void", "signature": "Root Privilege",
	},
	"cinder_colossus": {
		"portrait": preload("res://assets/combat/cinder_colossus.svg"),
		"faction": "ember", "signature": "Stomp",
	},
	"the_unwritten": {
		"portrait": preload("res://assets/combat/the_unwritten.svg"),
		"faction": "void", "signature": "Final Commit",
	},
	"storm_regent": {
		"portrait": preload("res://assets/combat/storm_regent.svg"),
		"faction": "tide", "signature": "Lightning",
	},
	"kiln_mother": {
		"portrait": preload("res://assets/combat/kiln_mother.svg"),
		"faction": "ember", "signature": "Meltdown",
	},
	"furnace_king": {
		"portrait": preload("res://assets/combat/furnace_king.svg"),
		"faction": "ember", "signature": "Slag",
	},
	"undertow_broker": {
		"portrait": preload("res://assets/combat/undertow_broker.svg"),
		"faction": "tide", "signature": "Margin Call",
	},
	"tidal_exchange": {
		"portrait": preload("res://assets/combat/tidal_exchange.svg"),
		"faction": "tide", "signature": "Insider Trade",
	},
	"chief_surgeon": {
		"portrait": preload("res://assets/combat/chief_surgeon.svg"),
		"faction": "bloom", "signature": "Harvest",
	},
	"gene_saint": {
		"portrait": preload("res://assets/combat/gene_saint.svg"),
		"faction": "bloom", "signature": "Amputate",
	},
	"zero_prime": {
		"portrait": preload("res://assets/combat/zero_prime.svg"),
		"faction": "void", "signature": "Void Echo",
	},
	"the_absence": {
		"portrait": preload("res://assets/combat/the_absence.svg"),
		"faction": "void", "signature": "Annihilate",
	},
	"hive_overseer": {
		"portrait": preload("res://assets/combat/hive_overseer.svg"),
		"faction": "chrome", "signature": "Railshot",
	},
	"chrome_queen": {
		"portrait": preload("res://assets/combat/chrome_queen.svg"),
		"faction": "chrome", "signature": "Orbital Lance",
	},
	"dj_feedback": {
		"portrait": preload("res://assets/combat/dj_feedback.svg"),
		"faction": "noise", "signature": "Drop the Bass",
	},
	"the_broadcast": {
		"portrait": preload("res://assets/combat/the_broadcast.svg"),
		"faction": "noise", "signature": "Signal Crush",
	},
	"root_kernel": {
		"portrait": preload("res://assets/combat/root_kernel.svg"),
		"faction": "neutral", "signature": "Purge",
	},
	"last_mirror": {
		"portrait": preload("res://assets/combat/last_mirror.svg"),
		"faction": "void", "signature": "Collapse",
	},
	"kiln_heart": {
		"portrait": preload("res://assets/combat/kiln_heart.svg"),
		"faction": "ember", "signature": "Pour Slag",
	},
	"drowned_market": {
		"portrait": preload("res://assets/combat/drowned_market.svg"),
		"faction": "tide", "signature": "Margin Call",
	},
	"mother_vat": {
		"portrait": preload("res://assets/combat/mother_vat.svg"),
		"faction": "bloom", "signature": "Consume",
	},
	"zero_point": {
		"portrait": preload("res://assets/combat/zero_point.svg"),
		"faction": "void", "signature": "Delete",
	},
	"hive_throne": {
		"portrait": preload("res://assets/combat/hive_throne.svg"),
		"faction": "chrome", "signature": "Orbital Strike",
	},
	"dead_air": {
		"portrait": preload("res://assets/combat/dead_air.svg"),
		"faction": "noise", "signature": "Final Broadcast",
	},
}
