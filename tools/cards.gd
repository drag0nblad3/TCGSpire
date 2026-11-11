extends SceneTree
## Prints every card as one compact line with generated rules text. Reading this
## is much cheaper than reading the JSON.   scripts/cards.sh [filter]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var filter: String = args[0] if args.size() > 0 else ""
	var db := CardDB.load_from(CardDB.DATA_ROOT)
	var ids := db.cards.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		var ca: CardDef = db.cards[a]
		var cb: CardDef = db.cards[b]
		return [ca.faction, CardDef.RARITIES.find(ca.rarity), a] < [cb.faction, CardDef.RARITIES.find(cb.rarity), b])
	for id in ids:
		var c: CardDef = db.cards[id]
		var line := "%-15s %-7s %-8s %-6s %d | %s || + %d | %s" % [id, c.faction, c.rarity, c.type, c.cost, c.get_text(false), c.get_cost(true), c.get_text(true)]
		if filter == "" or filter in line:
			print(line)
	quit(0)
