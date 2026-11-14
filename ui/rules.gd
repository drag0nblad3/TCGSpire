class_name Rules
extends Control
## Rules reference overlay: a contents strip that jumps to numbered sections
## (turn flow, programs, keywords, statuses, intents, daemons, the Stack, implants,
## jobs, upgrades, collecting, firmware, heat). Status, keyword, type and intent text comes
## straight from Statuses.DEFS / CardDef.KEYWORD_DESC / TYPE_DESC / Intents.DESC,
## so new content documents itself. Open with Rules.open(node[, heading]).
##
## sections() is data only: [heading, group, entries]. An entry is a paragraph
## (String), a definition ([term, text]), a numbered step (["#", text]) or the
## intent icon legend ("@intents").

const WARD := "Firewall absorbs damage before HP and normally clears at the start of your turn. Hardened keeps all remaining Firewall, and so does any daemon or implant whose rule keeps Firewall (Gatekeeper, for one). The Liquidity Engine rig upgrade keeps 30%, rounded up."
const UNITS := "Daemons: programs that stay on your board for a few turns and change the rules while they run. They are not attackers: each one is a rule, like keeping your Firewall or striking at the end of your turn. Enemies can still hit them. A daemon's HP is its countdown: it loses 1 at the start of each of your turns and 1 for each hit it takes. Purge moves (enemy attacks aimed at daemons) take their full damage. At 0 it closes and its rule ends. Running a daemon that is already up tops its HP back up. Up to 3 can run at once."
const LEGEND := "@intents"
const GROUPS := ["In a fight", "The run", "Between runs"]

var _tap := Tap.new()
var _jump := ""
var _scroll: ScrollContainer
var _anchors := {}  # heading -> Control


static func open(host: Node, heading: String = "") -> Rules:
	var r := Rules.new()
	r._jump = heading
	host.get_tree().root.add_child(r)
	return r


static func sections(db: CardDB) -> Array:
	var p: Dictionary = db.balance.get("player", {})
	var acts := int(db.balance.get("acts", 2))
	var ram := int(p.get("max_energy", 3))
	var hand := int(p.get("hand_size", 5))
	var slots := int(db.balance.get("board_slots", 3))
	var out: Array = []

	# --- In a fight -------------------------------------------------------------
	out.append(["Goal", "In a fight", [
		Palette.w("tagline"),
		["Win a fight", "Bring every enemy to 0 HP. If your HP hits 0, the run ends."],
		["Win the run", "Breach the Core at the top of %s." % ("both layers" if acts == 2 else "all %d layers" % acts)],
		["Your deck", "Your deck is your rig's program library. Each card is a program you run by paying its RAM."],
	]])
	out.append(["Plain words", "In a fight", [
		"The game uses hacker slang. Here is what each word means.",
		["Program", "A card. Running a program means playing a card."],
		["RAM", "Energy. You spend it to play cards and it refills every turn."],
		["Firewall", "Block. It soaks damage before your HP."],
		["Sentry", "An enemy. Black sentries are elites and Cores are bosses."],
		["Exploit, Script, Daemon, Rootkit", "Card types: attack, skill, a temporary rule change on your board, and a power that lasts the fight."],
		["Loop", "A Loop program gets stronger each time you run it this fight: every number marked Loop +N grows by N."],
		["Wiped", "Removed for the rest of this fight (it comes back next fight)."],
		["Malware", "Junk cards enemies put in your deck."],
		["The Stack", "The map of one run. Each node is a stop on it, and each layer (act) ends at a Core."],
		["Wall", "A barrier on the Stack that cuts the routes it crosses."],
		["Jump", "A move diagonally up one floor, through walls. Earned from upgrades and implants."],
		["Vault", "A node sealed off by walls. Only a jump gets you in."],
		["Job", "A run. Every run is done for one crew (faction), which pays you rep."],
		[Palette.w("rest"), "Rest stop: heal or upgrade a card."],
		[Palette.w("shop"), "The shop."],
		["Signal", "A random event with choices."],
		["Implant", "A passive item that triggers on its own."],
		["Subroutine", "A perk that lasts for the rest of the run."],
		["Recompile", "Upgrade a card for the rest of this run."],
		["Firmware", "A permanent upgrade to a card, for every future run."],
		["Rig upgrades", "Permanent bonuses bought with rep."],
		["Creds", "Gold for this run. Spend it at the %s." % Palette.w("shop")],
		[Palette.w("packs"), "Card packs."],
		[Palette.w("dust"), "Crafting currency from scrapped cards."],
		["Heat", "Difficulty level. Higher Heat makes enemies tougher."],
		["Flatlined", "Your HP hit 0 and the run is over."],
	]])
	out.append(["Turn flow", "In a fight", [
		["#", "Start of your turn: Firewall clears (unless kept), RAM refills to %d, each daemon loses 1 HP, then you draw %d programs." % [ram, hand]],
		["#", "Run programs in any order while you have RAM. The cost is the chip in a program's top-left corner."],
		["#", "Press End turn. End-of-turn statuses tick, then your hand is discarded (Cache programs stay, Volatile ones are wiped)."],
		["#", "Enemy turn: each enemy drops its own Firewall and does the move its intent showed. Then it shows its next intent."],
		["Empty draw pile", "Your discard pile is shuffled back in to make a new draw pile."],
		["Running a program", "Tap it. If it needs a target and there are several enemies, tap the enemy next. Tap the program again to cancel."],
		["Reading", "Press and hold any program to read it large, with every keyword explained. Hold an enemy to read its next move."],
		["Piles", "The buttons at the top show your draw pile (in random order), discard pile, wiped programs and whole deck."],
	]])
	var types: Array = []
	for t in CardDef.TYPE_DESC:
		var d: String = CardDef.TYPE_DESC[t]
		types.append([Lexicon.type_name(t), d.substr(d.find(":") + 1).strip_edges() if d.contains(":") else d])
	types.append(["Malware", "Junk the enemy uploads into your deck. Usually Locked or harmful; wipe it when you can."])
	out.append(["Program types", "In a fight", types])
	var kw: Array = []
	for k in CardDef.KEYWORD_DESC:
		kw.append([Lexicon.keyword(k), CardDef.KEYWORD_DESC[k]])
	out.append(["Keywords", "In a fight", kw])
	var programs: Array = []
	for op in CardPrograms.DESCRIPTIONS:
		programs.append([op.capitalize(), CardPrograms.DESCRIPTIONS[op]])
	out.append(["Program combos", "In a fight", programs])
	var good: Array = []
	var bad: Array = []
	for k in Statuses.DEFS:
		var d: String = Statuses.DEFS[k]["desc"]
		var entry := [Lexicon.status(k), d.substr(d.find(":") + 1).strip_edges() if d.begins_with(Lexicon.status(k) + ":") else d]
		(bad if Statuses.DEFS[k]["debuff"] else good).append(entry)
	out.append(["Statuses", "In a fight", ["Helpful:"] + good + ["Harmful:"] + bad])
	out.append(["Enemy intents", "In a fight", [
		"Each enemy shows what it will do on its turn. Hold it to read the move.",
		LEGEND,
		["Exact numbers", "An attack number already includes the enemy's Boost and Throttled and your Exposed, so you can raise exactly enough Firewall."],
	]])
	out.append(["Firewall and daemons", "In a fight", [
		["Firewall", WARD],
		["Daemons", UNITS.trim_prefix("Daemons: ").replace("Up to 3", "Up to %d" % slots)],
		["Bars", "Your HP bar sits under the battlefield. Firewall shows as a shield beside it."],
	]])

	# --- The run ----------------------------------------------------------------
	var ease: Dictionary = db.balance.get("act_start_ease", {})
	out.append(["The Stack", "The run", [
		"The Stack is the run's map. Move up it one node (stop) at a time along the lit routes. Each layer (act) ends with a Core: the boss fight.",
		["HP", "Your HP is your rig's integrity and carries over between fights. Safehouses, some signals and implants repair it."],
		["Rewards", "After a fight you pick one of %d new programs (cards) to add to your deck, or skip. A lean deck draws its best cards more often." % int(db.balance.get("reward", {}).get("choices", 3))],
		["Sentry", "A normal fight."],
		["Black sentry", "An elite: a tougher fight that drops an implant and lets you pick a subroutine."],
		["Core", "The boss at the top of each layer. It drops a boss implant, and every Core but the last lets you pick a subroutine."],
		[Palette.w("rest"), "A rest stop. Reboot to heal, recompile (upgrade) a card, or tinker a mod onto one."],
		[Palette.w("shop"), "The shop. Spend creds on programs, implants and mods, or remove a card from your deck."],
		["Signal", "A random event: pick a choice, some with risks."],
		["Cache", "Loot: holds an implant."],
		["Walls", "Short walls cut some routes, so the Stack is a little maze. Every node can still reach the Core."],
		["Jumps", "Some subroutines, rig upgrades and implants give jumps: charges per layer that move you diagonally up one floor, straight through a wall. You play the node you land on."],
		["Vault", "A node the walls seal off completely. Only a jump gets you in: an elite guard, then a rare implant and extra creds."],
		["Easy start", "The first %d floors of each layer are softer: enemies there have %d%% less HP and deal %d%% less damage." % [int(ease.get("floors", 2)), absi(roundi(float(ease.get("enemy_hp_pct", 0)) * 100)), absi(roundi(float(ease.get("enemy_dmg_pct", 0)) * 100))]],
	]])
	out.append(["Implants", "The run", [
		"Implants are passive items that trigger on their own. Black sentries, Cores, loot caches, vaults, the %s and some signals hand them out. Rarity tells you how an implant works, not how strong it is:" % Palette.w("shop"),
		["Common", "A flat bonus that is always on."],
		["Uncommon", "A bonus with a condition or a counter."],
		["Rare", "Changes a rule of the game."],
		["Boss", "Dropped by Cores: a big upside with a real cost."],
		["Crew implants", "Some implants belong to a crew and never show up on a job against that crew."],
	]])
	var share := int(float(db.balance.get("jobs", {}).get("client_share", 0.5)) * 100)
	var rivals: Array = []
	for f in Jobs.board(db):
		rivals.append([Lexicon.faction(f), "bans " + " and ".join(Jobs.banned(db, f).map(func(x: String) -> String: return Lexicon.faction(x)))])
	var extra := _first_heat(db, "extra_targets")
	var job_lines: Array = [
		["Client", "Every run is a job for one crew (faction). Taking a job on the hub starts a new run. At least %d%% of the programs you load must be theirs." % share],
		["Rivals", "Their rivals' programs are banned: you can't load them and nobody offers them during the job."],
	]
	job_lines.append_array(rivals)
	job_lines.append(["Targets", "A job runs against its targets: their crew's own enforcers guard most fights and black sentries, and usually the Core itself." + ((" From Heat %d, jobs run against extra crews too (still one client), and each extra target pays %d%% more rep." % [extra, int(float(db.balance.get("jobs", {}).get("rep_per_extra_target", 0.25)) * 100)]) if extra > 0 else "")])
	job_lines.append(["Rep", "A job pays the client's rep when it ends, more the further you climb. Rep buys that crew's rig upgrades and flashes its programs to firmware."])
	job_lines.append(["Crews", "Burner (viruses and overclocking), Flux (data flow and firewalls), Wetware (bio-daemons and patches), Null (glitches, buffers and loops), Chrome (drone swarms and plating), Static (jamming and broadcasts), plus Street programs that fit any rig."])
	job_lines.append(["Daily breach", "A daily challenge run with a fixed job, Heat and map for that date. One try per day, scored."])
	var wk: Dictionary = db.balance.get("weekly", {})
	job_lines.append(["Weekly challenge", "A Heat %d job that changes every Monday, the same for everyone, with %d rule changes rolled from a list. You load programs from your own library, but firmware and rig upgrades are off: every program plays at base level. Try as often as you like; the first clear each week pays %s." % [int(wk.get("heat", 2)), int(wk.get("mods", 3)), "%d %s" % [int(wk.get("packs", 1)), PackArt.title(db, str(wk.get("pack_kind", Packs.PREMIUM)))]]])
	var lg: Dictionary = db.balance.get("login", {})
	job_lines.append(["Daily login bonus", "Claim once a day from the hideout. Days 1-6 pay %s %s, day 4 adds %s and day 7 pays %s, then the track starts over. Missing a day never resets it: you pick up on the next day of the track." % [" / ".join(lg.get("scrap", []).map(func(x: Variant) -> String: return str(int(x)))), Palette.w("dust").to_lower(), LoginBonus.reward_text(db, 4).split(", ")[-1].trim_prefix("+"), LoginBonus.reward_text(db, 7).trim_prefix("+")]])
	out.append(["Jobs and rep", "The run", job_lines])
	var mods: Array = [
		["Recompile (+)", "At a safehouse: upgrade one program for this run."],
		["Mods", "Each program holds one mod. Safehouses let you tinker, the Fixer sells mods, and some signals install them."],
	]
	for id in db.mods:
		mods.append([str(db.mods[id]["name"]), (CardMods.describe(db.mods[id]) + " " + CardMods.restriction_text(db.mods[id])).strip_edges()])
	mods.append(["Subroutines", "Perks for this run. After black sentries and every Core except the last, pick one of %d. They last for the rest of the job." % int(db.balance.get("perk_choices", 3))])
	out.append(["Upgrades and perks", "The run", mods])

	# --- Between runs -----------------------------------------------------------
	var dust := Palette.w("dust").to_lower()
	var packs := Palette.w("packs").to_lower()
	var limit := Profile.deck_limit(db)
	out.append(["Collecting", "Between runs", [
		["Library", "Your deck is built from programs you own. Before each run you load extra programs from your library, up to %d copies of each." % limit],
		[Palette.w("packs"), "Earned by play only. Each Core breached pays a crew cache of the crew hiring you (Street when freelance). Finishing the whole job pays a %s. The first weekly challenge clear and day 7 of the login bonus pay one too. Levels, the daily breach, day 4 of the login bonus and shards from black sentries (%d make one) pay a %s." % [PackArt.title(db, Packs.PREMIUM), Profile.shards_per_pack(db), Palette.w("pack").to_lower()]],
		["Hot slot", "The last card of every %s is the hot slot: uncommon or better (rare or better in a %s)." % [Palette.w("pack").to_lower(), PackArt.title(db, Packs.PREMIUM)]],
		["Mercy", "Each kind of %s keeps its own timer (every crew separately): a %s or crew cache guarantees a rare at least every %d and a mythic every %d of that same kind; a %s guarantees a mythic every %d." % [Palette.w("pack").to_lower(),
			Palette.w("pack").to_lower(), int(Packs.config(db).get("pity", {}).get("rare", 0)), int(Packs.config(db).get("pity", {}).get("mythic", 0)),
			PackArt.title(db, Packs.PREMIUM), int(Packs.config(db, Packs.PREMIUM).get("pity", {}).get("mythic", 0))]],
		[Palette.w("pack"), "Any crew. " + _pack_odds(db, Packs.NORMAL)],
		["Crew caches", "One per crew, Street included: only that crew's programs (and its joint ops). " + _pack_odds(db, Packs.crew_kind("ember"))],
		[PackArt.title(db, Packs.PREMIUM), "Premium. Any crew. " + _pack_odds(db, Packs.PREMIUM)],
		["Rarity", "Rarer programs add complexity, not raw power."],
		[Palette.w("dust"), "Scrap copies you no longer need to earn %s, then spend it to compile the programs you want." % dust],
		["Quick scrap", "While opening a %s, a pulled program you already own more than %d of can be scrapped on the spot." % [Palette.w("pack").to_lower(), limit]],
		["Mastery", "Running a program often raises its mastery."],
		["Binders", "Own every program on a crew's rarity page to claim it. A full set pays a card back and a title."],
	]])
	out.append(["Firmware", "Between runs", [
		"Copies are upgrades: a deck holds up to %d copies of a program, and extra copies beyond those upgrade it." % limit,
		["v1", "Uses up %s extra copies (by rarity: common, uncommon, rare, mythic) and gives +%d%% to its numbers in every run." % [_ladder(db, 0), roundi((float(db.balance["firmware"]["scale"][0]) - 1.0) * 100)]],
		["v2", "Uses up %s more (+%d%%, twice the price)." % [_ladder(db, 1), roundi((float(db.balance["firmware"]["scale"][1]) - 1.0) * 100)]],
		["Baked mod", "After %d plays you can bake a mod into a program's firmware." % int(db.balance["mastery"][int(db.balance["firmware"].get("mod_mastery_tier", 2)) - 1]["plays"])],
		["Price", "Crew programs cost that crew's rep. Street and base programs cost %s (base programs need no copies)." % dust],
		["Maxed", "Once a program's firmware is maxed and you own %d copies, %s reroll it once." % [limit, packs]],
		["Rig upgrades", "Bought at the hideout with a crew's rep. They apply to every run."],
	]])
	var heat: Array = ["Heat is the difficulty level, picked on the hub before you take a job. Breach the final Core to unlock the next Heat. Each level adds to the ones below it, and the enemy HP and damage boosts compound."]
	var levels: Array = db.balance.get("heat", [])
	for i in levels.size():
		heat.append(["Heat %d" % (i + 1), str(levels[i].get("desc", ""))])
	out.append(["Heat", "Between runs", heat])
	return out


## Section headings in order (for the contents strip and tests).
static func headings(db: CardDB) -> Array:
	return sections(db).map(func(s: Array) -> String: return s[0])


static func _first_heat(db: CardDB, mod: String) -> int:
	var levels: Array = db.balance.get("heat", [])
	for i in levels.size():
		if levels[i].get("mods", {}).has(mod):
			return i + 1
	return 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 80
	var bg := ColorRect.new()
	bg.color = Color(Palette.PANEL_BG, 0.97)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var parts := UiKit.screen(10, BoxContainer.ALIGNMENT_BEGIN)
	add_child(parts[0])
	var v: VBoxContainer = parts[1]
	v.add_child(UiKit.label("Rules reference", 30, Palette.ENERGY))
	var secs := sections(CardDB.shared())
	v.add_child(_contents(secs))
	var inner := UiKit.scroll(v)
	_scroll = inner.get_parent() as ScrollContainer
	var n := 0
	var group := ""
	for sec in secs:
		if sec[1] != group:
			group = sec[1]
			var g := UiKit.label(group.to_upper(), 14, Palette.TEXT_DIM)
			g.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			inner.add_child(g)
		n += 1
		var box := _section(n, sec[0], sec[2])
		_anchors[sec[0]] = box
		inner.add_child(box)
	v.add_child(UiKit.button("Close", queue_free, Vector2(200, 56)))
	if _jump != "":
		jump_to.call_deferred(_jump)


## Scrolls so `heading` sits at the top. Unknown headings do nothing.
func jump_to(heading: String) -> void:
	var c: Control = _anchors.get(heading)
	if c == null or _scroll == null:
		return
	await get_tree().process_frame
	_scroll.scroll_vertical = int(c.position.y)


## Chips grouped by part; tapping one scrolls to its section.
func _contents(secs: Array) -> Control:
	var flow := UiKit.flow(6)
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	var n := 0
	for sec in secs:
		n += 1
		var heading: String = sec[0]
		var b := UiKit.button("%d %s" % [n, heading], func() -> void: jump_to(heading), Vector2(0, 38), 13)
		b.add_theme_color_override("font_color", Palette.ENERGY if sec[1] == GROUPS[0] else (Palette.UPGRADED if sec[1] == GROUPS[1] else Palette.TEXT))
		flow.add_child(b)
	return flow


func _section(n: int, heading: String, entries: Array) -> Control:
	var box := UiKit.vbox(6, BoxContainer.ALIGNMENT_BEGIN)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := UiKit.label("%d. %s" % [n, heading], 21, Palette.ENERGY)
	h.add_theme_font_override("font", Palette.display())
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(h)
	var step := 0
	for e in entries:
		if e is String and e == LEGEND:
			box.add_child(_legend())
		elif e is Array and e[0] == "#":
			step += 1
			box.add_child(_rich("[color=%s][b]%d[/b][/color]  %s" % [Palette.ENERGY.to_html(false), step, _esc(e[1])]))
		elif e is Array:
			box.add_child(_rich("[color=%s][b]%s[/b][/color]   %s" % [Palette.UPGRADED.to_html(false), _esc(e[0]), _esc(e[1])]))
		elif str(e).ends_with(":") and str(e).length() < 20:
			var sub := UiKit.label(str(e), 16, Palette.TEXT_DIM)
			sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			box.add_child(sub)
		else:
			box.add_child(_rich(_esc(str(e))))
	return UiKit.panel(box, Color(Palette.PANEL_BG, 0.6))


func _rich(bb: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.add_theme_font_size_override("normal_font_size", 16)
	r.add_theme_font_size_override("bold_font_size", 16)
	r.add_theme_color_override("default_color", Palette.TEXT)
	r.text = bb
	return r


static func _esc(s: String) -> String:
	return s.replace("[", "[lb]")


func _legend() -> Control:
	var box := VBoxContainer.new()
	for k in Intents.DESC:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(34, 34)
		icon.draw.connect(func() -> void: IntentIcon.draw(icon, icon.size / 2, 13, k))
		row.add_child(icon)
		var l := UiKit.label(str(Intents.DESC[k]), 15, Palette.TEXT, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.custom_minimum_size.x = 0
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		box.add_child(row)
	return box


## "3/3/2/2": copies for firmware level `lvl` by rarity (common, uncommon, rare, mythic).
static func _ladder(db: CardDB, lvl: int) -> String:
	var parts: Array[String] = []
	for r in ["common", "uncommon", "rare", "mythic"]:
		var l: Array = db.balance["firmware"].get("copies", {}).get(r, [])
		parts.append(str(l[lvl]) if lvl < l.size() else "-")
	return "/".join(parts)


## "3 cards: common 76%, ... · hot slot: ... · 5% glitch foil per card" from a pack kind's config.
static func _pack_odds(db: CardDB, kind: String) -> String:
	var cfg := Packs.config(db, kind)
	var pct := func(w: Dictionary) -> String:
		var total := 0.0
		for r in w:
			total += float(w[r])
		var bits: Array[String] = []
		for r in ["common", "uncommon", "rare", "mythic"]:
			if w.has(r) and float(w[r]) > 0.0:
				bits.append("%s %s%%" % [r, String.num(100.0 * float(w[r]) / total, 1).trim_suffix(".0")])
		return ", ".join(bits)
	return "%d cards (%s), then the hot slot (%s). %d%% glitch foil per card." % [int(cfg.get("size", 4)) - 1, pct.call(cfg.get("weights", {})),
		pct.call(cfg.get("hot_slot", {})), roundi(float(cfg.get("foil_chance", 0)) * 100)]
