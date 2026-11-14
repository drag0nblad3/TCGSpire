class_name ImplantTracker
extends RefCounted
## Tracks only events already presented, never the resolved combat's future state.
var counts: Dictionary = {}
var progress: Dictionary = {}
var daemons: Dictionary = {}

func consume(event: Dictionary) -> void:
	var kind := str(event.get("t", ""))
	var id := str(event.get("id", ""))
	if kind == "talisman":
		counts[id] = int(counts.get(id, 0)) + 1
	elif kind == "talisman_progress":
		progress["%s:%d" % [id, int(event.get("index", 0))]] = int(event["count"])
	elif kind == "summon":
		daemons[str(event["target"])] = true
	elif kind in ["expire", "death"]:
		daemons.erase(str(event.get("target", "")))

func badge(definition: Dictionary) -> String:
	var id := str(definition.get("id", ""))
	if definition.get("flags_while_daemon", false):
		return "ON" if not daemons.is_empty() else "OFF"
	var triggers: Array = definition.get("triggers", [])
	for i in triggers.size():
		var trigger: Dictionary = triggers[i]
		if trigger.has("every"):
			var total := int(trigger["every"])
			var n := int(progress.get("%s:%d" % [id, i], 0)) % total
			return "%d/%d" % [n, total]
	if not triggers.is_empty():
		var times := int(counts.get(id, 0))
		if triggers[0].get("on", "") == "combat_start" or triggers[0].has("turn"):
			return "USED" if times > 0 else "READY"
		return "×%d" % times
	if definition.has("run"):
		return "MAP"
	if definition.has("flags") or definition.has("daemon") or definition.has("mods"):
		return "ON"
	return "TAKEN"

func detail(definition: Dictionary) -> String:
	var id := str(definition.get("id", ""))
	var lines: Array[String] = []
	for i in definition.get("triggers", []).size():
		var trigger: Dictionary = definition["triggers"][i]
		if trigger.has("every"):
			var total := int(trigger["every"])
			var n := int(progress.get("%s:%d" % [id, i], 0)) % total
			lines.append("Progress: %d/%d qualifying events · %d until activation" % [n, total, total - n])
	if definition.has("triggers"):
		lines.append("Activated %d times this fight" % int(counts.get(id, 0)))
	elif definition.get("flags_while_daemon", false):
		lines.append("Active: daemon running" if not daemons.is_empty() else "Inactive: requires a running daemon")
	elif definition.has("run"):
		lines.append("Activates on the map")
	else:
		lines.append("Continuous bonus" if definition.has("flags") or definition.has("mods") or definition.has("daemon") else "Applied when acquired")
	return "\n".join(lines)
