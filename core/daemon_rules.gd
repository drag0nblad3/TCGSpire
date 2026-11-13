class_name DaemonRules
extends RefCounted
## A daemon is a temporary rule change on the player's board. The "summon" op carries
##   {"op": "summon", "name", "hp", "rule": {"flags": {FLAG: n}, "triggers": [...]}}
## flags are passive rule changes (summed over living daemons, see Combat.rule_sum);
## triggers use the implant format (Talismans.TRIGGERS) with the player as source.
## HP is the countdown: -1 at the start of each of your turns, -1 per hit taken, and Purge
## moves take their number. The rule ends at 0 HP.

## flag -> rules text ("%d" takes the flag's number).
const FLAGS := {
	"burn_no_decay": "Virus on enemies doesn't decay.",
	"regen_no_decay": "Your Patch doesn't decay.",
	"keep_ward": "Your Firewall isn't cleared at the start of your turn.",
	"guard": "Enemy attacks deal %d less damage to you per hit.",
	"attack_bonus": "Your attacks deal +%d damage.",
	"ward_bonus": "Whenever you gain Firewall, gain %d more.",
	"thorns": "Enemies that attack you take %d damage.",
	"burn_bonus": "Whenever you apply Virus to an enemy, apply %d more.",
	"regen_bonus": "Whenever you or a daemon gain Patch, gain %d more.",
	"debuff_bonus": "Harmful statuses you apply to enemies get +%d.",
}

## Rough worth of one turn of each flag (per point), for the bots.
const FLAG_VALUE := {
	"burn_no_decay": 2.5, "regen_no_decay": 1.5, "keep_ward": 3.5, "guard": 2.2,
	"attack_bonus": 2.5, "ward_bonus": 1.6, "thorns": 1.2, "burn_bonus": 2.0,
	"regen_bonus": 1.5, "debuff_bonus": 1.5,
}


static func describe(rule: Dictionary) -> String:
	var parts: Array[String] = []
	var flags: Dictionary = rule.get("flags", {})
	for k in flags:
		var txt: String = FLAGS.get(k, "?%s?" % k)
		parts.append(txt % int(flags[k]) if "%d" in txt else txt)
	if not rule.get("triggers", []).is_empty():
		parts.append(Talismans.describe({"triggers": rule["triggers"]}))
	return " ".join(parts)


static func validate(rule: Dictionary, where: String) -> Array[String]:
	var errs: Array[String] = []
	for k in rule:
		if k not in ["flags", "triggers"]:
			errs.append("%s: rule has unknown key '%s'" % [where, k])
	for k in rule.get("flags", {}):
		if not FLAGS.has(k):
			errs.append("%s: unknown rule flag '%s'" % [where, k])
	for trig in rule.get("triggers", []):
		if trig.get("on", "") not in Talismans.TRIGGERS or trig.get("on", "") == "combat_start":
			errs.append("%s: bad rule trigger '%s'" % [where, trig.get("on", "")])
		for e in trig.get("effects", []):
			errs.append_array(Effects.validate(e, where))
	return errs


## Static worth of a summon effect (no combat state): rule value per turn x turns (HP).
## Later turns count for less: the fight may end or the daemon may be hit.
static func value(e: Dictionary, hp_bonus: int = 0) -> float:
	var hp := float(maxi(int(e.get("hp", 1)) + hp_bonus, 1))
	var up := minf(hp, 3.0) + maxf(hp - 3.0, 0.0) * 0.5
	var rule: Dictionary = e.get("rule", {})
	var v := 0.0
	var flags: Dictionary = rule.get("flags", {})
	for k in flags:
		v += float(FLAG_VALUE.get(k, 1.0)) * float(flags[k]) * up
	for trig in rule.get("triggers", []):
		var per := 0.0
		for fx in trig.get("effects", []):
			per += _effect_value(fx)
		var times := up
		match str(trig.get("on", "")):
			"turn_start":
				times = up - 1.0
			"card_played":
				times = up * (1.3 if trig.has("card_type") else 3.0)
			"kill":
				times = 1.0
		v += per * times / float(trig.get("every", 1))
	return v


static func _effect_value(fx: Dictionary) -> float:
	var n := float(fx.get("amount", 0))
	match str(fx.get("op", "")):
		"damage":
			return n * float(fx.get("hits", 1)) * (1.8 if fx.get("to", "") == "all_enemies" else 1.0)
		"damage_per_ward":
			return 6.0 * float(fx.get("mult", 1.0))
		"ward":
			return n * 0.85
		"heal":
			return n * 0.8
		"apply":
			return float(fx.get("stacks", 1)) * 1.8
		"draw":
			return n * 3.5
		"energy":
			return n * 4.5
		"summon":
			return value(fx) * 0.8
	return 1.0
