class_name RunMap
extends RefCounted
## Branching act map: rows of nodes, each linked to 1-2 nodes in the next row,
## ending in a single boss. Generated from a seed; all layout rules come from
## balance.json "map".
##   node: {"id": int, "row": int, "col": int, "type": String, "next": [ids], "encounter": String}
## Walls (balance map.walls) make the Stack a little maze-like. Each is short:
##   {"kind": "h", "links": [[from, to], ...]}  1-2 cut links between two floors
##   {"kind": "v", "pairs": [[a, b], ...]}      1-2 floors where two row neighbours
##                                               are split (blocks a sidestep)
## A horizontal cut only happens if its source keeps another way up and its target
## another way in, so the boss is always reachable without sidesteps.

const TYPES := ["fight", "elite", "rest", "shop", "event", "treasure", "boss"]

var nodes: Array = []
var rows: Array = []  # row -> [node ids]
var act := 1
var walls: Array = []


## targets: crews the job runs against; their faction encounters replace a share
## (balance.jobs.faction_encounter_share) of fights and elites, and most bosses
## (faction_boss_share).
## boss_faction: if set (and that crew has a boss this act), the boss is always theirs.
static func generate(db: CardDB, rng: GameRng, act: int = 1, targets: Array = [], boss_faction: String = "") -> RunMap:
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
	m._build_walls(cfg.get("walls", {}), rng.fork("walls"))
	m.act = act
	m._assign_encounters(db, rng, targets, boss_faction)
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


func _build_walls(cfg: Dictionary, rng: GameRng) -> void:
	var h := float(cfg.get("h_chance", 0.0))
	var v := float(cfg.get("v_chance", 0.0))
	var long_p := float(cfg.get("two_chance", 0.4))
	# Horizontal: between floors r and r+1, never into the last rest row or the boss.
	for r in range(0, rows.size() - 3):
		if not rng.chance(h):
			continue
		var links := _links_by_x(r)
		var order := range(links.size())
		rng.shuffle(order)
		for i in order:
			if not _can_cut(links[i]):
				continue
			var cut: Array = [links[i]]
			_cut(links[i])
			if rng.chance(long_p):
				for j in [i + 1, i - 1]:
					if j >= 0 and j < links.size() and _can_cut(links[j]):
						cut.append(links[j])
						_cut(links[j])
						break
			walls.append({"kind": "h", "links": cut})
			break
	# Vertical: splits two neighbours on a floor, sometimes the floor above too.
	for r in range(0, rows.size() - 1):
		if rows[r].size() < 2 or not rng.chance(v) or _side_walled_row(r):
			continue
		var c := rng.range_i(0, rows[r].size() - 2)
		var pairs: Array = [[rows[r][c], rows[r][c + 1]]]
		var x := (_rel(nodes[rows[r][c]]) + _rel(nodes[rows[r][c + 1]])) / 2.0
		if r + 1 < rows.size() - 1 and rows[r + 1].size() >= 2 and rng.chance(long_p):
			var above := _pair_near(r + 1, x)
			if not above.is_empty():
				pairs.append(above)
		walls.append({"kind": "v", "pairs": pairs})


## Upward links leaving row r, ordered left to right by where the wire crosses.
func _links_by_x(r: int) -> Array:
	var links: Array = []
	for id in rows[r]:
		for to in nodes[id]["next"]:
			links.append([id, to])
	links.sort_custom(func(a: Array, b: Array) -> bool:
		return _rel(nodes[a[0]]) + _rel(nodes[a[1]]) < _rel(nodes[b[0]]) + _rel(nodes[b[1]]))
	return links


func _can_cut(link: Array) -> bool:
	var src: Dictionary = nodes[link[0]]
	if src["next"].size() < 2 or link[1] not in src["next"]:
		return false
	for other in rows[src["row"]]:
		if other != link[0] and link[1] in nodes[other]["next"]:
			return true
	return false


func _cut(link: Array) -> void:
	nodes[link[0]]["next"].erase(link[1])


func _pair_near(r: int, x: float) -> Array:
	for c in rows[r].size() - 1:
		var a: int = rows[r][c]
		var b: int = rows[r][c + 1]
		# Only stack a wall when the gap lines up, so it reads as one straight wall.
		if absf((_rel(nodes[a]) + _rel(nodes[b])) / 2.0 - x) < 0.05:
			return [a, b]
	return []


func _side_walled_row(r: int) -> bool:
	for w in walls:
		if w["kind"] == "v":
			for pair in w["pairs"]:
				if int(nodes[pair[0]]["row"]) == r:
					return true
	return false


## Nodes beside this one on the same floor that no vertical wall splits off.
func side_nodes(id: int) -> Array:
	var node: Dictionary = nodes[id]
	var out: Array = []
	for sid in rows[node["row"]]:
		if absi(int(nodes[sid]["col"]) - int(node["col"])) == 1 and not side_blocked(id, sid):
			out.append(sid)
	return out


func side_blocked(a: int, b: int) -> bool:
	for w in walls:
		if w["kind"] == "v":
			for pair in w["pairs"]:
				if (int(pair[0]) == a and int(pair[1]) == b) or (int(pair[0]) == b and int(pair[1]) == a):
					return true
	return false


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


func _assign_encounters(db: CardDB, rng: GameRng, targets: Array = [], boss_faction: String = "") -> void:
	var jcfg: Dictionary = db.balance.get("jobs", {})
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
		var crew: Array = []
		var forced: Array = []
		for id in db.encounters:
			var enc: Dictionary = db.encounters[id]
			if int(enc.get("act", 1)) != act:
				continue
			if str(enc.get("kind", "normal")) == kind and (kind != "normal" or int(enc.get("tier", 1)) == tier):
				var f := str(enc.get("faction", ""))
				if f == "":
					pool.append(id)
				elif f in targets:
					crew.append(id)
				if kind == "boss" and f != "" and f == boss_faction:
					forced.append(id)
		pool.sort()
		crew.sort()
		forced.sort()
		if not forced.is_empty():
			node["encounter"] = str(rng.pick(forced))
			continue
		var share := float(jcfg.get("faction_boss_share" if kind == "boss" else "faction_encounter_share", 0.6))
		if not crew.is_empty() and (pool.is_empty() or rng.chance(share)):
			pool = crew
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
