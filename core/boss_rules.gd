class_name BossRules
extends RefCounted
## Fight rules that bosses and elites carry on top of their move list. Data only: an enemy def
## may hold "rules": {key: config} with any of the KEYS below. Combat calls the hooks here;
## the UI reads chips()/rows(). Pure rules, no Nodes.
##
##   phases     [{at, name, moves, statuses, effects, cleanse, rules}]  new form at at*max HP; damage past the mark is lost
##   timer      {turns, status, stacks}        Trace: after `turns` moves it gains the status every move
##   tide       {high, low, high_taken, low_taken, low_move}  cycles by round; low tide uses low_move
##   gauge      {max, name, effects}           your attack hits add heat; full = effects stapled to its next move
##   jam        {every}                        intent hidden every Nth turn (Exposed or an Interrupt clears it)
##   twin       {pct}                          a crashed twin is restored by the survivor at pct HP
##   pool       "name" (+ leaves_at)           bodies share one HP total; a body shuts down at leaves_at of it
##   taken      {damage kind: multiplier}      e.g. {"attack": 0.5, "burn": 2}
##   shielded_by enemy id (+ respawn {count, after})  no damage while one of those is up; they come back
##   guarded    true                           single-target hits land on its escorts first
##   bond       {status, stacks, heal}         when a bonded partner crashes, the survivors power up

const KEYS := ["phases", "timer", "tide", "gauge", "jam", "twin", "pool", "leaves_at", "taken", "shielded_by", "respawn", "guarded", "bond"]

## Rules page / ICE database glossary: key -> [name, text].
const DESC := {
	"phases": ["Phases", "At a marked share of its HP the boss changes form: new moves, and its harmful statuses are wiped. Damage past the mark is lost, so one big hit can't skip a phase."],
	"timer": ["Trace", "A countdown of its moves. When it reaches 0 the boss gains Boost on every move after that, so long fights get dangerous."],
	"tide": ["Tide", "The boss swaps between high tide (takes less damage, attacks) and low tide (takes extra damage, only defends). The chip says when it turns."],
	"gauge": ["Heat gauge", "Each of your attack hits adds 1 heat. When the gauge is full the boss vents on its next move, on top of that move, and the gauge resets. Few big hits fill it slower than many small ones."],
	"jam": ["Signal jam", "On some turns the intent is hidden. Exposed on the enemy, or running an Interrupt on it, clears the jam for that turn."],
	"twin": ["Twin Cores", "When one twin crashes, the survivor spends its move after next restoring it with a share of its max HP, which becomes its new max HP, so each Restore is smaller. Crash both before then, or Interrupt the Restore (it counts as Repair) to stop it for good."],
	"pool": ["Shared HP", "These bodies share one HP total. Hit whichever is weakest to your programs; hit-all programs count once per body. Some bodies shut down as the total drops."],
	"taken": ["Resistances", "Takes more or less damage from one kind of damage, such as attacks or Virus."],
	"shielded_by": ["Shield pylons", "The boss takes no damage while a pylon is up. Crash the pylons to open a window; they come back after a few moves."],
	"guarded": ["Formation", "Escorts stand in front. Programs aimed at one enemy hit an escort first. Hit-all programs and Virus still reach the boss."],
	"bond": ["Bonded", "When one of a bonded pair crashes, the survivor repairs itself and powers up. Choose which to finish first, or bring both down together."],
}

const KIND_NAMES := {"attack": "attacks", "burn": "Virus", "thorns": "Feedback", "purge": "Purge"}


static func setup(f: Fighter, def: Dictionary) -> void:
	f.rules = def.get("rules", {})
	f.state = {}
	_init_state(f)


static func _init_state(f: Fighter) -> void:
	if f.rules.has("gauge") and not f.state.has("gauge"):
		f.state["gauge"] = 0
	if f.rules.has("timer") and not f.state.has("timer"):
		f.state["timer"] = int(f.rules["timer"].get("turns", 6))
	if f.rules.has("phases") and not f.state.has("phase"):
		f.state["phase"] = 0


## After every starting enemy exists: bodies of one pool start on the same HP total.
static func link(c: Combat) -> void:
	for f in c.enemies:
		var pool := str(f.rules.get("pool", ""))
		if pool == "":
			continue
		if not c.pools.has(pool):
			c.pools[pool] = f.hp
		f.hp = int(c.pools[pool])
		f.max_hp = f.hp


# --- damage -------------------------------------------------------------------

static func shielded(c: Combat, t: Fighter) -> bool:
	var by := str(t.rules.get("shielded_by", ""))
	return by != "" and c.enemies.any(func(e: Fighter) -> bool: return e.def_id == by and not e.is_dead())


## Tide state for the current round: "high", "low" or "" (no tide).
static func tide(c: Combat, t: Fighter) -> String:
	if not t.rules.has("tide"):
		return ""
	var cfg: Dictionary = t.rules["tide"]
	var high := maxi(int(cfg.get("high", 2)), 1)
	var low := maxi(int(cfg.get("low", 1)), 1)
	return "high" if (maxi(c.turn, 1) - 1) % (high + low) < high else "low"


## Rounds until the tide turns (1 = it turns after this round).
static func tide_left(c: Combat, t: Fighter) -> int:
	var cfg: Dictionary = t.rules.get("tide", {})
	var high := maxi(int(cfg.get("high", 2)), 1)
	var low := maxi(int(cfg.get("low", 1)), 1)
	var pos := (maxi(c.turn, 1) - 1) % (high + low)
	return high - pos if pos < high else high + low - pos


## Multiplier on damage of `kind` landing on enemy t (0 = shielded).
static func taken_mult(c: Combat, t: Fighter, kind: String) -> float:
	if t.rules.is_empty() or not c.enemies.has(t):
		return 1.0
	if shielded(c, t):
		return 0.0
	var m := float(t.rules.get("taken", {}).get(kind, 1.0))
	match tide(c, t):
		"high":
			m *= float(t.rules["tide"].get("high_taken", 0.5))
		"low":
			m *= float(t.rules["tide"].get("low_taken", 1.5))
	return m


static func scale(c: Combat, t: Fighter, amount: int, kind: String) -> int:
	var m := taken_mult(c, t, kind)
	if m == 1.0:
		return amount
	return 0 if m <= 0.0 else maxi(roundi(amount * m), 1)


## The HP mark of the next phase (0 = none left).
static func phase_floor(t: Fighter) -> int:
	var phases: Array = t.rules.get("phases", [])
	var i := int(t.state.get("phase", 0))
	if i >= phases.size():
		return 0
	return maxi(ceili(t.max_hp * float(phases[i].get("at", 0.5))), 1)


## Damage that may land now: a hit can't carry past the next phase mark.
static func limit(t: Fighter, dealt: int) -> int:
	var mark := phase_floor(t)
	if mark > 0 and t.hp > mark:
		return mini(dealt, t.hp - mark)
	return dealt


## Called after HP changed on enemy t (damage): phases and the shared pool.
static func after_damage(c: Combat, t: Fighter) -> void:
	if t.rules.is_empty():
		return
	var mark := phase_floor(t)
	if mark > 0 and t.hp > 0 and t.hp <= mark:
		_enter_phase(c, t)
	_sync_pool(c, t, true)


## Called after enemy t was repaired.
static func after_heal(c: Combat, t: Fighter) -> void:
	if not t.rules.is_empty():
		_sync_pool(c, t, false)


static func _sync_pool(c: Combat, t: Fighter, hurt: bool) -> void:
	var pool := str(t.rules.get("pool", ""))
	if pool == "":
		return
	c.pools[pool] = t.hp
	var bodies: Array = c.enemies.filter(func(e: Fighter) -> bool: return e != t and not e.is_dead() and str(e.rules.get("pool", "")) == pool)
	for b in bodies:
		b.hp = t.hp
		c.emit("sync", {"target": b.id, "hp": b.hp})
		if b.hp <= 0:
			c.emit("death", {"target": b.id})
	if not hurt or t.hp <= 0:
		return
	# Bodies shut down one at a time as the total passes their mark; the last body never leaves.
	var share := float(t.hp) / maxf(t.max_hp, 1.0)
	for b in [t] + bodies:
		if b.rules.has("leaves_at") and share <= float(b.rules["leaves_at"]):
			var others: Array = c.enemies.filter(func(e: Fighter) -> bool: return e != b and not e.is_dead() and str(e.rules.get("pool", "")) == pool)
			if others.is_empty():
				continue
			b.hp = 0
			if b != t:
				c.emit("death", {"target": b.id})


static func _enter_phase(c: Combat, t: Fighter) -> void:
	var p: Dictionary = t.rules["phases"][int(t.state["phase"])]
	t.state["phase"] = int(t.state["phase"]) + 1
	if p.has("moves"):
		t.moves = p["moves"]
		t.move_idx = 0
	t.override = {}
	t.bonus = []
	t.interrupted = []
	if p.get("cleanse", true):
		for s in Statuses.debuffs(t):
			t.statuses.erase(s)
	if p.has("rules"):
		t.rules = t.rules.duplicate()
		for k in p["rules"]:
			t.rules[k] = p["rules"][k]
		_init_state(t)
	c.emit("phase", {"target": t.id, "index": int(t.state["phase"]), "name": str(p.get("name", ""))})
	for s in p.get("statuses", {}):
		t.add_status(s, int(p["statuses"][s]))
		c.emit("status", {"target": t.id, "status": s, "stacks": int(p["statuses"][s]), "total": t.status(s)})
	for e in p.get("effects", []):
		if c.is_over():
			break
		Effects.resolve(c, e, t, c.player)


## One of your attack hits landed on (or was blocked by) enemy t: the heat gauge.
static func on_attacked(c: Combat, src: Fighter, t: Fighter) -> void:
	if src != c.player or not t.rules.has("gauge") or t.is_dead():
		return
	var cfg: Dictionary = t.rules["gauge"]
	var cap := maxi(int(cfg.get("max", 8)), 1)
	var g := int(t.state.get("gauge", 0))
	if g >= cap:
		return
	g += 1
	t.state["gauge"] = g
	c.emit("gauge", {"target": t.id, "value": g, "max": cap})
	if g >= cap:
		t.bonus = cfg.get("effects", [])
		t.bonus_name = str(cfg.get("name", "Vent"))
		c.emit("gauge_full", {"target": t.id, "name": t.bonus_name})


static func on_death(c: Combat, t: Fighter) -> void:
	var alive: Array = c.living(c.enemies)
	if t.rules.has("twin"):
		for p in alive:
			if p.rules.has("twin") and not p.state.has("restore"):
				p.state["restore"] = t.def_id
				p.state["restore_max"] = t.max_hp
				c.emit("twin_down", {"target": t.id, "by": p.id})
				break
	if t.rules.has("bond"):
		for p in alive:
			if not p.rules.has("bond"):
				continue
			var cfg: Dictionary = p.rules["bond"]
			var heal := int(p.max_hp * float(cfg.get("heal", 0.0)))
			c.emit("bond", {"target": p.id})
			if heal > 0:
				Effects.resolve(c, {"op": "heal", "amount": heal, "to": "self"}, p, p)
			if cfg.has("status"):
				Effects.resolve(c, {"op": "apply", "status": cfg["status"], "stacks": int(cfg.get("stacks", 1)), "to": "self"}, p, p)
	for boss in alive:
		if str(boss.rules.get("shielded_by", "")) == t.def_id and not shielded(c, boss):
			boss.state["respawn"] = int(boss.rules.get("respawn", {}).get("after", 0))
			c.emit("shield_down", {"target": boss.id})


# --- turn hooks -----------------------------------------------------------------

## Start of each of your turns (after the turn counter moved): set this round's one-off moves.
static func on_player_turn(c: Combat) -> void:
	for en in c.living(c.enemies):
		if en.rules.is_empty():
			continue
		en.state.erase("revealed")
		if en.rules.has("tide"):
			var low := tide(c, en) == "low"
			if low and en.rules["tide"].has("low_move"):
				en.override = en.rules["tide"]["low_move"]
				en.state["tide_move"] = true
			elif en.state.get("tide_move", false):
				en.override = {}
				en.state.erase("tide_move")
			c.emit("tide", {"target": en.id, "state": "low" if low else "high"})
		if en.state.has("restore"):
			var pct := float(en.rules.get("twin", {}).get("pct", 0.5))
			en.override = {"name": "Restore", "effects": [{"op": "revive", "enemy": str(en.state["restore"]), "pct": pct, "max": int(en.state.get("restore_max", 0))}]}
			en.state.erase("restore")
			en.state.erase("restore_max")


## Just before enemy `en` takes its move (also when it is Lagged).
static func before_move(c: Combat, en: Fighter) -> void:
	if en.rules.is_empty():
		return
	if en.rules.has("timer"):
		var left := int(en.state.get("timer", 0))
		if left > 0:
			en.state["timer"] = left - 1
			c.emit("timer", {"target": en.id, "left": left - 1})
		else:
			var cfg: Dictionary = en.rules["timer"]
			Effects.resolve(c, {"op": "apply", "status": str(cfg.get("status", "might")), "stacks": int(cfg.get("stacks", 1)), "to": "self"}, en, en)
	if en.rules.has("respawn") and en.rules.has("shielded_by") and not shielded(c, en):
		var wait := int(en.state.get("respawn", 0)) - 1
		en.state["respawn"] = wait
		if wait <= 0:
			for i in int(en.rules["respawn"].get("count", 1)):
				c.spawn(str(en.rules["shielded_by"]))
			if shielded(c, en):
				c.emit("shield_up", {"target": en.id})


static func after_move(en: Fighter) -> void:
	if en.rules.has("gauge") and en.bonus.is_empty() and int(en.state.get("gauge", 0)) >= int(en.rules["gauge"].get("max", 8)):
		en.state["gauge"] = 0


# --- targeting and intent -------------------------------------------------------

## Where a single-target hit aimed at t lands: a guarded boss's first living escort.
static func guard_target(c: Combat, t: Fighter) -> Fighter:
	if t == null or not t.rules.get("guarded", false):
		return t
	for e in c.enemies:
		if e != t and not e.is_dead() and not e.rules.get("guarded", false):
			return e
	return t


static func guarded(c: Combat, t: Fighter) -> bool:
	return guard_target(c, t) != t


static func jammed(c: Combat, en: Fighter) -> bool:
	if not en.rules.has("jam") or en.is_dead():
		return false
	var every := maxi(int(en.rules["jam"].get("every", 2)), 2)
	return c.turn % every == 0 and en.status("brittle") <= 0 and not en.state.get("revealed", false)


# --- text for the UI ---------------------------------------------------------------

## Short chips under the HP bar: live state at a glance.
static func chips(c: Combat, f: Fighter) -> Array[String]:
	var out: Array[String] = []
	if f.rules.is_empty() or f.is_dead():
		return out
	var r := f.rules
	if r.has("phases"):
		out.append("Phase %d/%d" % [int(f.state.get("phase", 0)) + 1, r["phases"].size() + 1])
	if r.has("timer"):
		var left := int(f.state.get("timer", 0))
		out.append("Trace %d" % left if left > 0 else "Traced")
	if r.has("tide"):
		out.append("%s tide (%d)" % ["High" if tide(c, f) == "high" else "Low", tide_left(c, f)])
	if r.has("gauge"):
		out.append("Heat %d/%d" % [int(f.state.get("gauge", 0)), int(r["gauge"].get("max", 8))])
	if jammed(c, f):
		out.append("Jammed")
	if r.has("twin"):
		out.append("Twin")
	if r.has("pool"):
		out.append("Shared HP")
	if r.has("shielded_by"):
		out.append("Shielded" if shielded(c, f) else "Shield down (%d)" % maxi(int(f.state.get("respawn", 0)), 1))
	if guarded(c, f):
		out.append("Guarded")
	if r.has("bond"):
		out.append("Bonded")
	return out


## [heading, body] rows for the inspect popup. c may be null (ICE database): then no live numbers.
static func rows(c: Combat, f: Fighter) -> Array:
	return describe(f.rules, c, f)


static func describe(r: Dictionary, c: Combat = null, f: Fighter = null) -> Array:
	var out: Array = []
	var live := c != null and f != null
	if r.has("phases"):
		var marks: Array = r["phases"].map(func(p: Dictionary) -> String: return "%d%%" % roundi(float(p.get("at", 0.5)) * 100))
		var now := (" Now in phase %d of %d." % [int(f.state.get("phase", 0)) + 1, r["phases"].size() + 1]) if live else ""
		out.append(["Phases", "Changes form at %s HP: new moves, and its harmful statuses are wiped. Damage past the mark is lost.%s" % [" and ".join(marks), now]])
	if r.has("timer"):
		var cfg: Dictionary = r["timer"]
		var gain := "%d %s" % [int(cfg.get("stacks", 1)), Lexicon.status(str(cfg.get("status", "might")))]
		var left := int(f.state.get("timer", 0)) if live else int(cfg.get("turns", 6))
		out.append(["Trace", ("In %d more move%s it starts gaining %s on every move." % [left, "" if left == 1 else "s", gain]) if left > 0 else "The trace is complete: it gains %s on every move." % gain])
	if r.has("tide"):
		var cfg: Dictionary = r["tide"]
		var txt := "High tide (%d turn%s): takes %s damage. Low tide (%d turn%s): takes %s damage and only defends." % [
			int(cfg.get("high", 2)), "" if int(cfg.get("high", 2)) == 1 else "s", _mult_word(float(cfg.get("high_taken", 0.5))),
			int(cfg.get("low", 1)), "" if int(cfg.get("low", 1)) == 1 else "s", _mult_word(float(cfg.get("low_taken", 1.5)))]
		if live:
			txt += " Now: %s tide, turning in %d." % [tide(c, f), tide_left(c, f)]
		out.append(["Tide", txt])
	if r.has("gauge"):
		var cfg: Dictionary = r["gauge"]
		var fx := " ".join(cfg.get("effects", []).map(func(e: Dictionary) -> String: return Effects.describe(e).replace(" to ALL enemies", " to you and your daemons")))
		var now := (" Now %d." % int(f.state.get("gauge", 0))) if live else ""
		out.append(["Heat gauge", "Each of your attack hits adds 1 heat. At %d it vents on its next move (%s) and resets.%s" % [int(cfg.get("max", 8)), fx, now]])
	if r.has("jam"):
		out.append(["Signal jam", "Every %s turn its intent is hidden. Exposed on it, or running an Interrupt on it, clears the jam for that turn." % _ordinal(int(r["jam"].get("every", 2)))])
	if r.has("twin"):
		out.append(["Twin Cores", "When one twin crashes, the survivor uses its move after next to restore it at %d%% of its max HP, which becomes its new max (each Restore is smaller). Crash both before then, or Interrupt the Restore (as Repair) to stop it for good." % roundi(float(r["twin"].get("pct", 0.5)) * 100)])
	if r.has("pool"):
		var leave := (" This body shuts down when the total falls to %d%%." % roundi(float(r["leaves_at"]) * 100)) if r.has("leaves_at") else ""
		out.append(["Shared HP", "Shares one HP total with the other bodies. Damage to any of them counts.%s" % leave])
	if r.has("taken"):
		var parts: Array = []
		for k in r["taken"]:
			parts.append("%s damage from %s" % [_mult_word(float(r["taken"][k])), KIND_NAMES.get(k, k)])
		out.append(["Resistances", "Takes %s." % " and ".join(parts)])
	if r.has("shielded_by"):
		var back := ""
		if r.has("respawn"):
			back = " %d come back %d moves after the last one falls." % [int(r["respawn"].get("count", 1)), int(r["respawn"].get("after", 3))]
		out.append(["Shield pylons", "Takes no damage while a %s is up.%s" % [Lexicon.enemy_name(str(r["shielded_by"])), back]])
	if r.get("guarded", false):
		out.append(["Formation", "While an escort is up, programs aimed at this enemy hit the front escort instead. Hit-all programs and Virus still reach it."])
	if r.has("bond"):
		var cfg: Dictionary = r["bond"]
		var gains: Array = []
		if float(cfg.get("heal", 0.0)) > 0.0:
			gains.append("repairs %d%% of its HP" % roundi(float(cfg["heal"]) * 100))
		if cfg.has("status"):
			gains.append("gains %d %s" % [int(cfg.get("stacks", 1)), Lexicon.status(str(cfg["status"]))])
		out.append(["Bonded", "When its partner crashes, it %s." % " and ".join(gains)])
	return out


static func _mult_word(m: float) -> String:
	if m == 0.5:
		return "half"
	if m == 2.0:
		return "double"
	return "%d%% %s" % [roundi(absf(m - 1.0) * 100), "more" if m > 1.0 else "less"]


static func _ordinal(n: int) -> String:
	return {2: "2nd", 3: "3rd"}.get(n, "%dth" % n)


# --- data checks ------------------------------------------------------------------

static func validate(db: CardDB, id: String, r: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var where := "enemy '%s' rules" % id
	for k in r:
		if k not in KEYS:
			errs.append("%s: unknown rule '%s'" % [where, k])
	var mark := 1.0
	for p in r.get("phases", []):
		var at := float(p.get("at", 0.0))
		if at <= 0.0 or at >= mark:
			errs.append("%s: phase marks must fall from below 1 toward 0" % where)
		mark = at
		for mv in p.get("moves", []):
			for e in mv.get("effects", []):
				errs.append_array(Effects.validate(e, where))
		for e in p.get("effects", []):
			errs.append_array(Effects.validate(e, where))
		for s in p.get("statuses", {}):
			if not Statuses.is_known(s):
				errs.append("%s: unknown status '%s'" % [where, s])
		if p.has("rules"):
			errs.append_array(validate(db, id, p["rules"]))
	if r.has("timer") and not Statuses.is_known(str(r["timer"].get("status", "might"))):
		errs.append("%s: unknown timer status" % where)
	for e in r.get("gauge", {}).get("effects", []):
		errs.append_array(Effects.validate(e, where))
	if r.has("gauge") and r["gauge"].get("effects", []).is_empty():
		errs.append("%s: gauge vents nothing" % where)
	for e in r.get("tide", {}).get("low_move", {}).get("effects", []):
		errs.append_array(Effects.validate(e, where))
	if r.has("shielded_by") and not db.enemies.has(str(r["shielded_by"])):
		errs.append("%s: unknown pylon '%s'" % [where, r["shielded_by"]])
	if r.has("respawn") and not r.has("shielded_by"):
		errs.append("%s: respawn needs shielded_by" % where)
	if r.has("leaves_at") and not r.has("pool"):
		errs.append("%s: leaves_at needs pool" % where)
	if r.has("bond") and r["bond"].has("status") and not Statuses.is_known(str(r["bond"]["status"])):
		errs.append("%s: unknown bond status" % where)
	for k in r.get("taken", {}):
		if not KIND_NAMES.has(k):
			errs.append("%s: unknown damage kind '%s'" % [where, k])
	return errs
