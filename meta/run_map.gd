class_name RunMap
extends RefCounted
## Branching act map: rows of nodes, each linked to 1-2 nodes in the next row,
## ending in a single boss. Generated from a seed; all layout rules come from
## balance.json "map".
##   node: {"id": int, "row": int, "col": int, "type": String, "next": [ids], "encounter": String}
## Walls (balance map.walls) make the Stack a little maze-like. Each is a short
## segment in map space (x = relative column 0..1, y = row):
##   {"kind": "h"|"v", "a": [x, y], "b": [x, y], "cut": [[from, to], ...]}
## Any link a wall crosses is cut. A node left with no way up gets the nearest
## unwalled diagonal instead, so every node can still climb to the Core. Nodes the
## walls seal off (unreachable from the bottom) become "vault" nodes: only a jump
## (perk mod "jumps") gets you in, and they pay out more.

const TYPES := ["fight", "elite", "rest", "shop", "event", "treasure", "vault", "boss"]
const JUMP_REACH := 0.36  # how far sideways (relative width) a jump reaches

var nodes: Array = []
var rows: Array = []  # row -> [node ids]
var act := 1
var walls: Array = []
var _max_vaults := 2


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
	# Walls live in map space: x = relative column position 0..1, y = row.
	# Gaps between floors 0 .. rows-3 can hold walls (never the rest row or the Core).
	var last_gap := rows.size() - 3
	var n_h := rng.range_i(int(cfg.get("h_min", 2)), int(cfg.get("h_max", 3)))
	var n_v := rng.range_i(int(cfg.get("v_min", 1)), int(cfg.get("v_max", 2)))
	_max_vaults = int(cfg.get("max_vaults", 2))
	var tries := 0
	while (n_h > 0 or n_v > 0) and tries < 60:
		tries += 1
		var w := {}
		if n_h > 0:
			# Horizontal: across one floor gap, about one or two columns wide.
			var gap := rng.range_i(1, last_gap - 1)
			var cx := rng.roll()
			var half := 0.15 if rng.chance(0.5) else 0.25
			# Sits low in the gap, clear of the node labels drawn under the floor above.
			w = {"kind": "h", "a": [clampf(cx - half, 0.02, 0.98), gap + 0.33], "b": [clampf(cx + half, 0.02, 0.98), gap + 0.33]}
		else:
			# Vertical: between two columns, one or two floor gaps tall.
			var gap := rng.range_i(1, last_gap - 1)
			var x: float = [0.25, 0.333, 0.5, 0.667, 0.75][rng.range_i(0, 4)]
			if not (_clear_of_nodes(gap, x) and _clear_of_nodes(gap + 1, x)):
				continue
			var tall := gap + 1 < last_gap and rng.chance(0.5) and _clear_of_nodes(gap + 2, x)
			w = {"kind": "v", "a": [x, gap + 0.2], "b": [x, gap + (1.8 if tall else 0.8)]}
		if _try_wall(w):
			if w["kind"] == "h":
				n_h -= 1
			else:
				n_v -= 1
	_mark_vaults()


func _clear_of_nodes(r: int, x: float) -> bool:
	for id in rows[r]:
		if absf(_rel(nodes[id]) - x) < 0.1:
			return false
	return true


## Cuts every link the wall crosses, then reroutes any node left without a way up
## along a diagonal that crosses no wall. Rejected (nothing changes) if that fails
## or the wall cuts nothing.
func _try_wall(w: Dictionary) -> bool:
	var before := nodes.duplicate(true)
	var cut: Array = []
	for n in nodes:
		for to in n["next"].duplicate():
			if _crosses(n["id"], to, w):
				n["next"].erase(to)
				cut.append([n["id"], to])
	w["cut"] = cut
	walls.append(w)
	var ok := not cut.is_empty()
	if ok:
		for n in nodes:
			if n["type"] != "boss" and n["next"].is_empty() and not _reroute(n["id"]):
				ok = false
				break
	if ok:
		# Few vaults, and each one a single jump from a node you can walk to.
		var seen := _reachable()
		var sealed := 0
		for n in nodes:
			if seen.has(n["id"]):
				continue
			sealed += 1
			var row_below: Array = rows[int(n["row"]) - 1]
			if not row_below.any(func(x: int) -> bool: return seen.has(x) and absf(_rel(nodes[x]) - _rel(n)) <= JUMP_REACH):
				ok = false
		if sealed > _max_vaults:
			ok = false
	if not ok:
		walls.pop_back()
		nodes = before
	return ok


## Adds the nearest diagonal up that crosses no wall.
func _reroute(id: int) -> bool:
	var node: Dictionary = nodes[id]
	var options: Array = rows[node["row"] + 1].duplicate()
	options.sort_custom(func(a: int, b: int) -> bool: return absf(_rel(nodes[a]) - _rel(node)) < absf(_rel(nodes[b]) - _rel(node)))
	for to in options:
		if absf(_rel(nodes[to]) - _rel(node)) > 0.45:
			break
		if not _link_walled(id, to):
			_add_link(node, to)
			return true
	return false


func _link_walled(a: int, b: int) -> bool:
	for w in walls:
		if _crosses(a, b, w):
			return true
	return false


func cut_by(a: int, b: int, w: Dictionary) -> bool:
	return _crosses(a, b, w)


func _crosses(a: int, b: int, w: Dictionary) -> bool:
	var p1 := Vector2(_rel(nodes[a]), float(nodes[a]["row"]))
	var p2 := Vector2(_rel(nodes[b]), float(nodes[b]["row"]))
	return Geometry2D.segment_intersects_segment(p1, p2, Vector2(w["a"][0], w["a"][1]), Vector2(w["b"][0], w["b"][1])) != null


## Nodes the walls seal off (no way in without a jump) become vaults: richer stops.
func _mark_vaults() -> void:
	var seen := _reachable()
	for n in nodes:
		if not seen.has(n["id"]):
			n["type"] = "vault"
			n["encounter"] = ""


func _reachable() -> Dictionary:
	var seen := {}
	var frontier: Array = rows[0].duplicate()
	while not frontier.is_empty():
		var id: int = frontier.pop_back()
		if seen.has(id):
			continue
		seen[id] = true
		frontier.append_array(nodes[id]["next"])
	return seen


## Jump targets from a node: nodes on the next floor within a diagonal step that
## have no normal link from it. A jump goes through walls.
func jump_targets(id: int) -> Array:
	var node: Dictionary = nodes[id]
	if node["row"] + 1 >= rows.size() - 1:
		return []
	var out: Array = []
	for to in rows[node["row"] + 1]:
		if to not in node["next"] and absf(_rel(nodes[to]) - _rel(node)) <= JUMP_REACH:
			out.append(to)
	return out


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
	var sym := {"fight": "F", "elite": "E", "rest": "R", "shop": "$", "event": "?", "treasure": "T", "vault": "V", "boss": "B"}
	var lines: Array[String] = []
	for r in range(rows.size() - 1, -1, -1):
		var parts: Array[String] = []
		for id in rows[r]:
			parts.append("%s%s" % [sym[nodes[id]["type"]], ",".join(nodes[id]["next"].map(func(x: int) -> String: return str(x)))])
		lines.append("%2d: %s" % [r, "  ".join(parts)])
	return "\n".join(lines)
