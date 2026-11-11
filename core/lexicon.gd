class_name Lexicon
extends RefCounted
## Player-facing names for rules terms. Data ids stay stable ("burn", "ward",
## "exhaust") so saves, JSON and tests never change; only what players read does.
## The setting is a cyberpunk hacking sim: you are a Ghost running programs
## (cards) on your rig's RAM against corporate sentries.

const TERMS := {
	"ward": "Firewall",
	"energy": "RAM",
	"unit": "daemon",
	"units": "daemons",
	"talisman": "implant",
	"talismans": "implants",
	"curse": "malware",
}

const STATUS := {
	"burn": "Virus",
	"brittle": "Exposed",
	"weaken": "Throttled",
	"might": "Boost",
	"overcharge": "Overheat",
	"thorns": "Feedback",
	"regen": "Patch",
	"fortify": "Hardened",
	"frail": "Fragmented",
	"charge": "Buffer",
	"echo": "Loop",
}

const KEYWORD := {
	"exhaust": "Wipe",
	"retain": "Cache",
	"unplayable": "Locked",
	"innate": "Preload",
	"ethereal": "Volatile",
}

const FACTION := {"neutral": "Street", "ember": "Burner", "tide": "Flux", "bloom": "Wetware", "void": "Null", "chrome": "Chrome", "noise": "Static"}

const TYPE := {"attack": "Exploit", "skill": "Script", "unit": "Daemon", "power": "Rootkit"}


static func term(k: String) -> String:
	return str(TERMS.get(k, k))


static func status(id: String) -> String:
	return str(STATUS.get(id, id.capitalize()))


static func keyword(id: String) -> String:
	return str(KEYWORD.get(id, id.capitalize()))


static func faction(id: String) -> String:
	return str(FACTION.get(id, id.capitalize()))


static func type_name(id: String) -> String:
	return str(TYPE.get(id, id.capitalize()))


## Display name for a card id (falls back to the id).
static func card_name(id: String) -> String:
	var c: CardDef = CardDB.shared().card(id)
	return c.name if c != null else id.capitalize()


static func enemy_name(id: String) -> String:
	return str(CardDB.shared().enemies.get(id, {}).get("name", id.capitalize()))
