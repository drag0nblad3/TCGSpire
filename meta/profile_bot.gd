class_name ProfileBot
extends RefCounted
## Builds test profiles for sims (tools/sim.gd profile=...):
##   veteran(n): a player after n bot runs (sims: experienced = 10, veteran = 39), opening every pack and spending
##               rep/dust the way a sensible player would (rig ranks, firmware).
##   maxed():    every card owned, every rig rank, every card in firmware with a
##               baked mod, max starting picks.

## Rig perks in the order a player would likely buy them (cheap survival first).
const RIG_ORDER := ["chassis", "hardpoint", "contract_killer", "cred_stash", "field_clinic", "repair_drones", "boot_firewall",
	"cooling_loop", "salvage_rights", "reward_reroute", "fence_network", "signal_jammer", "pirate_coupons", "signal_override",
	"mod_cache", "wider_scan", "wider_menu", "seed_subroutine",
	"thermal_runaway", "liquidity_engine", "regrowth_protocol", "absolute_zero", "hive_link", "dead_air_protocol"]
## Mods worth baking, best first.
const MOD_ORDER := ["overclocked", "looped", "hardened_payload", "buffered", "shielded", "cached", "infected", "exposing",
	"boosted_daemon", "swarm_hook", "persistent", "leech", "preloaded", "lean_build", "volatile_payload"]


static func veteran(db: CardDB, runs: int = 39, seed_in: int = 7) -> Profile:
	var p := Profile.new_player(db)
	var jobs := Jobs.board(db)
	for i in runs:
		var res := RunBot.play(db, p, seed_in * 1000 + i, 0, jobs[i % jobs.size()])
		p.finish_run(db, res["run"])
		while p.packs_unopened > 0:
			p.open_pack(db, GameRng.new(seed_in * 7919 + p.stats.get("packs_opened", 0)))
		spend(db, p)
	return p


## Spends rep and dust until nothing useful is affordable.
static func spend(db: CardDB, p: Profile) -> void:
	for guard in 200:
		var bought := false
		# Firmware first for the cards it actually plays most.
		var played: Array = p.mastery.keys()
		played.sort_custom(func(a: String, b: String) -> bool: return int(p.mastery[a]) > int(p.mastery[b]))
		for id in played:
			if p.flash_firmware(db, id):
				bought = true
				break
		if not bought:
			for id in RIG_ORDER:
				if p.buy_rig(db, id):
					bought = true
					break
		if not bought:
			for id in played:
				var m := best_mod(db, id)
				if m != "" and p.bake_firmware_mod(db, id, m):
					bought = true
					break
		if not bought:
			for id in ["jab", "brace"]:
				if p.flash_firmware(db, id):
					bought = true
					break
		if not bought:
			return


static func best_mod(db: CardDB, id: String) -> String:
	var c := CardInstance.new(db.card(id), true)
	for m in MOD_ORDER:
		if db.mods.has(m) and CardMods.can_apply(db.mod(m), c):
			return m
	return ""


static func maxed(db: CardDB) -> Profile:
	var p := Profile.new_player(db)
	for id in db.cards:
		var c: CardDef = db.cards[id]
		if c.rarity == "curse":
			continue
		if c.rarity != "starter":
			p.collection.add(id, maxi(3 - p.collection.count(id), 0))
		p.mastery[id] = 100
		p.firmware[id] = Profile.firmware_max(db)
		var m := best_mod(db, id)
		if m != "":
			p.firmware_mods[id] = m
	for id in db.perks:
		if db.perks[id].get("scope", "") == "rig":
			p.rig[id] = int(db.perks[id]["max_rank"])
	p.unlocks["swap_picks"] = 4
	p.xp = Profile.xp_for_level(Profile.LEVEL_CAP)
	p.max_heat = db.balance.get("heat", []).size()
	return p


static func summary(db: CardDB, p: Profile) -> String:
	var ranks := 0
	for id in p.rig:
		ranks += int(p.rig[id])
	var rep := 0
	for f in p.rep:
		rep += int(p.rep[f])
	return "level %d  picks %d  cards %d  rig ranks %d  firmware %d (+%d mods)  rep left %d  dust %d" % [p.level(), p.starter_picks(db),
		p.collection.owned_ids().size(), ranks, p.firmware.size(), p.firmware_mods.size(), rep, p.collection.dust]
