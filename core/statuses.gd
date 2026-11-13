class_name Statuses
extends RefCounted
## Status definitions and their hooks. To add a status: add it to DEFS, then
## handle it in the hook(s) below, then add a test in tests/test_effects.gd.

const DEFS := {
	"burn": {"debuff": true, "desc": "At the start of your turn, take damage equal to stacks, then lose 1 stack."},
	"brittle": {"debuff": true, "desc": "Takes 50% more attack damage. Loses 1 stack at end of turn."},
	"weaken": {"debuff": true, "desc": "Deals 25% less attack damage. Loses 1 stack at end of turn."},
	"might": {"debuff": false, "desc": "Attacks deal +1 damage per stack."},
	"overcharge": {"debuff": true, "desc": "Start next turn with 1 less RAM per stack."},
	"thorns": {"debuff": false, "desc": "When attacked, deal damage equal to stacks back to the attacker."},
	"regen": {"debuff": false, "desc": "Repair HP equal to stacks at end of turn, then lose 1 stack. On a daemon it wins back turns."},
	"fortify": {"debuff": false, "desc": "Your Firewall stays up at the start of your turn."},
	"frail": {"debuff": true, "desc": "Gain 25% less Firewall. Lose 1 stack at end of turn."},
	"charge": {"debuff": false, "desc": "Stored power that some programs spend for big effects."},
	"stall": {"debuff": true, "desc": "Skips its next move, and that intent waits a turn. Never more than 1 stack."},
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
		dmg *= attacker.dmg_mult
	if defender != null and defender.status("brittle") > 0:
		dmg *= 1.5
	return maxi(int(floor(dmg)), 0)


static func on_turn_start(c: Combat, f: Fighter) -> void:
	var burn := f.status("burn")
	if burn > 0:
		c.deal_damage(f, burn, "", "burn")
		if not (c.enemies.has(f) and c.rule_sum("burn_no_decay") > 0):
			f.add_status("burn", -1)


static func on_turn_end(c: Combat, f: Fighter) -> void:
	var regen := f.status("regen")
	if regen > 0 and not f.is_dead():
		var before := f.hp
		f.hp = mini(f.max_hp, f.hp + regen)
		c.emit("heal", {"target": f.id, "amount": f.hp - before, "hp": f.hp})
		if not (f == c.player and c.rule_sum("regen_no_decay") > 0):
			f.add_status("regen", -1)
	for s in DECAYING:
		if f.status(s) > 0:
			f.add_status(s, -1)
