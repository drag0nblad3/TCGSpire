class_name RunMap
extends RefCounted
## Branching act map: rows of nodes, each linked to 1-2 nodes in the next row,
## ending in a single boss. Generated from a seed; all layout rules come from
## balance.json "map".
##   node: {"id": int, "row": int, "col": int, "type": String, "next": [ids], "encounter": String}

const TYPES := ["fight", "elite", "rest", "shop", "event", "treasure", "boss"]

var nodes: Array = []
var rows: Array = []  # row -> [node ids]


static func generate(db: CardDB, rng: GameRng) -> RunMap:
	var cfg: Dictionary = db.balance.get("map", {})
	var m := RunMap.new()
	var n_rows := int(cfg.get("rows", 12))
	var width := int(cfg.get("width", 4))
	for r in n_rows:
		var count := width if r > 0 else 3
		count = rng.range_i(maxi(2, count - 1), count)
		var row_ids: Array = []
		for col in count:
			var node := {"id": m.nodes.size(), "row": r, "col": col, "cols": count, "type": "", "next": [], "encounter": ""}
			node["type"] = m._pick_type(cfg, r, n_rows, rng)
			m.nodes.append(node)
			row_ids.append(node["id"])
		m.rows.append(row_ids)
	var boss := {"id": m.nodes.size(), "row": n_rows, "col": 0, "cols": 1, "type": "boss", "next": [], "encounter": ""}
	m.nodes.append(boss)
	m.rows.append([boss["id"]])
	m._link(rng)
	m._assign_encounters(db, rng)
	return m


func _pick_type(cfg: Dictionary, r: int, n_rows: int, rng: GameRng) -> String:
	if r == 0:
		return "fight"
	if r == n_rows - 1:
		return "rest"
	if r == int(n_rows / 2.0):
		return "treasure"
	var w: Dictionary = cfg.get("weights", {"fight": 1}).duplicate()
	if r < int(cfg.get("elite_from_row", 4)):
		w.erase("elite")
	if r < 3:
		w.erase("rest")
	return rng.weighted(w)


## Each node links to the nearest node(s) in the next row by relative position.
## Every next-row node is guaranteed at least one incoming link.
func _link(rng: GameRng) -> void:
	for r in rows.size() - 1:
		var cur: Array = rows[r]
		var nxt: Array = rows[r + 1]
		var reached := {}
		for id in cur:
			var node: Dictionary = nodes[id]
			var pos := _rel(node)
			var best := _nearest(nxt, pos)
			_add_link(node, best)
			reached[best] = true
			if nxt.size() > 1 and rng.chance(0.45):
				var alt_idx := clampi(nxt.find(best) + (1 if rng.chance(0.5) else -1), 0, nxt.size() - 1)
				_add_link(node, nxt[alt_idx])
				reached[nxt[alt_idx]] = true
		for nid in nxt:
			if not reached.has(nid):
				var src_id: int = _nearest(cur, _rel(nodes[nid]))
				_add_link(nodes[src_id], nid)


func _rel(node: Dictionary) -> float:
	return (float(node["col"]) + 0.5) / float(node["cols"])


func _nearest(ids: Array, pos: float) -> int:
	var best: int = ids[0]
	for id in ids:
		if absf(_rel(nodes[id]) - pos) < absf(_rel(nodes[best]) - pos):
			best = id
	return best


func _add_link(node: Dictionary, to_id: int) -> void:
	if to_id not in node["next"]:
		node["next"].append(to_id)
		node["next"].sort()


func _assign_encounters(db: CardDB, rng: GameRng) -> void:
	for node in nodes:
		var kind := ""
		match node["type"]:
			"fight":
				kind = "normal"
			"elite":
				kind = "elite"
			"boss":
				kind = "boss"
		if kind == "":
			continue
		var tier := 1 if node["row"] < 4 else 2
		var pool: Array = []
		for id in db.encounters:
			var enc: Dictionary = db.encounters[id]
			if str(enc.get("kind", "normal")) == kind and (kind != "normal" or int(enc.get("tier", 1)) == tier):
				pool.append(id)
		pool.sort()
		node["encounter"] = str(rng.pick(pool)) if not pool.is_empty() else ""


func start_nodes() -> Array:
	return rows[0].duplicate()


func node(id: int) -> Dictionary:
	return nodes[id]


## Compact text rendering, one row per line (boss at top). Handy for debugging.
func ascii() -> String:
	var sym := {"fight": "F", "elite": "E", "rest": "R", "shop": "$", "event": "?", "treasure": "T", "boss": "B"}
	var lines: Array[String] = []
	for r in range(rows.size() - 1, -1, -1):
		var parts: Array[String] = []
		for id in rows[r]:
			parts.append("%s%s" % [sym[nodes[id]["type"]], ",".join(nodes[id]["next"].map(func(x: int) -> String: return str(x)))])
		lines.append("%2d: %s" % [r, "  ".join(parts)])
	return "\n".join(lines)
