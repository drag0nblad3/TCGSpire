class_name BossPresentation
extends RefCounted
## Display-only portraits, entrance accents and the existing move to spotlight.
## Combat and Intents remain the source of all effects and damage numbers.

const PROFILES := {
	"torch_choir": {
		"portrait": preload("res://assets/combat/virtual/torch_choir.webp"),
		"faction": "ember", "signature": "Crescendo",
	},
	"slag_matriarch": {
		"portrait": preload("res://assets/combat/virtual/slag_matriarch.webp"),
		"faction": "ember", "signature": "Brand Line",
	},
	"pyre_saint": {
		"portrait": preload("res://assets/combat/virtual/pyre_saint.webp"),
		"faction": "ember", "signature": "Pillar of Fire",
	},
	"ledger_kraken": {
		"portrait": preload("res://assets/combat/virtual/ledger_kraken.webp"),
		"faction": "tide", "signature": "Squeeze",
	},
	"margin_leviathan": {
		"portrait": preload("res://assets/combat/virtual/margin_leviathan.webp"),
		"faction": "tide", "signature": "Call an Agent",
	},
	"clearing_house": {
		"portrait": preload("res://assets/combat/virtual/clearing_house.webp"),
		"faction": "tide", "signature": "Default",
	},
	"graft_mother": {
		"portrait": preload("res://assets/combat/virtual/graft_mother.webp"),
		"faction": "bloom", "signature": "Pollen",
	},
	"spore_cathedral": {
		"portrait": preload("res://assets/combat/virtual/spore_cathedral.webp"),
		"faction": "bloom", "signature": "Crush",
	},
	"chimera_prime": {
		"portrait": preload("res://assets/combat/virtual/chimera_prime.webp"),
		"faction": "bloom", "signature": "Brood",
	},
	"hollow_saint": {
		"portrait": preload("res://assets/combat/virtual/hollow_saint.webp"),
		"faction": "void", "signature": "Silence",
	},
	"null_choir": {
		"portrait": preload("res://assets/combat/virtual/null_choir.webp"),
		"faction": "void", "signature": "Annul",
	},
	"event_collapse": {
		"portrait": preload("res://assets/combat/virtual/event_collapse.webp"),
		"faction": "void", "signature": "Delete",
	},
	"drill_sergeant": {
		"portrait": preload("res://assets/combat/virtual/drill_sergeant.webp"),
		"faction": "chrome", "signature": "Railshot",
	},
	"siege_foundry": {
		"portrait": preload("res://assets/combat/virtual/siege_foundry.webp"),
		"faction": "chrome", "signature": "Rivet Storm",
	},
	"orbital_command": {
		"portrait": preload("res://assets/combat/virtual/orbital_command.webp"),
		"faction": "chrome", "signature": "Kill Order",
	},
	"static_king": {
		"portrait": preload("res://assets/combat/virtual/static_king.webp"),
		"faction": "noise", "signature": "Air Horn",
	},
	"mixing_desk": {
		"portrait": preload("res://assets/combat/virtual/mixing_desk.webp"),
		"faction": "noise", "signature": "Encore",
	},
	"signal_apocalypse": {
		"portrait": preload("res://assets/combat/virtual/signal_apocalypse.webp"),
		"faction": "noise", "signature": "Overload",
	},

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
