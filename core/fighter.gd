class_name Fighter
extends RefCounted
## Anything with HP in combat: the player, an enemy, or a unit on the player's board.

var id := ""
var name := ""
var hp := 1
var max_hp := 1
var ward := 0
var statuses: Dictionary = {}
## Daemons only: the rule change it enforces while it runs (see DaemonRules). A daemon's
## HP is its countdown: it loses 1 at the start of each of your turns.
var rule: Dictionary = {}
## Enemies only: looping move list [{name, effects}] from data/enemies.
var moves: Array = []
var move_idx := 0
var def_id := ""
## Enemies only: intent kinds (Intents) cancelled for its next move by an Interrupt.
var interrupted: Array = []
## Attack multiplier (heat scaling for enemies), applied after Boost and Weakened.
var dmg_mult := 1.0
## Enemies only: boss rules from the enemy def ("rules", see BossRules) and their live counters.
var rules: Dictionary = {}
var state: Dictionary = {}
## A one-off move that replaces the next move from the list (Restore, a low-tide move).
var override: Dictionary = {}
## Extra effects stapled in front of the next move (a full heat gauge venting).
var bonus: Array = []
var bonus_name := ""
## True for enemies called in mid-fight by "spawn" (a Devour move eats these).
var spawned := false
## Enemies only: joined the fight as your turn ended or during the enemy turn (spawned, hatched,
## restored). It sits out that enemy turn and acts from the next one.
var arrived := false


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
	var mv: Dictionary = override
	if mv.is_empty() and not moves.is_empty():
		mv = moves[move_idx % moves.size()]
	if bonus.is_empty():
		return mv
	return {"name": "%s + %s" % [bonus_name, mv.get("name", "")], "effects": bonus + mv.get("effects", [])}


## A one-off override is used up without moving through the list.
func advance_move() -> void:
	bonus = []
	if not override.is_empty():
		override = {}
	else:
		move_idx += 1


## Compact one-line state, handy in test failures and sim logs.
func summary() -> String:
	var s := "%s %d/%d" % [id, hp, max_hp]
	if ward > 0:
		s += " w%d" % ward
	for k in statuses:
		s += " %s%d" % [k, statuses[k]]
	return s
