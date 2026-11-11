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
	"thorns": {"debuff": false, "desc": "When attacked, deal damage equal to stacks to the attacker."},
	"regen": {"debuff": false, "desc": "Heal stacks at end of turn, then lose 1."},
	"fortify": {"debuff": false, "desc": "Ward is not removed at the start of turn."},
	"frail": {"debuff": true, "desc": "Gain 25% less Ward. Loses 1 at end of turn."},
	"charge": {"debuff": false, "desc": "Stored power. Some cards spend it for big effects."},
	"echo": {"debuff": false, "desc": "Your next card's effects happen twice. Uses 1 stack."},
}

const DECAYING := ["brittle", "weaken", "frail"]


static func debuffs(f: Fighter) -> Array:
	return f.statuses.keys().filter(func(k: String) -> bool: return DEFS.get(k, {}).get("debuff", false))


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


static func on_turn_end(c: Combat, f: Fighter) -> void:
	var regen := f.status("regen")
	if regen > 0 and not f.is_dead():
		var before := f.hp
		f.hp = mini(f.max_hp, f.hp + regen)
		c.emit("heal", {"target": f.id, "amount": f.hp - before, "hp": f.hp})
		f.add_status("regen", -1)
	for s in DECAYING:
		if f.status(s) > 0:
			f.add_status(s, -1)
