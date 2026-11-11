class_name Statuses
extends RefCounted
## Status definitions and their hooks. To add a status: add it to DEFS, then
## handle it in the hook(s) below, then add a test in tests/test_effects.gd.

const DEFS := {
	"burn": {"debuff": true, "desc": "Takes damage equal to stacks at turn start, then loses 1."},
	"brittle": {"debuff": true, "desc": "Takes 50% more attack damage. Loses 1 at end of turn."},
	"weaken": {"debuff": true, "desc": "Deals 25% less attack damage. Loses 1 at end of turn."},
	"might": {"debuff": false, "desc": "Attacks deal +1 damage per stack."},
	"overcharge": {"debuff": true, "desc": "Start next turn with 1 less energy per stack."},
}

const DECAYING := ["brittle", "weaken"]


static func is_known(n: String) -> bool:
	return DEFS.has(n)


static func modify_attack(base: int, attacker: Fighter, defender: Fighter) -> int:
	var dmg := float(base)
	if attacker != null:
		dmg += attacker.status("might")
		if attacker.status("weaken") > 0:
			dmg *= 0.75
	if defender != null and defender.status("brittle") > 0:
		dmg *= 1.5
	return maxi(int(floor(dmg)), 0)


static func on_turn_start(c: Combat, f: Fighter) -> void:
	var burn := f.status("burn")
	if burn > 0:
		c.deal_damage(f, burn, "", "burn")
		f.add_status("burn", -1)


static func on_turn_end(_c: Combat, f: Fighter) -> void:
	for s in DECAYING:
		if f.status(s) > 0:
			f.add_status(s, -1)
