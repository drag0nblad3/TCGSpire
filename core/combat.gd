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
var played_ids: Array = []
var played_types: Array = []
var energy := 0
## X cost: the RAM the program being run spent (0 for fixed-cost programs).
var x_spent := 0
## Cards the last Dump discarded (effects with "per": "dumped").
var last_dumped := 0
## Cards the player picked for this play's Dump / recover (others are picked for them).
var picks: Array = []
var max_energy := 3
var hand_size := 5
## True while "hp_lost" rules resolve (they never retrigger themselves).
var _hp_lost_firing := false
var board_slots := 3
## True from End turn until the enemy phase starts: enemies that join then (Spore hatch) wait a turn.
var _ending_turn := false
var turn := 0
var phase: Phase = Phase.PLAYER
var events: Array = []
var encounter_id := ""
## Talisman defs (dicts from data/talismans.json) active this combat.
var talismans: Array = []
## Per-talisman counters for "every N" triggers.
var talisman_counters: Dictionary = {}
## The daemon whose rule trigger is resolving right now (effect target "this"), else null.
var rule_daemon: Fighter
## Subroutine (run perk) defs with triggers; they fire like talismans.
var perks: Array = []
## Firewall gained when combat starts (perks).
var start_ward := 0
## Boot Firewall: Firewall gained at the start of each of your turns.
var turn_ward := 0
var ward_retention := 0.0
var daemon_death_damage := 0
## Hive Link: you may shut down your own daemons on your turn (shutdown_daemon).
var manual_crash := false
## Repair Drones: repair this much each time you run a daemon. Daemon Plating: Firewall a new daemon starts with.
var daemon_heal := 0
var daemon_ward := 0
## Second Wind: once per fight, a hit that would flatline you leaves 1 HP and gives this much Firewall.
var second_wind := 0
var second_wind_used := false
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
## Shared HP totals by pool name (BossRules "pool").
var pools: Dictionary = {}


## deck: Array of CardInstance (copied, not mutated). hp < 0 means full HP.
## opts (all optional): max_hp, talismans (Array of ids), perks (Array of perk dicts),
## start_ward, ward_retention, daemon_death_damage, manual_crash, enemy_hp_mult, enemy_might, enemy_dmg_mult, extra_energy, extra_hand, extra_slots,
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
	# balance.enemy_dmg_mult scales every enemy's damage (on top of heat/act/perk mults).
	c.enemy_dmg_mult = float(opts.get("enemy_dmg_mult", 1.0)) * float(db_in.balance.get("enemy_dmg_mult", 1.0))
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
	c.turn_ward = int(opts.get("turn_ward", 0))
	c.ward_retention = clampf(float(opts.get("ward_retention", 0.0)), 0.0, 1.0)
	c.daemon_death_damage = int(opts.get("daemon_death_damage", 0))
	c.manual_crash = bool(opts.get("manual_crash", false))
	c.daemon_heal = int(opts.get("daemon_heal", 0))
	c.daemon_ward = int(opts.get("daemon_ward", 0))
	c.second_wind = int(opts.get("second_wind", 0))
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
	BossRules.link(c)
	c.draw_pile = deck.map(func(card: CardInstance) -> CardInstance:
		var cp := card.copy()
		cp.origin = card
		return cp)
	for card in c.draw_pile:
		card.reset_combat()
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
	BossRules.setup(f, d)
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
	played_ids.clear()
	played_types.clear()
	if player.status("fortify") <= 0 and rule_sum("keep_ward") <= 0:
		player.ward = ceili(player.ward * ward_retention)
	energy = maxi(max_energy - player.status("overcharge") + player.status("surge"), 0)
	player.statuses.erase("overcharge")
	player.statuses.erase("surge")
	BossRules.on_player_turn(self)
	emit("turn_start", {"turn": turn, "ward": player.ward})
	# Daemons run down: HP is the countdown, so a daemon with N HP lasts N rounds if left alone.
	# Every daemon ticks first, then the ones at 0 close, so a payoff from one closing (Server Farm)
	# can't decide which of two daemons at the same HP survives.
	var closing: Array = []
	for u: Fighter in units:
		u.hp -= 1
		if u.hp <= 0:
			closing.append(u)
		else:
			emit("uptime", {"target": u.id, "hp": u.hp})
	for u: Fighter in closing:
		units.erase(u)
		emit("expire", {"target": u.id})
	for u: Fighter in closing:
		_daemon_closed(u)
	if turn == 1:
		# After the Ward reset, so start-of-combat Ward sticks for turn 1.
		if start_ward > 0:
			Effects.resolve(self, {"op": "ward", "amount": start_ward}, player, null)
		Talismans.fire(self, "combat_start")
	if turn_ward > 0:
		Effects.resolve(self, {"op": "ward", "amount": turn_ward}, player, null)
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
	if card.has_keyword("unplayable") or card.cost() > energy:
		return false
	if units.size() >= board_slots and _summons(card) and not _refreshes(card):
		return false
	# Dump N is a cost: you need N other cards in hand.
	if dump_need(card) > hand.size() - 1:
		return false
	return true


## How many other cards this program must Dump (0 for none or "Dump your hand").
func dump_need(card: CardInstance) -> int:
	var n := 0
	for e in card.effects():
		if e.get("op", "") == "dump":
			n += int(e.get("amount", 0))
	return n


## What a Dump or recover on this card would ask the player to pick from:
## {"kind": "dump"|"recover", "amount": n, "cards": [...]} or {} when there is no choice to make.
## Picks are optional: play_card fills any it doesn't get (see dump/recover).
func pick_request(hand_idx: int) -> Dictionary:
	if hand_idx < 0 or hand_idx >= hand.size():
		return {}
	var card: CardInstance = hand[hand_idx]
	for e in card.effects():
		var op := str(e.get("op", ""))
		if op == "dump" and int(e.get("amount", 0)) > 0:
			var others := hand.filter(func(k: CardInstance) -> bool: return k != card)
			if others.size() > int(e["amount"]):
				return {"kind": "dump", "amount": int(e["amount"]), "cards": others}
		elif op == "recover":
			var pool := recover_pool(str(e.get("from", "discard")))
			if pool.size() > maxi(int(e.get("amount", 1)), 1):
				return {"kind": "recover", "amount": maxi(int(e.get("amount", 1)), 1), "cards": pool, "from": str(e.get("from", "discard")), "into": str(e.get("into", "draw"))}
	return {}


func needs_target(card: CardInstance) -> bool:
	return card.def.target == "enemy"


func needs_ally(card: CardInstance) -> bool:
	return card.def.target == "ally"


## target_idx is an index into `enemies`; -1 picks the first living enemy.
## For "ally" cards it indexes [you] + your daemons (0 or -1 = you).
## chosen: cards the player picked for a Dump (from hand) or recover (from a pile).
func play_card(hand_idx: int, target_idx: int = -1, chosen: Array = []) -> bool:
	if not can_play(hand_idx):
		return false
	var card: CardInstance = hand[hand_idx]
	var target: Fighter = null
	if needs_target(card):
		if target_idx < 0:
			target_idx = enemies.find(_first_living(enemies))
		if target_idx < 0 or target_idx >= enemies.size() or enemies[target_idx].is_dead():
			return false
		# Formation: a guarded boss's escorts take hits aimed at it.
		target = BossRules.guard_target(self, enemies[target_idx])
	if needs_ally(card):
		var allies: Array = [player] + units
		if target_idx >= allies.size():
			return false
		target = allies[maxi(target_idx, 0)]
	hand.remove_at(hand_idx)
	var held := hand.duplicate()
	picks = chosen.duplicate()
	last_dumped = 0
	x_spent = 0
	if card.is_x():
		x_spent = energy
		energy = 0
	else:
		energy -= card.cost()
	var play_ev := {"card": card.key(), "target": target.id if target != null else ""}
	if card.is_x():
		play_ev["x"] = x_spent
	emit("play", play_ev)
	for e in CardPrograms.effects(self, card):
		if is_over():
			break
		if target != null and target.is_dead():
			target = _first_living(enemies) if needs_target(card) else target
		Effects.resolve(self, e, player, target)
	CardPrograms.after_play(self, card, held)
	picks = []
	_evolve_step(card)
	if card.has_loop():
		card.loops += 1 + rule_sum("loop_bonus")
		var step := 0
		for le in card.def.get_effects(card.upgraded):
			if le.has("loop"):
				step = int(le["loop"])
				break
		emit("loop", {"card": card.key(), "loops": card.loops, "grown": step * card.loops})
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


## Evolve: count the run; on the last one the copy becomes its evolved card (same upgrade/firmware/mod).
func _evolve_step(card: CardInstance) -> void:
	if card.def.evolve.is_empty():
		return
	card.uses += 1
	if card.evolve_left() > 0:
		return
	var into: CardDef = db.card(str(card.def.evolve.get("into", "")))
	if into == null:
		return
	var was := card.key()
	card.def = into
	card.uses = 0
	card.loops = 0
	emit("evolve", {"card": was, "into": card.key()})


## Dump: discard n other cards from hand (0 = all). Player picks come first; the rest are
## picked for them: cards with a "When dumped" effect, then Locked cards, then left to right.
func dump(n: int) -> void:
	var count := hand.size() if n <= 0 else mini(n, hand.size())
	var order: Array = picks.filter(func(k: CardInstance) -> bool: return hand.has(k))
	var rest := hand.filter(func(k: CardInstance) -> bool: return not order.has(k))
	var rank := func(k: CardInstance) -> int: return 0 if not k.def.get_on_dump(k.upgraded).is_empty() else (1 if k.has_keyword("unplayable") else 2)
	for r in 3:
		for k in rest:
			if rank.call(k) == r:
				order.append(k)
	var done := 0
	for k: CardInstance in order.slice(0, count):
		if is_over():
			break
		hand.erase(k)
		CardPrograms.on_discard(k)
		discard_pile.append(k)
		done += 1
		emit("dump", {"card": k.key()})
		for fx in k.def.get_on_dump(k.upgraded):
			if is_over():
				break
			Effects.resolve(self, fx, player, _first_living(enemies))
		_check_end()
	last_dumped = done


## What recover can pull from a pile: no Rootkits back from Wipe, and no recover cards (no loops).
func recover_pool(from: String) -> Array:
	var pile: Array = exhaust_pile if from == "wiped" else discard_pile
	if from != "wiped":
		return pile.duplicate()
	return pile.filter(func(k: CardInstance) -> bool: return k.def.type != "power" and not k.effects().any(func(e: Dictionary) -> bool: return e.get("op", "") == "recover"))


## Shuffle n programs from the discard pile or the Wiped pile into the draw pile ("top": on top).
## Player picks first, then the costliest card (X counts as 3), most recent first.
func recover(from: String, into: String, n: int) -> void:
	var pool := recover_pool(from)
	var order: Array = picks.filter(func(k: CardInstance) -> bool: return pool.has(k))
	var rest: Array = pool.filter(func(k: CardInstance) -> bool: return not order.has(k))
	rest.reverse()
	var weight := func(k: CardInstance) -> int: return 3 if k.is_x() else k.cost()
	rest.sort_custom(func(a: CardInstance, b: CardInstance) -> bool: return weight.call(a) > weight.call(b))
	order.append_array(rest)
	var pile: Array = exhaust_pile if from == "wiped" else discard_pile
	for k: CardInstance in order.slice(0, n):
		pile.erase(k)
		if into == "top" or draw_pile.is_empty():
			draw_pile.append(k)
		else:
			draw_pile.insert(rng.range_i(0, draw_pile.size()), k)
		emit("recover", {"card": k.key(), "from": from, "into": into})


## After a fight: Evolve progress (and evolved forms) go back to the run deck cards.
func sync_origins() -> void:
	for k: CardInstance in draw_pile + hand + discard_pile + exhaust_pile:
		if k.origin == null:
			continue
		k.origin.uses = k.uses
		if k.origin.def != k.def:
			k.origin.def = k.def


func end_turn() -> void:
	if phase != Phase.PLAYER:
		return
	_ending_turn = true
	Talismans.fire(self, "turn_end")
	if is_over():
		return
	Statuses.on_turn_end(self, player)
	for u in units:
		Statuses.on_turn_end(self, u)
	# Enemies that joined during your turn had a turn to be answered: they act this enemy turn.
	for en: Fighter in enemies:
		en.arrived = false
	var kept: Array = []
	for card in hand:
		if card.has_keyword("retain"):
			kept.append(card)
		elif card.has_keyword("ethereal"):
			exhaust_pile.append(card)
		elif card.def.hatch != "":
			# Spore: left unplayed, it is used up and hatches on the enemy side.
			exhaust_pile.append(card)
			emit("hatch", {"card": card.key(), "enemy": card.def.hatch})
			spawn(card.def.hatch)
		else:
			CardPrograms.on_discard(card)
			discard_pile.append(card)
	hand = kept
	_ending_turn = false
	phase = Phase.ENEMY
	emit("enemy_phase")
	for en: Fighter in enemies:
		# Summoned this enemy turn (or hatched as yours ended): it waits for the next one.
		if en.is_dead() or en.arrived:
			continue
		if en.status("fortify") <= 0:
			en.ward = 0
		Statuses.on_turn_start(self, en)
		_check_end()
		if is_over():
			return
		if en.is_dead():
			continue
		BossRules.before_move(self, en)
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
				if Intents.kind_of(e) in en.interrupted:
					continue
				Effects.resolve(self, e, en, player)
			en.interrupted = []
			en.advance_move()
			BossRules.after_move(en)
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


## own_mods = false: a daemon rule's hit. It comes from you, but your Boost/Throttled don't
## touch it; daemons have their own buffs (Uplink). The target's Exposed still counts.
func attack(src: Fighter, t: Fighter, base: int, own_mods: bool = true) -> int:
	var amount := Statuses.modify_attack(base, src if own_mods else null, t)
	if t == player and src != null and enemies.has(src):
		amount = maxi(amount - rule_sum("guard"), 0)
	var dealt := deal_damage(t, amount, src.id if src != null else "")
	BossRules.on_attacked(self, src, t)
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
	if not t.rules.is_empty():
		amount = BossRules.scale(self, t, amount, kind)
		if amount <= 0:
			emit("immune", {"target": t.id})
			return 0
	# Daemon Firewall (Daemon Plating) only absorbs attacks: Purge, Virus and HP loss go straight through.
	var blocked := mini(t.ward, amount) if not (units.has(t) and kind != "attack") else 0
	t.ward -= blocked
	var dealt := amount - blocked
	if not t.rules.is_empty():
		dealt = BossRules.limit(t, dealt)
	t.hp = maxi(t.hp - dealt, 0)
	var saved := t == player and t.hp <= 0 and second_wind > 0 and not second_wind_used
	if saved:
		second_wind_used = true
		t.hp = 1
	emit("damage", {"target": t.id, "amount": dealt, "blocked": blocked, "source": source_id, "kind": kind, "hp": t.hp, "ward": t.ward})
	if saved:
		t.ward += second_wind
		emit("second_wind", {"target": t.id})
		emit("ward", {"target": t.id, "amount": second_wind, "ward": t.ward})
	if not t.rules.is_empty() and dealt > 0:
		BossRules.after_damage(self, t)
	# "When you lose HP" rules (Backlash, Scar Tissue). Not from inside one: a rule that
	# costs HP can't chain itself.
	if t == player and dealt > 0 and not t.is_dead() and not _hp_lost_firing:
		_hp_lost_firing = true
		Talismans.fire(self, "hp_lost", {"amount": dealt, "kind": kind})
		_hp_lost_firing = false
	if t.is_dead():
		emit("death", {"target": t.id})
		if units.has(t):
			units.erase(t)
			_daemon_closed(t)
		elif enemies.has(t):
			BossRules.on_death(self, t)
			if phase == Phase.PLAYER:
				Talismans.fire(self, "kill", {"target": t})
	return dealt


## Crashes a running daemon on purpose (op "sacrifice"): its rule ends now.
func crash_daemon(u: Fighter) -> void:
	if not units.has(u):
		return
	units.erase(u)
	emit("expire", {"target": u.id, "crashed": true})
	_daemon_closed(u)


## A daemon left the board (crashed or ran out): its own "closed" rule, then the payoffs.
func _daemon_closed(u: Fighter) -> void:
	# The daemon's own "closed" rule (Botnet Lease's parting blast).
	for trig in u.rule.get("triggers", []):
		if trig.get("on", "") != "closed" or is_over():
			continue
		emit("rule", {"id": u.id, "trigger": "closed"})
		for e in trig.get("effects", []):
			Effects.resolve(self, e, player, null)
		_check_end()
	_daemon_payoffs(u)


## Player action (Hive Link): shut down one of your own daemons. Same as it running out.
func can_shutdown() -> bool:
	return manual_crash and phase == Phase.PLAYER and not units.is_empty() and not is_over()


func shutdown_daemon(idx: int) -> bool:
	if not can_shutdown() or idx < 0 or idx >= units.size():
		return false
	crash_daemon(units[idx])
	return true


## "Destroyed or refreshed" payoffs: implants on daemon_closed and Hive Link's blast.
## Fire when a daemon leaves the board and when re-running it tops it back up.
func _daemon_payoffs(u: Fighter) -> void:
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
		if card.payload > 0:
			var payload := card.payload
			card.payload = 0
			Effects.resolve(self, {"op": "ward", "amount": payload}, player, null)
	for i in reshuffles:
		if not is_over():
			Talismans.fire(self, "reshuffle")


## Runs a daemon: a rule change that lasts while it has HP. It loses 1 HP at the start of each
## of your turns and 1 per hit taken (Purge takes more). Running one that is already up
## (same name) tops its HP back up instead of taking a slot.
func summon(unit_name: String, hp: int, rule: Dictionary = {}) -> bool:
	hp = maxi(ceili(hp * daemon_hp_mult - 0.001) + daemon_hp, 1)
	# A daemon with a "closed" rule restarts when re-run: it shuts down (payoff fires), then boots fresh.
	for u in units:
		if u.name == unit_name and u.rule.get("triggers", []).any(func(t: Dictionary) -> bool: return t.get("on", "") == "closed"):
			crash_daemon(u)
			break
	for u in units:
		if u.name == unit_name:
			u.max_hp = maxi(u.max_hp, hp)
			u.hp = maxi(u.hp, hp)
			u.rule = rule
			u.ward = maxi(u.ward, daemon_ward)
			emit("refresh", {"target": u.id, "hp": u.hp, "ward": u.ward})
			_daemon_payoffs(u)
			_daemon_repair()
			return true
	if units.size() >= board_slots:
		return false
	var u := Fighter.make("u%d" % _unit_counter, unit_name, hp)
	_unit_counter += 1
	u.rule = rule
	u.ward = daemon_ward
	units.append(u)
	emit("summon", {"target": u.id, "name": unit_name, "hp": hp, "ward": u.ward})
	_daemon_repair()
	return true


## Repair Drones: running a daemon (new or refreshed) repairs you.
func _daemon_repair() -> void:
	if daemon_heal > 0 and not is_over():
		Effects.resolve(self, {"op": "heal", "amount": daemon_heal, "to": "self"}, player, player)


## Sum of a rule flag over the daemons that are running (true counts as 1).
func rule_sum(flag: String) -> int:
	var total := 0
	for u in units:
		total += int(u.rule.get("flags", {}).get(flag, 0))
	return total + Talismans.flag_sum(self, flag)


## Enemy-side summon (op "spawn"). Max 5 enemies alive.
## hp_pct < 1 brings it in hurt (a restored twin); those are not "spawned" helpers.
## `base_max` > 0 (twin Restore): the share is of that max HP, and the result becomes the new max.
func spawn(enemy_id: String, hp_pct: float = 1.0, base_max: int = 0) -> bool:
	if living(enemies).size() >= 5 or not db.enemies.has(enemy_id):
		return false
	var f := _make_enemy(enemy_id)
	f.spawned = hp_pct >= 1.0
	f.arrived = phase != Phase.PLAYER or _ending_turn
	if base_max > 0:
		f.max_hp = maxi(roundi(base_max * hp_pct), 1)
		f.hp = f.max_hp
	elif hp_pct < 1.0:
		f.hp = maxi(roundi(f.max_hp * hp_pct), 1)
	var pool := str(f.rules.get("pool", ""))
	if pool != "" and pools.has(pool):
		f.hp = int(pools[pool])
	enemies.append(f)
	emit("spawn", {"target": f.id, "enemy": enemy_id, "hp": f.hp})
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
			if "attack" in en.interrupted:
				continue
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
