class_name Combat
extends RefCounted
## Pure combat rules. No Nodes and no rendering: the UI, tests and the bot all
## drive it through play_card()/end_turn() and read state plus the `events` log.
## Events hold only ids and numbers so identical seeds give identical logs.

enum Phase { PLAYER, ENEMY, WON, LOST }

const MAX_HAND := 10

var db: CardDB
var rng: GameRng
var player: Fighter
var enemies: Array = []
var units: Array = []
var draw_pile: Array = []
var hand: Array = []
var discard_pile: Array = []
var exhaust_pile: Array = []
var _played_once_per_turn: Array[CardInstance] = []
var energy := 0
var max_energy := 3
var hand_size := 5
var board_slots := 3
var turn := 0
var phase: Phase = Phase.PLAYER
var events: Array = []
var encounter_id := ""
## Talisman defs (dicts from data/talismans.json) active this combat.
var talismans: Array = []
## Per-talisman counters for "every N" triggers.
var talisman_counters: Dictionary = {}
## Subroutine (run perk) defs with triggers; they fire like talismans.
var perks: Array = []
## Firewall gained when combat starts (perks).
var start_ward := 0
var ward_retention := 0.0
var daemon_death_damage := 0
var _unit_counter := 0
var _enemy_counter := 0
## Difficulty modifiers from the encounter's act and RunState.combat_opts.
var enemy_hp_mult := 1.0
var enemy_might := 0
var enemy_dmg_mult := 1.0
## Extra HP (= extra turns) for every daemon, from rig ranks, implants and subroutines.
var daemon_hp := 0
## Multiplier on a daemon program's base HP (implant "daemon": {"hp_mult": x}), applied before daemon_hp.
var daemon_hp_mult := 1.0


## deck: Array of CardInstance (copied, not mutated). hp < 0 means full HP.
## opts (all optional): max_hp, talismans (Array of ids), perks (Array of perk dicts),
## start_ward, ward_retention, daemon_death_damage, enemy_hp_mult, enemy_might, enemy_dmg_mult, extra_energy, extra_hand, extra_slots,
## daemon_hp. Implants add their "daemon": {"hp": n} on top.
static func create(db_in: CardDB, deck: Array, encounter_id: String, rng_in: GameRng, hp: int = -1, opts: Dictionary = {}) -> Combat:
	var c := Combat.new()
	c.db = db_in
	c.rng = rng_in
	var p: Dictionary = db_in.balance.get("player", {})
	c.max_energy = int(p.get("max_energy", 3))
	c.hand_size = int(p.get("hand_size", 5))
	c.board_slots = int(db_in.balance.get("board_slots", 3)) + int(opts.get("extra_slots", 0))
	c.max_energy += int(opts.get("extra_energy", 0))
	c.hand_size += int(opts.get("extra_hand", 0))
	var max_hp := int(opts.get("max_hp", p.get("max_hp", 60)))
	c.enemy_might = int(opts.get("enemy_might", 0))
	c.enemy_dmg_mult = float(opts.get("enemy_dmg_mult", 1.0))
	c.daemon_hp = int(opts.get("daemon_hp", 0))
	for tid in opts.get("talismans", []):
		if db_in.talismans.has(tid):
			c.talismans.append(db_in.talismans[tid])
			c.daemon_hp += int(db_in.talismans[tid].get("daemon", {}).get("hp", 0))
			c.daemon_hp_mult *= float(db_in.talismans[tid].get("daemon", {}).get("hp_mult", 1.0))
	for pd in opts.get("perks", []):
		if not pd.get("triggers", []).is_empty():
			c.perks.append(pd)
	c.start_ward = int(opts.get("start_ward", 0))
	c.ward_retention = clampf(float(opts.get("ward_retention", 0.0)), 0.0, 1.0)
	c.daemon_death_damage = int(opts.get("daemon_death_damage", 0))
	c.player = Fighter.make("player", "You", max_hp)
	if hp > 0:
		c.player.hp = mini(hp, max_hp)
	c.encounter_id = encounter_id
	var enc: Dictionary = db_in.encounters.get(encounter_id, {})
	if enc.is_empty():
		push_error("Unknown encounter '%s'" % encounter_id)
	var act_hp_mult: Dictionary = db_in.balance.get("enemy_hp_mult_by_act", {})
	c.enemy_hp_mult = float(opts.get("enemy_hp_mult", 1.0)) * float(act_hp_mult.get(str(int(enc.get("act", 1))), 1.0))
	for eid in enc.get("enemies", []):
		c.enemies.append(c._make_enemy(str(eid)))
	c.draw_pile = deck.duplicate()
	for card in c.draw_pile:
		card.loops = 0
	return c


func _make_enemy(eid: String) -> Fighter:
	var idx := _enemy_counter
	_enemy_counter += 1
	var d: Dictionary = db.enemies.get(eid, {})
	if d.is_empty():
		push_error("Unknown enemy '%s'" % eid)
		return Fighter.make("e%d" % idx, eid, 1)
	var r: Array = d.get("hp", [10, 10])
	var hp_mult := enemy_hp_mult * float(d.get("hp_mult", 1.0))
	var hp := maxi(1, roundi(rng.range_i(int(r[0]), int(r[1])) * hp_mult))
	var f := Fighter.make("e%d" % idx, str(d.get("name", eid)), hp)
	if enemy_might > 0:
		f.add_status("might", enemy_might)
	for s in d.get("statuses", {}):
		f.add_status(s, int(d["statuses"][s]))
	f.def_id = eid
	f.dmg_mult = enemy_dmg_mult
	f.moves = d.get("moves", [])
	if d.get("random_start", false) and not f.moves.is_empty():
		f.move_idx = rng.range_i(0, f.moves.size() - 1)
	return f


# --- flow -------------------------------------------------------------------

func start() -> void:
	rng.shuffle(draw_pile)
	# Innate cards go on top so they are in the opening hand.
	var innate := draw_pile.filter(func(c: CardInstance) -> bool: return c.has_keyword("innate"))
	for card in innate:
		draw_pile.erase(card)
		draw_pile.append(card)
	emit("combat_start", {"enemies": enemies.map(func(e: Fighter) -> String: return e.def_id)})
	_start_player_turn()


func _start_player_turn() -> void:
	turn += 1
	phase = Phase.PLAYER
	_played_once_per_turn.clear()
	if player.status("fortify") <= 0 and rule_sum("keep_ward") <= 0:
		player.ward = ceili(player.ward * ward_retention)
	energy = maxi(max_energy - player.status("overcharge"), 0)
	player.statuses.erase("overcharge")
	emit("turn_start", {"turn": turn, "ward": player.ward})
	# Daemons run down: HP is the countdown, so a daemon with N HP lasts N rounds if left alone.
	for u in units.duplicate():
		u.hp -= 1
		if u.hp <= 0:
			units.erase(u)
			emit("expire", {"target": u.id})
			_daemon_closed(u)
		else:
			emit("uptime", {"target": u.id, "hp": u.hp})
	if turn == 1:
		# After the Ward reset, so start-of-combat Ward sticks for turn 1.
		if start_ward > 0:
			Effects.resolve(self, {"op": "ward", "amount": start_ward}, player, null)
		Talismans.fire(self, "combat_start")
	Statuses.on_turn_start(self, player)
	_check_end()
	if is_over():
		return
	draw(hand_size)
	Talismans.fire(self, "turn_start")


func can_play(hand_idx: int) -> bool:
	if phase != Phase.PLAYER or hand_idx < 0 or hand_idx >= hand.size():
		return false
	var card: CardInstance = hand[hand_idx]
	if card.has_keyword("unplayable") or card.cost() > energy or was_played_this_turn(card):
		return false
	if units.size() >= board_slots and _summons(card) and not _refreshes(card):
		return false
	return true


func was_played_this_turn(card: CardInstance) -> bool:
	return card in _played_once_per_turn


func needs_target(card: CardInstance) -> bool:
	return card.def.target == "enemy"


func needs_ally(card: CardInstance) -> bool:
	return card.def.target == "ally"


## target_idx is an index into `enemies`; -1 picks the first living enemy.
## For "ally" cards it indexes [you] + your daemons (0 or -1 = you).
func play_card(hand_idx: int, target_idx: int = -1) -> bool:
	if not can_play(hand_idx):
		return false
	var card: CardInstance = hand[hand_idx]
	var target: Fighter = null
	if needs_target(card):
		if target_idx < 0:
			target_idx = enemies.find(_first_living(enemies))
		if target_idx < 0 or target_idx >= enemies.size() or enemies[target_idx].is_dead():
			return false
		target = enemies[target_idx]
	if needs_ally(card):
		var allies: Array = [player] + units
		if target_idx >= allies.size():
			return false
		target = allies[maxi(target_idx, 0)]
	hand.remove_at(hand_idx)
	energy -= card.cost()
	if card.has_keyword("once_per_turn"):
		_played_once_per_turn.append(card)
	emit("play", {"card": card.key(), "target": target.id if target != null else ""})
	for e in card.effects():
		if is_over():
			break
		if target != null and target.is_dead():
			target = _first_living(enemies) if needs_target(card) else target
		Effects.resolve(self, e, player, target)
	if card.has_loop():
		card.loops += 1 + rule_sum("loop_bonus")
		emit("loop", {"card": card.key(), "loops": card.loops})
		if not is_over():
			Talismans.fire(self, "loop", {"card": card, "target": target})
	if card.def.type == "power" or card.has_keyword("exhaust"):
		exhaust_pile.append(card)
	else:
		discard_pile.append(card)
	if not is_over():
		Talismans.fire(self, "card_played", {"card": card, "target": target})
	_check_end()
	return true


func end_turn() -> void:
	if phase != Phase.PLAYER:
		return
	Talismans.fire(self, "turn_end")
	if is_over():
		return
	Statuses.on_turn_end(self, player)
	for u in units:
		Statuses.on_turn_end(self, u)
	var kept: Array = []
	for card in hand:
		if card.has_keyword("retain"):
			kept.append(card)
		elif card.has_keyword("ethereal"):
			exhaust_pile.append(card)
		else:
			discard_pile.append(card)
	hand = kept
	phase = Phase.ENEMY
	emit("enemy_phase")
	for en in enemies:
		if en.is_dead():
			continue
		if en.status("fortify") <= 0:
			en.ward = 0
		Statuses.on_turn_start(self, en)
		_check_end()
		if is_over():
			return
		if en.is_dead():
			continue
		if en.status("stall") > 0:
			# Lagged: skips this move; the same intent waits for next turn.
			en.add_status("stall", -1)
			emit("enemy_move", {"source": en.id, "move": "Lagged", "stalled": true})
		else:
			var mv: Dictionary = en.current_move()
			emit("enemy_move", {"source": en.id, "move": mv.get("name", "")})
			for e in mv.get("effects", []):
				if is_over():
					break
				Effects.resolve(self, e, en, player)
			en.advance_move()
		Statuses.on_turn_end(self, en)
		_check_end()
		if is_over():
			return
	_start_player_turn()


func is_over() -> bool:
	return phase == Phase.WON or phase == Phase.LOST


func _check_end() -> void:
	if is_over():
		return
	if player.is_dead():
		phase = Phase.LOST
		emit("combat_end", {"won": false, "turn": turn})
	elif _first_living(enemies) == null:
		phase = Phase.WON
		emit("combat_end", {"won": true, "turn": turn})


## Testing shortcut. Skip enemy death triggers but finish through the normal victory path.
func cheat_win() -> void:
	if is_over() or player.is_dead():
		return
	for enemy in living(enemies):
		enemy.hp = 0
		emit("death", {"target": enemy.id})
	_check_end()


# --- primitives used by Effects / Statuses ------------------------------------

func emit(t: String, data: Dictionary = {}) -> void:
	data["t"] = t
	events.append(data)


func attack(src: Fighter, t: Fighter, base: int) -> int:
	var amount := Statuses.modify_attack(base, src, t)
	if t == player and src != null and enemies.has(src):
		amount = maxi(amount - rule_sum("guard"), 0)
	var dealt := deal_damage(t, amount, src.id if src != null else "")
	# Thorns: being attacked hurts the attacker (even if Ward absorbed the hit).
	var thorns := t.status("thorns") + (rule_sum("thorns") if t == player else 0)
	if thorns > 0 and src != null and not src.is_dead():
		deal_damage(src, thorns, t.id, "thorns")
	return dealt


func deal_damage(t: Fighter, amount: int, source_id: String = "", kind: String = "attack") -> int:
	if t.is_dead() or amount <= 0:
		return 0
	# A daemon's HP is turns, not toughness: any hit costs it 1. Only Purge takes more.
	if units.has(t) and kind != "purge":
		amount = 1
	var blocked := mini(t.ward, amount)
	t.ward -= blocked
	var dealt := amount - blocked
	t.hp = maxi(t.hp - dealt, 0)
	emit("damage", {"target": t.id, "amount": dealt, "blocked": blocked, "source": source_id, "kind": kind, "hp": t.hp, "ward": t.ward})
	if t.is_dead():
		emit("death", {"target": t.id})
		if units.has(t):
			units.erase(t)
			_daemon_closed(t)
		elif enemies.has(t) and phase == Phase.PLAYER:
			Talismans.fire(self, "kill", {"target": t})
	return dealt


## Crashes a running daemon on purpose (op "sacrifice"): its rule ends now.
func crash_daemon(u: Fighter) -> void:
	if not units.has(u):
		return
	units.erase(u)
	emit("expire", {"target": u.id, "crashed": true})
	_daemon_closed(u)


## A daemon left the board (crashed or ran out): Hive Link's blast.
func _daemon_closed(u: Fighter) -> void:
	if not is_over():
		Talismans.fire(self, "daemon_closed", {"daemon": u})
		_check_end()
	if daemon_death_damage > 0 and not is_over():
		emit("daemon_explosion", {"target": u.id})
		for enemy in living(enemies):
			deal_damage(enemy, daemon_death_damage, u.id, "daemon_explosion")
		_check_end()


func draw(n: int) -> void:
	var reshuffles := 0
	for i in n:
		if hand.size() >= MAX_HAND:
			break
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				break
			draw_pile = discard_pile
			discard_pile = []
			rng.shuffle(draw_pile)
			emit("reshuffle")
			reshuffles += 1
		var card: CardInstance = draw_pile.pop_back()
		hand.append(card)
		emit("draw", {"card": card.key()})
	for i in reshuffles:
		if not is_over():
			Talismans.fire(self, "reshuffle")


## Runs a daemon: a rule change that lasts while it has HP. It loses 1 HP at the start of each
## of your turns and 1 per hit taken (Purge takes more). Running one that is already up
## (same name) tops its HP back up instead of taking a slot.
func summon(unit_name: String, hp: int, rule: Dictionary = {}) -> bool:
	hp = maxi(ceili(hp * daemon_hp_mult - 0.001) + daemon_hp, 1)
	for u in units:
		if u.name == unit_name:
			u.max_hp = maxi(u.max_hp, hp)
			u.hp = maxi(u.hp, hp)
			u.rule = rule
			emit("refresh", {"target": u.id, "hp": u.hp})
			return true
	if units.size() >= board_slots:
		return false
	var u := Fighter.make("u%d" % _unit_counter, unit_name, hp)
	_unit_counter += 1
	u.rule = rule
	units.append(u)
	emit("summon", {"target": u.id, "name": unit_name, "hp": hp})
	return true


## Sum of a rule flag over the daemons that are running (true counts as 1).
func rule_sum(flag: String) -> int:
	var total := 0
	for u in units:
		total += int(u.rule.get("flags", {}).get(flag, 0))
	return total + Talismans.flag_sum(self, flag)


## Enemy-side summon (op "spawn"). Max 5 enemies alive.
func spawn(enemy_id: String) -> bool:
	if living(enemies).size() >= 5 or not db.enemies.has(enemy_id):
		return false
	var f := _make_enemy(enemy_id)
	enemies.append(f)
	emit("spawn", {"target": f.id, "enemy": enemy_id})
	return true


## Counts plays per card id this combat (feeds card mastery).
func play_counts() -> Dictionary:
	var out := {}
	for e in events:
		if e["t"] == "play":
			var id := str(e["card"]).trim_suffix("+")
			out[id] = int(out.get(id, 0)) + 1
	return out


# --- queries ------------------------------------------------------------------

func is_friendly(f: Fighter) -> bool:
	return f == player or units.has(f)


func living(arr: Array) -> Array:
	return arr.filter(func(f: Fighter) -> bool: return not f.is_dead())


func _first_living(arr: Array) -> Fighter:
	for f in arr:
		if not f.is_dead():
			return f
	return null


func _summons(card: CardInstance) -> bool:
	for e in card.effects():
		if e.get("op", "") == "summon":
			return true
	return false


## True if every daemon the card runs is already up (so it needs no free slot).
func _refreshes(card: CardInstance) -> bool:
	for e in card.effects():
		if e.get("op", "") == "summon" and not units.any(func(u: Fighter) -> bool: return u.name == str(e.get("name", "Unit"))):
			return false
	return true


## Damage the enemy's next move would deal to the player (ignores Ward). For UI + bot.
func intent_damage(en: Fighter) -> int:
	var total := 0
	if en.status("stall") > 0:
		return 0
	for e in en.current_move().get("effects", []):
		if e.get("op", "") == "damage":
			if str(e.get("to", "")) == "daemon" or (str(e.get("to", "")) == "front" and not units.is_empty()):
				continue
			total += hit_on_player(int(e.get("amount", 0)), en) * int(e.get("hits", 1))
	return total


## One enemy hit on the player after statuses and Guard daemons.
func hit_on_player(base: int, en: Fighter) -> int:
	return maxi(Statuses.modify_attack(base, en, player) - rule_sum("guard"), 0)


func incoming_damage() -> int:
	var total := 0
	for en in living(enemies):
		total += intent_damage(en)
	return total


## One-line state dump for debugging, sim logs and test failure messages.
func summary() -> String:
	var parts: Array[String] = ["T%d %s e%d" % [turn, Phase.keys()[phase], energy], player.summary()]
	for f in units + enemies:
		parts.append(f.summary())
	return " | ".join(parts)
