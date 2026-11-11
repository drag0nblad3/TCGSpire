class_name Rules
extends Control
## "How to play" overlay: rules, intent legend, statuses and keywords. Status and
## keyword text comes straight from Statuses.DEFS / CardDef.KEYWORD_DESC, so
## new content documents itself. Open with Rules.open(node).

const WARD := "Firewall: absorbs damage before HP. Your Firewall is cleared at the start of your turn (unless you are Hardened)."
const UNITS := "Daemons: programs that stay on your board. Each hits the front enemy at the end of your turn. Area attacks and attacks aimed at the front can crash them."

var _tap := Tap.new()


static func open(host: Node) -> void:
	host.get_tree().root.add_child(Rules.new())


## [heading, [lines]] pairs. Data only so it is easy to test and extend.
static func sections(db: CardDB) -> Array:
	var p: Dictionary = db.balance.get("player", {})
	var acts := int(db.balance.get("acts", 2))
	var out: Array = []
	out.append(["The job", [
		Palette.w("tagline"),
		"Your deck is your rig's program library. Each card is a program: Exploits attack, Scripts defend and set up, Daemons stay on your board, Rootkits change the rules for the rest of the fight.",
	]])
	out.append(["The run", [
		"Hack node by node up the network map. Each layer ends with a Core guarded by a boss; breach %s to own the Stack." % ("both layers" if acts == 2 else "all %d layers" % acts),
		"Your HP is your rig's integrity and carries over between fights. Safehouses, some signals and implants repair it.",
		"After a fight you rip one program from the sentries into your deck (or skip). A lean deck runs its best programs more often.",
	]])
	out.append(["Your turn", [
		"You have %d RAM each turn and draw %d programs. A program's RAM cost is in its top-left chip." % [int(p.get("max_energy", 3)), int(p.get("hand_size", 5))],
		"Tap a program to run it. If it needs a target and there are several enemies, tap the enemy next. Tap the program again to cancel.",
		"Press and hold any program to read it large, with every keyword explained. Hold an enemy to read its next move.",
		"End turn: your daemons hit, then programs left in your hand are discarded. When your draw pile runs dry, the discard pile is shuffled back in.",
		"The buttons at the top show your draw pile (in random order), discard pile, wiped programs and whole deck.",
	]])
	out.append(["Reading the sentries", ["Each enemy shows what it will do on its turn. The icons:"]])
	out.append(["Defence", [WARD, UNITS]])
	var st: Array = []
	for k in Statuses.DEFS:
		st.append("%s%s: %s" % [Lexicon.status(k), " (harmful)" if Statuses.DEFS[k]["debuff"] else "", Statuses.DEFS[k]["desc"]])
	out.append(["Statuses", st])
	var kw: Array = []
	for t in CardDef.TYPE_DESC:
		kw.append(CardDef.TYPE_DESC[t])
	for k in CardDef.KEYWORD_DESC:
		kw.append("%s: %s" % [Lexicon.keyword(k), CardDef.KEYWORD_DESC[k]])
	out.append(["Programs and keywords", kw])
	out.append(["Between fights", [
		"Black sentries (X) are tougher fights that drop implants. Implants are passive cyberware that trigger on their own.",
		"Safehouse (H): reboot to repair HP, or recompile (upgrade) a program. Fixer ($): buy programs and implants, or delete a program. Signals (?) are choices with risks. Caches (C) hold an implant.",
	]])
	var share := int(float(db.balance.get("jobs", {}).get("client_share", 0.5)) * 100)
	var rivals: Array[String] = []
	for f in Jobs.board(db):
		rivals.append("%s bans %s" % [Lexicon.faction(f), " and ".join(Jobs.banned(db, f).map(func(x: String) -> String: return Lexicon.faction(x)))])
	out.append(["Jobs and rep", [
		"Every run is a job for one crew. At least %d%% of the programs you load must be theirs, and their rivals' programs are banned: you can't load them and nobody offers them during the job (%s)." % [share, "; ".join(rivals)],
		"A job also runs against its targets: their crew's own enforcers guard most fights and black sentries on the map, and usually the Core itself. From Heat %d, jobs run against extra crews too (still one client), and each extra target pays %d%% more rep." % [_first_heat(db, "extra_targets"), int(float(db.balance.get("jobs", {}).get("rep_per_extra_target", 0.25)) * 100)],
		"A job pays the client's rep when it ends, more the further you climb. Rep buys that crew's rig upgrades and flashes its programs to firmware.",
	]])
	var mods: Array[String] = []
	for id in db.mods:
		mods.append("%s: %s" % [db.mods[id]["name"], CardMods.describe(db.mods[id])])
	out.append(["Upgrades and perks", [
		"This run only: recompile a program at a safehouse (+), or install a mod. Each program holds one mod. Safehouses let you tinker, the Fixer sells mods, and some signals install them.",
		"Mods: " + " ".join(mods),
		"Subroutines: after black sentries and the first Core, load one of %d subroutines. They run for the rest of the job." % int(db.balance.get("perk_choices", 3)),
		"Permanent: rig upgrades (hideout) apply to every run. Firmware: once you've run a program enough, flash it and every copy joins your runs upgraded. Run it even more and you can bake a mod into its firmware too. Crew programs cost that crew's rep; Street and base programs cost %s." % Palette.w("dust").to_lower(),
	]])
	out.append(["Your library", [
		"Your deck is built from programs you own. Before each run you load extra programs from your library.",
		"Runs earn XP and %s. Crack them open for new programs (rarer programs add complexity, not raw power)." % Palette.w("packs").to_lower(),
		"Scrap spare copies for %s and compile the programs you want. Running a program often raises its mastery." % Palette.w("dust").to_lower(),
		"Crews: Burner (viruses and overclocking), Flux (data flow and firewalls), Wetware (bio-daemons and patches), Null (glitches, buffers and loops), Chrome (drone swarms and plating), Static (jamming and broadcasts), plus Street programs that fit any rig.",
		"Heat: breach the final Core to unlock harder runs with extra modifiers.",
	]])
	out.append(["Tips", [
		"An enemy's attack number already includes its Boost, its Throttle and your Exposed, so you can raise exactly enough Firewall.",
		"Your HP bar sits under the battlefield. Firewall shows as a shield beside it.",
	]])
	return out


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
	v.add_child(UiKit.label("How to play", 30, Palette.ENERGY))
	var inner := UiKit.scroll(v)
	for sec in sections(CardDB.shared()):
		var h := UiKit.label(sec[0], 21, Palette.ENERGY)
		h.add_theme_font_override("font", Palette.display())
		inner.add_child(h)
		for line in sec[1]:
			var l := UiKit.label(str(line), 16, Palette.TEXT, true)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size.x = 0
			inner.add_child(l)
		if sec[0] == "Reading the sentries":
			inner.add_child(_legend())
	v.add_child(UiKit.button("Close", queue_free, Vector2(200, 56)))


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
