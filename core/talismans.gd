class_name Talismans
extends RefCounted
## Passive run items. Defined in data/talismans.json:
##   {"id", "name", "rarity", "triggers": [{"on": TRIGGER, "effects": [...], filters...}],
##    "pickup": [run outcomes, e.g. {"op": "max_hp", "amount": 8}],
##    "daemon": {"hp": 1, "hp_mult": 2.0} (flat HP on every daemon you run; hp_mult scales
##       the program's base HP first, rounded up),
##    "mods": {PERK_MOD: n} (run-level numbers, same keys as subroutines, see MOD_KEYS),
##    "flags": {FLAG: n} (daemon rule flags that are always on, DaemonRules.FLAGS),
##    "flags_while_daemon": true (the flags only count while you run a daemon),
##    "run": [{"on": RUN_TRIGGER, "outcomes": [run outcomes]}] (map-level triggers),
##    "faction": crew id (thematic; never rolls on jobs where that crew is a target)}
## Trigger effects use the normal Effects vocabulary with the player as source.
## Filters: "every": N (fires on every Nth event), "turn": N (only that turn),
## "card_type": "attack" and "keyword": "loop" (card_played and loop only).

const TRIGGERS := ["combat_start", "turn_start", "turn_end", "card_played", "kill", "daemon_closed", "loop", "reshuffle"]
## Map-level triggers: "jump" (you jump to a node), "vault" (you crack a vault).
const RUN_TRIGGERS := ["jump", "vault"]
const RUN_LABEL := {"jump": "When you jump", "vault": "When you crack a vault"}
## Subroutine mod keys an implant may carry (the ones RunState reads live).
const MOD_KEYS := ["gold_pct", "rest_heal_pct", "shop_discount_pct", "reward_choices", "perk_choices",
	"combat_heal", "start_ward", "ward_retention", "daemon_death_damage", "rep_pct", "remove_discount",
	"max_energy", "hand_size", "board_slots", "daemon_hp", "jumps", "run_scrap", "bonus_packs"]
const RARITIES := ["common", "uncommon", "rare", "boss"]
const LABEL := {
	"combat_start": "When you jack in",
	"turn_start": "Start of each turn",
	"turn_end": "End of turn",
	"card_played": "When you play a card",
	"kill": "When you crash an enemy",
	"daemon_closed": "When one of your daemons shuts down",
	"closed": "When this daemon shuts down or is re-run",
	"loop": "When a Loop program grows",
	"reshuffle": "When your discard shuffles back into your draw pile",
}


## Fires implants, then subroutines (perks share the trigger format).
static func fire(c: Combat, on: String, ctx: Dictionary = {}) -> void:
	var sources: Array = c.talismans + c.perks
	for u in c.units:
		if not u.rule.get("triggers", []).is_empty():
			sources.append({"id": u.id, "triggers": u.rule["triggers"], "daemon": u})
	for t in sources:
		var tid: String = t.get("id", "")
		if t.has("daemon") and not c.units.has(t["daemon"]):
			continue
		for i in t.get("triggers", []).size():
			var trig: Dictionary = t["triggers"][i]
			if trig.get("on", "") != on or c.is_over():
				continue
			if trig.has("turn") and int(trig["turn"]) != c.turn:
				continue
			if trig.has("card_type"):
				var card: CardInstance = ctx.get("card")
				if card == null or card.def.type != trig["card_type"]:
					continue
			if trig.has("keyword"):
				var kcard: CardInstance = ctx.get("card")
				var kw := str(trig["keyword"])
				if kcard == null or not (kcard.has_loop() if kw == "loop" else kcard.has_keyword(kw)):
					continue
			if trig.has("every"):
				var key := "%s:%d" % [tid, i]
				c.talisman_counters[key] = int(c.talisman_counters.get(key, 0)) + 1
				c.emit("talisman_progress", {"id": tid, "index": i, "count": c.talisman_counters[key], "total": int(trig["every"])})
				if c.talisman_counters[key] % int(trig["every"]) != 0:
					continue
			c.emit("rule" if t.has("daemon") else "talisman", {"id": tid, "trigger": on})
			c.rule_daemon = t.get("daemon")
			for e in trig.get("effects", []):
				Effects.resolve(c, e, c.player, ctx.get("target"))
			c.rule_daemon = null


## Always-on rule flag from implants (Combat.rule_sum adds it to the daemons' flags).
static func flag_sum(c: Combat, flag: String) -> int:
	var total := 0
	for t in c.talismans:
		var f: Dictionary = t.get("flags", {})
		if f.has(flag) and (not t.get("flags_while_daemon", false) or not c.units.is_empty()):
			total += int(f[flag])
	return total


## Fires the map-level triggers of the run's implants. Returns log lines.
static func fire_run(run: RunState, on: String) -> Array:
	var lines: Array = []
	for tid in run.talismans:
		var t: Dictionary = run.db.talismans.get(tid, {})
		for trig in t.get("run", []):
			if trig.get("on", "") != on:
				continue
			run.implant_activations[tid] = int(run.implant_activations.get(tid, 0)) + 1
			run.implant_recent.append(tid)
			for o in trig.get("outcomes", []):
				var line := RunOutcomes.apply(run, o)
				if line != "":
					lines.append("%s: %s" % [t.get("name", tid), line])
	return lines


static func describe(t: Dictionary) -> String:
	var parts: Array[String] = []
	for o in t.get("pickup", []):
		parts.append(RunOutcomes.describe(o))
	var dm: Dictionary = t.get("daemon", {})
	if dm.has("hp_mult"):
		var m := float(dm["hp_mult"])
		parts.append("Your daemons start with double HP." if is_equal_approx(m, 2.0) else "Your daemons start with %d%% more HP (rounded up)." % roundi((m - 1.0) * 100))
	if dm.has("hp"):
		parts.append("Your daemons have +%d HP." % int(dm["hp"]))
	var flags: Dictionary = t.get("flags", {})
	if not flags.is_empty():
		var ftxt := DaemonRules.describe({"flags": flags})
		if t.get("flags_while_daemon", false):
			ftxt = "While you run a daemon: " + ftxt
		parts.append(ftxt)
	var mods: Dictionary = t.get("mods", {})
	for k in mods:
		parts.append(Perks.describe_mod(k, float(mods[k])))
	for trig in t.get("run", []):
		var fx: Array[String] = []
		for o in trig.get("outcomes", []):
			fx.append(RunOutcomes.describe(o))
		var run_when: String = RUN_LABEL.get(str(trig.get("on", "")), "?")
		parts.append("%s: %s" % [run_when, " ".join(fx)])
	for trig in t.get("triggers", []):
		var on: String = trig.get("on", "")
		var when: String = LABEL.get(on, "?")
		if trig.has("card_type"):
			var tn := Lexicon.type_name(str(trig["card_type"]))
			when = "When you play %s %s" % ["an" if tn[0].to_lower() in "aeiou" else "a", tn]
		if trig.has("every"):
			var noun: String = {"card_played": "cards you play", "turn_start": "turns", "turn_end": "turns", "kill": "crashed enemies",
				"daemon_closed": "daemons that shut down", "reshuffle": "reshuffles"}.get(on, "times")
			if trig.has("card_type"):
				noun = "%ss you play" % Lexicon.type_name(str(trig["card_type"]))
			when = "Every %d %s" % [int(trig["every"]), noun]
			if on == "loop":
				when = "Every %d times a Loop program grows" % int(trig["every"])
		elif trig.has("keyword") and on == "card_played":
			when = "When you play a %s program" % Lexicon.keyword(str(trig["keyword"]))
		if trig.has("turn"):
			when = "On turn %d" % int(trig["turn"])
		var fx: Array[String] = []
		for e in trig.get("effects", []):
			fx.append(Effects.describe(e))
		parts.append("%s: %s" % [when, " ".join(fx)])
	return " ".join(parts)


static func validate(t: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var where := "talisman '%s'" % t.get("id", "")
	if str(t.get("rarity", "")) not in RARITIES:
		errs.append("%s: bad rarity '%s'" % [where, t.get("rarity", "")])
	for trig in t.get("triggers", []):
		if trig.get("on", "") not in TRIGGERS:
			errs.append("%s: bad trigger '%s'" % [where, trig.get("on", "")])
		for e in trig.get("effects", []):
			errs.append_array(Effects.validate(e, where))
	for o in t.get("pickup", []):
		errs.append_array(RunOutcomes.validate(o, where))
	for k in t.get("daemon", {}):
		if k not in ["hp", "hp_mult"]:
			errs.append("%s: unknown daemon bonus '%s'" % [where, k])
	for k in t.get("mods", {}):
		if k not in MOD_KEYS or not Perks.MODS.has(k):
			errs.append("%s: mod '%s' can't go on an implant" % [where, k])
	for k in t.get("flags", {}):
		if not DaemonRules.FLAGS.has(k):
			errs.append("%s: unknown rule flag '%s'" % [where, k])
	for trig in t.get("run", []):
		if trig.get("on", "") not in RUN_TRIGGERS:
			errs.append("%s: bad run trigger '%s'" % [where, trig.get("on", "")])
		for o in trig.get("outcomes", []):
			errs.append_array(RunOutcomes.validate(o, where))
	if t.has("faction") and not Lexicon.FACTION.has(str(t["faction"])):
		errs.append("%s: unknown faction '%s'" % [where, t["faction"]])
	return errs
