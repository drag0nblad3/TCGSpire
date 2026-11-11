extends SceneTree
## Headless test runner. Prints ONLY failures plus a one-line summary, so the
## output stays tiny whether 5 or 500 tests run.
##   godot --headless --path . -s res://tests/run_tests.gd -- [filter]
## filter matches file or method names (substring), e.g. "combat" or "test_burn".


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var filter := args[0] if args.size() > 0 else ""
	var verbose := "-v" in args
	var db := CardDB.load_from(CardDB.DATA_ROOT)
	var passed := 0
	var failed := 0
	for f in DirAccess.get_files_at("res://tests"):
		if not (f.begins_with("test_") and f.ends_with(".gd")) or f == "test_case.gd":
			continue
		var script: GDScript = load("res://tests/" + f)
		for m in script.get_script_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			if filter != "" and filter != "-v" and not (filter in f or filter in mname):
				continue
			var t: TestCase = script.new()
			t.db = db
			t.before_each()
			t.call(mname)
			if t.failures.is_empty():
				passed += 1
				if verbose:
					print("ok   %s::%s" % [f.get_basename(), mname])
			else:
				failed += 1
				for msg in t.failures:
					print("FAIL %s::%s: %s" % [f.get_basename(), mname, msg])
	print("%s: %d passed, %d failed" % ["OK" if failed == 0 else "FAILED", passed, failed])
	quit(1 if failed > 0 else 0)
