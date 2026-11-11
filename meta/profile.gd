class_name Profile
extends RefCounted
## Everything that persists between runs. Saved as versioned JSON in user://.
## When the format changes: bump SAVE_VERSION and add a step to _migrate().

const SAVE_VERSION := 1
const DEFAULT_PATH := "user://profile.json"

var collection := Collection.new()
var unlocks: Dictionary = {}
var stats: Dictionary = {"runs": 0, "wins": 0, "packs_opened": 0}
var packs_unopened := 0


static func new_player(db: CardDB) -> Profile:
	var p := Profile.new()
	var start: Dictionary = db.balance.get("starter_collection", {})
	for id in start:
		p.collection.add(id, int(start[id]))
	return p


func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"collection": collection.to_dict(),
		"unlocks": unlocks,
		"stats": stats,
		"packs_unopened": packs_unopened,
	}


static func from_dict(d: Dictionary) -> Profile:
	d = _migrate(d)
	var p := Profile.new()
	p.collection = Collection.from_dict(d.get("collection", {}))
	p.unlocks = d.get("unlocks", {})
	for k in d.get("stats", {}):
		p.stats[k] = int(d["stats"][k])
	p.packs_unopened = int(d.get("packs_unopened", 0))
	return p


static func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 1))
	# Example for the future:
	# if v < 2:
	# 	d["new_field"] = default
	# 	v = 2
	d["version"] = v
	return d


func open_pack(db: CardDB, rng: GameRng) -> Array:
	if packs_unopened <= 0:
		return []
	packs_unopened -= 1
	stats["packs_opened"] = int(stats.get("packs_opened", 0)) + 1
	var cards := Packs.open(db, rng)
	for c in cards:
		collection.add(c["id"], 1, c["foil"])
	return cards


func save(path: String = DEFAULT_PATH) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	# Write-then-rename so a crash mid-save never corrupts the profile.
	return DirAccess.rename_absolute(tmp, path)


static func load_or_new(db: CardDB, path: String = DEFAULT_PATH) -> Profile:
	if not FileAccess.file_exists(path):
		return new_player(db)
	var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if v is Dictionary:
		return from_dict(v)
	push_error("Corrupt profile at %s, starting fresh" % path)
	return new_player(db)
