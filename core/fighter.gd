class_name Fighter
extends RefCounted
## Anything with HP in combat: the player, an enemy, or a unit on the player's board.

var id := ""
var name := ""
var hp := 1
var max_hp := 1
var ward := 0
var statuses: Dictionary = {}
## Daemons only: turns left before it closes (ticks at the start of your turn), and its
## rule change while it runs (see DaemonRules).
var uptime := 0
var rule: Dictionary = {}
## Enemies only: looping move list [{name, effects}] from data/enemies.
var moves: Array = []
var move_idx := 0
var def_id := ""
## Attack multiplier (heat scaling for enemies), applied after Boost and Weakened.
var dmg_mult := 1.0


static func make(id_in: String, name_in: String, hp_in: int) -> Fighter:
	var f := Fighter.new()
	f.id = id_in
	f.name = name_in
	f.hp = hp_in
	f.max_hp = hp_in
	return f


func is_dead() -> bool:
	return hp <= 0


func status(n: String) -> int:
	return int(statuses.get(n, 0))


func add_status(n: String, stacks: int) -> void:
	var v := status(n) + stacks
	if v <= 0:
		statuses.erase(n)
	else:
		statuses[n] = v


func current_move() -> Dictionary:
	if moves.is_empty():
		return {}
	return moves[move_idx % moves.size()]


func advance_move() -> void:
	move_idx += 1


## Compact one-line state, handy in test failures and sim logs.
func summary() -> String:
	var s := "%s %d/%d" % [id, hp, max_hp]
	if ward > 0:
		s += " w%d" % ward
	if uptime > 0:
		s += " up%d" % uptime
	for k in statuses:
		s += " %s%d" % [k, statuses[k]]
	return s
