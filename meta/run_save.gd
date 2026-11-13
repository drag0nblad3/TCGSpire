class_name RunSave
extends RefCounted
## The run in progress, saved next to the profile so closing the app (or
## "Save & quit") never loses it. Written at every screen change of a run:
##   {"version", "run": RunState.to_dict(), "resume": where to pick up}
## resume: {"screen": "map"} | {"screen": "node"} (replay the node just entered:
## a fight restarts from its first turn) | {"screen": "reward", ...} | {"screen": "perks", ...}.
## Stored with var_to_str so ints stay ints (JSON would turn them into floats).

const VERSION := 1
const DEFAULT_PATH := "user://run.save"


static func save(run: RunState, resume: Dictionary, path: String = DEFAULT_PATH) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(var_to_str({"version": VERSION, "run": run.to_dict(), "resume": resume}))
	f.close()
	return DirAccess.rename_absolute(tmp, path)


static func exists(path: String = DEFAULT_PATH) -> bool:
	return FileAccess.file_exists(path)


## {"run": RunState, "resume": Dictionary}, or {} if there is no usable save.
static func load_run(db: CardDB, path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var v: Variant = str_to_var(FileAccess.get_file_as_string(path))
	if not (v is Dictionary) or int(v.get("version", 0)) != VERSION or not (v.get("run") is Dictionary):
		push_warning("Unreadable run save at %s, ignoring it" % path)
		return {}
	return {"run": RunState.from_dict(db, v["run"]), "resume": v.get("resume", {"screen": "map"})}


static func clear(path: String = DEFAULT_PATH) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
