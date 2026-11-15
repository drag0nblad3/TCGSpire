class_name LoginBonus
extends RefCounted
## Daily login bonus: one claim per calendar day (device date). Every day pays one cache
## (balance.login.pack, a data cache; day 7 upgrades it to a Zero-day cache via balance.login.packs)
## plus balance.login.scrap[day - 1] scrap, then the cycle starts again at day 1. A missed day never resets progress: the next claim
## is simply the next day of the cycle.
##
## Profile.login = {"last": date of the last claim, "day": last day claimed (0-7), "claims": lifetime}.

const CYCLE := 7


static func can_claim(p: Profile, date: String) -> bool:
	return str(p.login.get("last", "")) != date


## The cycle day the next claim pays (1-7).
static func next_day(p: Profile) -> int:
	return int(p.login.get("day", 0)) % CYCLE + 1


## What a cycle day pays: {"scrap": n, "packs": [pack kinds]}: balance.login.scrap[day - 1]
## scrap and one cache, balance.login.pack unless balance.login.packs maps the day ("7") to another kind.
static func reward(db: CardDB, day: int) -> Dictionary:
	var cfg: Dictionary = db.balance.get("login", {})
	var scrap: Array = cfg.get("scrap", [])
	var out := {"scrap": int(scrap[day - 1]) if day - 1 < scrap.size() else 0, "packs": []}
	var kind := str(cfg.get("packs", {}).get(str(day), cfg.get("pack", "")))
	if kind != "":
		out["packs"].append(kind)
	return out


## "+15 scrap, +1 data cache", "+25 scrap, +1 Zero-day cache".
static func reward_text(db: CardDB, day: int) -> String:
	var r := reward(db, day)
	var bits: Array[String] = []
	if int(r["scrap"]) > 0:
		bits.append("+%d %s" % [r["scrap"], Palette.w("dust").to_lower()])
	for k in r["packs"]:
		bits.append("+1 %s" % (PackArt.title(db, k).to_lower() if k == Packs.NORMAL else PackArt.title(db, k)))
	return ", ".join(bits)


## Claims today's bonus. Returns {"day", "scrap", "packs"}, or {} if already claimed today.
static func claim(db: CardDB, p: Profile, date: String) -> Dictionary:
	if not can_claim(p, date):
		return {}
	var day := next_day(p)
	var r := reward(db, day)
	p.collection.dust += int(r["scrap"])
	for k in r["packs"]:
		p.add_packs(k, 1)
	p.login["last"] = date
	p.login["day"] = day
	p.login["claims"] = int(p.login.get("claims", 0)) + 1
	return {"day": day, "scrap": r["scrap"], "packs": r["packs"]}
