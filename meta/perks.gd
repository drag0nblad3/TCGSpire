class_name Perks
extends RefCounted
## Perks change the rules of a whole run. Two scopes, one file (data/perks.json):
##   "run": Subroutines. Picked from 3 after black sentries and Cores; last this run.
##          May have "mods", "triggers" (like implants) and "pickup" (run outcomes).
##   "rig": Rig upgrades. Bought with rig points between runs, saved in the profile,
##          ranked 1..max_rank; each rank adds its "mods" again. A "capstone" rig perk
##          unlocks once every other rig perk of its crew is maxed, and may have triggers.
## Mods are numbers summed over every perk (RunState.perk_mod):
const MODS := {
	"max_hp": "Max HP",
	"start_gold": "Starting creds",
	"gold_pct": "Creds from fights",
	"rest_heal_pct": "Safehouse repair",
	"shop_discount_pct": "Fixer discount",
	"reward_choices": "Program choices after fights",
	"reward_rerolls": "Program reward rerolls per run",
	"event_rerolls": "Signal rerolls per run",
	"combat_heal": "Repair after each fight",
	"start_ward": "Firewall when you jack in",
	"ward_retention": "Firewall kept between turns",
	"daemon_death_damage": "Damage when a daemon is destroyed",
	"start_mods": "Random mods at run start",
	"start_perks": "Random subroutines at run start",
	"enemy_hp_pct": "Enemy HP",
	"rep_pct": "Rep from the job",
	"perk_choices": "Subroutine choices",
	"remove_discount": "Cheaper program deletion",
	"max_energy": "RAM each turn",
	"hand_size": "Programs drawn each turn",
	"board_slots": "Daemon slots",
	"daemon_hp": "Daemon HP",
	"sidesteps": "Sidesteps per layer",
}
const SCOPES := ["run", "rig"]
const PCT := ["gold_pct", "rest_heal_pct", "shop_discount_pct"]


## Player-facing text, e.g. "+35% creds from fights." rank scales the numbers.
static func describe(p: Dictionary, rank: int = 1) -> String:
	var parts: Array[String] = []
	for o in p.get("pickup", []):
		parts.append(RunOutcomes.describe(o))
	var mods: Dictionary = p.get("mods", {})
	for k in mods:
		parts.append(describe_mod(k, float(mods[k]) * maxi(rank, 1)))
	if p.has("triggers"):
		parts.append(Talismans.describe({"triggers": p["triggers"]}))
	return " ".join(parts)


static func describe_mod(k: String, v: float) -> String:
	match k:
		"sidesteps":
			return "+%d sidestep%s per layer: once per floor, slip to the node beside you (passing through, no stop)." % [int(v), "" if int(v) == 1 else "s"]
		"max_hp":
			return "+%d max HP." % int(v)
		"start_gold":
			return "Start runs with +%d creds." % int(v)
		"gold_pct":
			return "+%d%% creds from fights." % roundi(v * 100)
		"rest_heal_pct":
			return "Safehouses repair %d%% more." % roundi(v * 100)
		"shop_discount_pct":
			return "Fixer prices %d%% lower." % roundi(v * 100)
		"reward_choices":
			return "+%d program choice%s after fights." % [int(v), "" if int(v) == 1 else "s"]
		"reward_rerolls":
			return "Reroll program rewards after fights %d time%s per run." % [int(v), "" if int(v) == 1 else "s"]
		"event_rerolls":
			return "Reroll a Signal before choosing %d time%s per run." % [int(v), "" if int(v) == 1 else "s"]
		"combat_heal":
			return "Repair %d HP after each fight you win." % int(v)
		"start_ward":
			return "Jack in with %d %s." % [int(v), Lexicon.term("ward")]
		"ward_retention":
			return "Keep %d%% of remaining Firewall at the start of your turn, rounded up." % roundi(v * 100)
		"daemon_death_damage":
			return "When one of your daemons is destroyed, it explodes for %d damage to all enemies." % int(v)
		"start_mods":
			return "Start runs with %d random mod%s installed." % [int(v), "" if int(v) == 1 else "s"]
		"start_perks":
			return "Start runs with %d random subroutine%s." % [int(v), "" if int(v) == 1 else "s"]
		"rep_pct":
			return "+%d%% rep from jobs." % roundi(v * 100)
		"max_energy":
			return "+%d %s every turn." % [int(v), Lexicon.term("energy")]
		"hand_size":
			return "Draw %d more program%s each turn." % [int(v), "" if int(v) == 1 else "s"]
		"board_slots":
			return "+%d daemon slot%s." % [int(v), "" if int(v) == 1 else "s"]
		"daemon_hp":
			return "Your daemons have +%d HP." % int(v)
		"perk_choices":
			return "+%d subroutine choice%s." % [int(v), "" if int(v) == 1 else "s"]
		"remove_discount":
			return "Deleting a program at the Fixer costs %d less." % int(v)
		"enemy_hp_pct":
			return "Enemies have %d%% %s HP." % [absi(roundi(v * 100)), "less" if v < 0 else "more"]
	return "?"


static func ids(db: CardDB, scope: String) -> Array:
	var out: Array = db.perks.keys().filter(func(id: String) -> bool: return db.perks[id].get("scope", "") == scope)
	out.sort()
	return out


static func validate(p: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var where := "perk '%s'" % p.get("id", "")
	var scope := str(p.get("scope", ""))
	if scope not in SCOPES:
		errs.append("%s: bad scope '%s'" % [where, scope])
	for k in p.get("mods", {}):
		if not MODS.has(k):
			errs.append("%s: unknown mod '%s'" % [where, k])
	if scope == "rig":
		if int(p.get("max_rank", 0)) < 1 or int(p.get("cost", 0)) < 1:
			errs.append("%s: rig perks need max_rank and cost >= 1" % where)
		if p.has("pickup") or (p.has("triggers") and not p.get("capstone", false)):
			errs.append("%s: rig perks use mods only (capstones may add triggers)" % where)
	for trig in p.get("triggers", []):
		if trig.get("on", "") not in Talismans.TRIGGERS:
			errs.append("%s: bad trigger '%s'" % [where, trig.get("on", "")])
		for e in trig.get("effects", []):
			errs.append_array(Effects.validate(e, where))
	for o in p.get("pickup", []):
		errs.append_array(RunOutcomes.validate(o, where))
	return errs
