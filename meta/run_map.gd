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
		var gap := rng.range_i(1, last_gap - 1)
		var w := _h_wall(gap, rng) if n_h > 0 else _v_wall(gap, last_gap, rng)
		if w.is_empty():
			continue
		if _try_wall(w):
			if w["kind"] == "h":
				n_h -= 1
			else:
				n_v -= 1
	_mark_vaults()


## Horizontal wall low in a floor gap, centred on the 1-2 links it cuts.
func _h_wall(gap: int, rng: GameRng) -> Dictionary:
	var y := gap + 0.33  # clear of the node labels drawn under the floor above
	var xs: Array = []
	for id in rows[gap]:
		for to in nodes[id]["next"]:
			var a := _rel(nodes[id])
			xs.append(a + (_rel(nodes[to]) - a) * (y - gap))
	if xs.is_empty():
		return {}
	xs.sort()
	var i := rng.range_i(0, xs.size() - 1)
	var cover: Array = [xs[i]]
	if i + 1 < xs.size() and xs[i + 1] - xs[i] < 0.3 and xs[i + 1] - xs[i] > 0.04 and rng.chance(0.45):
		cover.append(xs[i + 1])
	var mid: float = (cover[0] + cover[-1]) / 2.0
	var half: float = (cover[-1] - cover[0]) / 2.0 + 0.08
	# Must not clip a link it isn't centred on.
	for x in xs:
		if x not in cover and absf(x - mid) <= half + 0.02:
			return {}
	return {"kind": "h", "a": [mid - half, y], "b": [mid + half, y], "cuts": cover.size()}


## Vertical wall between two columns, centred on the 1-2 diagonals it cuts.
func _v_wall(gap: int, last_gap: int, rng: GameRng) -> Dictionary:
	var x: float = [0.25, 0.333, 0.5, 0.667, 0.75][rng.range_i(0, 4)]
	if not (_clear_of_nodes(gap, x) and _clear_of_nodes(gap + 1, x)):
		return {}
	var tall := gap + 1 < last_gap and _clear_of_nodes(gap + 2, x)
	var ys: Array = []
	for r in ([gap, gap + 1] if tall else [gap]):
		for id in rows[r]:
			for to in nodes[id]["next"]:
				var a := _rel(nodes[id])
				var b := _rel(nodes[to])
				if (a - x) * (b - x) < 0.0:
					ys.append(r + (x - a) / (b - a))
	if ys.is_empty():
		return {}
	ys.sort()
	var i := rng.range_i(0, ys.size() - 1)
	var cover: Array = [ys[i]]
	if i + 1 < ys.size() and ys[i + 1] - ys[i] < 0.9 and rng.chance(0.45):
		cover.append(ys[i + 1])
	var mid: float = (cover[0] + cover[-1]) / 2.0
	var half: float = maxf((cover[-1] - cover[0]) / 2.0 + 0.12, 0.26)
	for y in ys:
		if y not in cover and absf(y - mid) <= half + 0.03:
			return {}
	return {"kind": "v", "a": [x, mid - half], "b": [x, mid + half], "cuts": cover.size()}


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
	var expected := int(w.get("cuts", cut.size()))
	w.erase("cuts")
	w["cut"] = cut
	walls.append(w)
	var ok := not cut.is_empty() and cut.size() == expected
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
			"vault":
				kind = "elite"  # every vault is guarded by an elite
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
