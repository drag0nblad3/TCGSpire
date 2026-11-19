class_name CombatUndo
extends RefCounted
## Undo for misclicks: takes back the last program you ran (or daemon you shut down) this turn,
## but only while that action showed you nothing new. A draw, a reshuffle, any random roll,
## a new enemy, a boss phase or a cleared signal jam closes the window, so undo can't be used
## to peek and take back a risky play. End turn closes it too.
##
## A snapshot is a deep copy of Combat's live state: Fighters and CardInstances are cloned
## (shared references stay shared), card defs, the run deck (`origin`), the card DB and the
## implant/perk defs stay by reference, and the events log is cut back to its old length.

## Event types that show the player something they didn't know before the action.
const REVEALS := ["draw", "reshuffle", "spawn", "hatch", "phase", "twin_down", "combat_end"]
## Combat vars that are never copied (shared data) or are handled on their own.
const SKIP := ["db", "rng", "talismans", "perks", "events", "undo_snap", "undo_on"]


static func snapshot(c: Combat) -> Dictionary:
	var map := {}
	var vars := {}
	for p in c.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p["name"]
		if n in SKIP:
			continue
		vars[n] = _clone(c.get(n), map)
	return {
		"vars": vars,
		"rng": c.rng.get_state(),
		"events": c.events.size(),
		"jammed": _jammed(c),
	}


## True when everything that happened since `snap` was already visible to the player.
static func revealed_nothing(c: Combat, snap: Dictionary) -> bool:
	if c.rng.get_state() != int(snap["rng"]):
		return false
	for i in range(int(snap["events"]), c.events.size()):
		if str(c.events[i].get("t", "")) in REVEALS:
			return false
	# Exposed (or an Interrupt) clearing a signal jam shows a hidden intent.
	for id in snap["jammed"]:
		if id not in _jammed(c):
			return false
	return true


static func restore(c: Combat, snap: Dictionary) -> void:
	var vars: Dictionary = snap["vars"]
	for n in vars:
		c.set(n, vars[n])
	c.rng.set_state(int(snap["rng"]))
	c.events.resize(int(snap["events"]))


static func _jammed(c: Combat) -> Array:
	var out := []
	for en: Fighter in c.enemies:
		if BossRules.jammed(c, en):
			out.append(en.id)
	return out


static func _clone(v: Variant, map: Dictionary) -> Variant:
	match typeof(v):
		TYPE_ARRAY:
			var a: Array = (v as Array).duplicate(false)
			for i in a.size():
				a[i] = _clone(a[i], map)
			return a
		TYPE_DICTIONARY:
			var d: Dictionary = (v as Dictionary).duplicate(false)
			for k in d:
				d[k] = _clone(d[k], map)
			return d
		TYPE_OBJECT:
			if v is Fighter or v is CardInstance:
				return _clone_object(v, map)
			return v
	return v


static func _clone_object(o: Object, map: Dictionary) -> Object:
	var key := o.get_instance_id()
	if map.has(key):
		return map[key]
	var out: Object
	if o is CardInstance:
		out = CardInstance.new((o as CardInstance).def, (o as CardInstance).upgraded)
	else:
		out = Fighter.new()
	map[key] = out
	for p in o.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p["name"]
		# Card defs and the run deck copy a combat card came from are shared, never copied.
		if n == "def" or n == "origin":
			out.set(n, o.get(n))
		else:
			out.set(n, _clone(o.get(n), map))
	return out
