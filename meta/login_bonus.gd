class_name LoginBonus
extends RefCounted
## Daily login bonus: one claim per calendar day (device date). Days 1-6 pay
## balance.login.scrap[day - 1] scrap, day 7 pays balance.login.packs packs, then the
## cycle starts again at day 1. A missed day never resets progress: the next claim
## is simply the next day of the cycle.
##
## Profile.login = {"last": date of the last claim, "day": last day claimed (0-7), "claims": lifetime}.

const CYCLE := 7


static func can_claim(p: Profile, date: String) -> bool:
	return str(p.login.get("last", "")) != date


## The cycle day the next claim pays (1-7).
static func next_day(p: Profile) -> int:
	return int(p.login.get("day", 0)) % CYCLE + 1


## What a cycle day pays: {"scrap": n, "packs": n}.
static func reward(db: CardDB, day: int) -> Dictionary:
	var cfg: Dictionary = db.balance.get("login", {})
	if day >= CYCLE:
		return {"scrap": 0, "packs": int(cfg.get("packs", 1))}
	var scrap: Array = cfg.get("scrap", [])
	return {"scrap": int(scrap[mini(day - 1, scrap.size() - 1)]) if not scrap.is_empty() else 0, "packs": 0}


## "+20 scrap", "+1 data cache".
static func reward_text(db: CardDB, day: int) -> String:
	var r := reward(db, day)
	var bits: Array[String] = []
	if int(r["scrap"]) > 0:
		bits.append("+%d %s" % [r["scrap"], Palette.w("dust").to_lower()])
	if int(r["packs"]) > 0:
		bits.append("+%d %s" % [r["packs"], Palette.w("pack").to_lower() if int(r["packs"]) == 1 else Palette.w("packs").to_lower()])
	return ", ".join(bits)


## Claims today's bonus. Returns {"day", "scrap", "packs"}, or {} if already claimed today.
static func claim(db: CardDB, p: Profile, date: String) -> Dictionary:
	if not can_claim(p, date):
		return {}
	var day := next_day(p)
	var r := reward(db, day)
	p.collection.dust += int(r["scrap"])
	p.add_packs(Packs.NORMAL, int(r["packs"]))
	p.login["last"] = date
	p.login["day"] = day
	p.login["claims"] = int(p.login.get("claims", 0)) + 1
	return {"day": day, "scrap": r["scrap"], "packs": r["packs"]}
