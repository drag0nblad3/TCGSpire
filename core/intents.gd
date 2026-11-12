class_name Intents
extends RefCounted
## Turns an enemy's next move into a short list of telegraph icons for the UI:
##   [{"kind": "attack", "value": 7, "hits": 2, "aoe": false}, {"kind": "ward", "value": 6}, ...]
## Kinds: attack, purge (hits your front daemon), ward, buff, debuff, heal, summon, curse (adds cards), unknown.
## Pure data, no Nodes: the UI draws the icons, tests check the classification.

const DESC := {
	"attack": "Attacks you. The number is damage per hit after Boost, Throttled and Exposed.",
	"purge": "Purge: hits your front daemon. Crashing a daemon ends its rule early. Does nothing if no daemon is running.",
	"ward": "Raises its Firewall, which absorbs damage until its next turn.",
	"buff": "Upgrades itself (for example Boost or Feedback).",
	"debuff": "Infects you with a harmful status.",
	"heal": "Repairs its HP.",
	"summon": "Calls more sentries into the fight.",
	"curse": "Uploads malware into your deck or hand.",
	"unknown": "Does something unusual. Tap the enemy to read the move.",
}


static func of(c: Combat, en: Fighter) -> Array:
	var out: Array = []
	var by_kind := {}
	for e in en.current_move().get("effects", []):
		var op := str(e.get("op", ""))
		var to := str(e.get("to", ""))
		var item := {}
		match op:
			"damage", "damage_per_ward", "damage_per_status", "lose_hp":
				var base := int(e.get("amount", 0))
				if op == "damage_per_ward":
					base = int(en.ward * float(e.get("mult", 1.0)))
				elif op == "damage_per_status":
					base = int(e.get("base", 0)) + int(en.status(str(e.get("status", ""))) * float(e.get("mult", 1.0)))
				var per := base if op == "lose_hp" else Statuses.modify_attack(base, en, c.player)
				item = {"kind": "attack", "value": per, "hits": int(e.get("hits", 1)), "aoe": to == "all_enemies"}
				if to == "daemon":
					item = {"kind": "purge", "value": per}
			"ward":
				item = {"kind": "ward", "value": int(e.get("amount", 0))}
			"heal":
				item = {"kind": "heal", "value": int(e.get("amount", 0))}
			"apply":
				var debuff: bool = Statuses.DEFS.get(str(e.get("status", "")), {}).get("debuff", false)
				var on_self := to in ["self", "all_allies"]
				item = {"kind": "debuff" if (debuff and not on_self) else "buff", "value": int(e.get("stacks", 1)), "status": str(e.get("status", ""))}
			"spawn", "summon":
				item = {"kind": "summon", "value": 0}
			"add_card":
				item = {"kind": "curse", "value": maxi(int(e.get("amount", 1)), 1)}
			_:
				item = {"kind": "unknown", "value": 0}
		# Merge repeats of the same kind (two attack effects -> one icon, summed).
		var k: String = item["kind"]
		if by_kind.has(k) and k != "attack":
			by_kind[k]["value"] += item["value"]
			continue
		if by_kind.has(k) and k == "attack" and by_kind[k]["value"] == item["value"]:
			by_kind[k]["hits"] += item["hits"]
			continue
		if not by_kind.has(k):
			by_kind[k] = item
		out.append(item)
	return out


## Plain-language lines for the inspect popup: "Move name: Deal 6 damage. Apply 1 Weaken."
static func explain(en: Fighter) -> String:
	var mv := en.current_move()
	var parts: Array[String] = []
	for e in mv.get("effects", []):
		parts.append(Effects.describe(e).replace(" to ALL enemies", " to you and your units"))
	return "%s: %s" % [mv.get("name", "?"), " ".join(parts)]
