extends SceneTree
## Dumps the game's own generated text (cards, enemy moves, boss rules) plus the
## glossary tables, for the data browser page. scripts/browser.sh joins it with the
## raw JSON files.   godot --headless --path . -s res://tools/export_browser.gd -- out.json


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else "/tmp/browser_text.json"
	var db := CardDB.shared()
	var cards := {}
	for id in db.cards:
		var c: CardDef = db.cards[id]
		cards[id] = {"text": c.get_text(false), "text_up": c.get_text(true) if not c.upgrade.is_empty() else "",
			"summary": c.upgrade_summary()}
	var enemies := {}
	for id in db.enemies:
		var d: Dictionary = db.enemies[id]
		var moves: Array = []
		for m in d.get("moves", []):
			moves.append(" ".join(m.get("effects", []).map(func(e: Dictionary) -> String: return Effects.describe(e))))
		var phases: Array = []
		for p in d.get("rules", {}).get("phases", []):
			var pm: Array = []
			for m in p.get("moves", []):
				pm.append(" ".join(m.get("effects", []).map(func(e: Dictionary) -> String: return Effects.describe(e))))
			phases.append(pm)
		enemies[id] = {"moves": moves, "phase_moves": phases, "rules": BossRules.describe(d.get("rules", {}))}
	var statuses := {}
	for k in Statuses.DEFS:
		statuses[k] = {"name": Lexicon.status(k), "debuff": Statuses.DEFS[k].get("debuff", false), "desc": Statuses.DEFS[k].get("desc", "")}
	var keywords := {}
	for k in CardDef.KEYWORD_DESC:
		keywords[k] = {"name": Lexicon.keyword(k), "desc": CardDef.KEYWORD_DESC[k]}
	var out := {
		"cards": cards, "enemies": enemies, "statuses": statuses, "keywords": keywords,
		"types": Lexicon.TYPE, "type_desc": CardDef.TYPE_DESC, "factions": Lexicon.FACTION, "intents": Lexicon.INTENT,
		"daemon_flags": DaemonRules.FLAGS, "trigger_labels": Talismans.LABEL, "per_sources": Effects.PER_SOURCES,
		"loop_key": Effects.LOOP_KEY, "ops": Effects.OPS,
		"rarities": CardDef.RARITIES,
	}
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("wrote %s: %d cards, %d enemies" % [out_path, cards.size(), enemies.size()])
	quit(0)
