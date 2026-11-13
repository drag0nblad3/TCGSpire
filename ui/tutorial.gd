class_name Tutorial
extends PanelContainer
## Guided practice fight, started from the hub. main.start_tutorial() shows the
## briefing pages, then a fixed-seed fight with this coach docked over the
## board, then the debrief. Nothing is saved except settings.tutorial_done.
##
## Each step is a short tip plus a condition read from live Combat state
## (step_done), so the coach follows whatever the player actually does.

signal skipped

const DECK := ["jab", "jab", "jab", "kindle", "brace", "brace", "brace", "drone_swarm"]
const ENCOUNTER := "mites"
const SEED := 7

## "next" = the player taps Got it; the rest advance on their own.
const STEPS := [
	{"until": "next", "text": "These are sentries. The icon over each one is its intent: what it does on its turn. Hold a sentry to read its move."},
	{"until": "attack", "text": "Your RAM is the chip beside End turn. Tap an Exploit such as %s, then tap a sentry to hit it."},
	{"until": "ward", "text": "Check the incoming damage beside End turn. Run a Script such as %s to raise Firewall. It soaks damage before your HP."},
	{"until": "turn2", "text": "Out of RAM, or happy with your plays? Press End turn. The sentries act, then you draw a fresh hand."},
	{"until": "daemon", "text": "Your Firewall cleared and your RAM refilled. Daemons stay on your board and change the rules for a few turns. Run %s if you drew it, or tap Got it."},
	{"until": "next", "text": "Hold any program to read it in full, and the ? button opens the rules reference. Now finish the fight."},
]

var screen: CombatScreen
var step := 0
var _since := 0  # combat.events index when the current step began
var _text: Label
var _next: Button


static func make_combat(db: CardDB) -> Combat:
	var c := Combat.create(db, db.make_deck(DECK), ENCOUNTER, GameRng.new(SEED))
	c.start()
	return c


static func step_text(db: CardDB, i: int) -> String:
	var t: String = STEPS[i]["text"]
	if not t.contains("%s"):
		return t
	var id: String = {1: "jab", 2: "brace", 4: "drone_swarm"}.get(i, "jab")
	return t % db.card(id).name


## True once step i's goal shows up in the fight (events since `since`, or state).
static func step_done(i: int, c: Combat, since: int) -> bool:
	match str(STEPS[i]["until"]):
		"attack":
			return _played_type(c, since, "attack")
		"ward":
			return c.player.ward > 0 or c.energy <= 0 or c.turn >= 2
		"turn2":
			return c.turn >= 2
		"daemon":
			return _played_type(c, since, "unit")
	return false


static func _played_type(c: Combat, since: int, type: String) -> bool:
	for k in range(since, c.events.size()):
		var e: Dictionary = c.events[k]
		if e["t"] == "play":
			var def: CardDef = c.db.card(str(e["card"]).get_slice("#", 0).trim_suffix("+"))
			if def != null and def.type == type:
				return true
	return false


## [title, [lines]] pages shown before the practice fight.
static func briefing(db: CardDB) -> Array:
	var p: Dictionary = db.balance.get("player", {})
	var acts := int(db.balance.get("acts", 3))
	return [
		["You're a %s" % Palette.w("hero"), [
			Palette.w("tagline"),
			"A run climbs the Stack: a map of fights and stops, %d layers tall. Each layer ends at a Core guarded by a boss." % acts,
		]],
		["Programs and RAM", [
			"Your deck is your program library. Each turn you get %d RAM and draw %d programs." % [int(p.get("max_energy", 3)), int(p.get("hand_size", 5))],
			"Exploits attack. Scripts defend and set up. Daemons stay on your board and bend the rules. Rootkits last the whole fight.",
		]],
		["Practice fight", [
			"Next: two Spark Mites and a small fixed deck. Nothing is lost and nothing is earned.",
			"Follow the tips at the top of the board. You can skip at any time.",
		]],
	]


## Pages after the fight: what a real job adds.
static func debrief(db: CardDB, won: bool) -> Array:
	return [
		["Practice complete" if won else "Flatlined, but that's what practice is for", [
			"After a real fight you pick one program to add to your deck. Safehouses repair HP and upgrade programs, the %s sells gear, and signals are gambles." % Palette.w("shop"),
			"Every run is a job for one crew. At least half your programs come from that crew, and their rivals' programs are banned.",
			"Jobs pay rep and %s. Open them for new programs, and extra copies upgrade a program's firmware for every run." % Palette.w("packs").to_lower(),
			"The Rules button on the hub explains everything in detail.",
		]],
	]


func setup(s: CombatScreen) -> Tutorial:
	screen = s
	return self


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	offset_left = 18
	offset_right = -18
	offset_top = 128
	z_index = 20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(Palette.PANEL_BG, 0.94)
	sb.border_color = Palette.ENERGY
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(maxi(Palette.RADIUS, 8))
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	var v := UiKit.vbox(8)
	add_child(v)
	_text = UiKit.label("", 17, Palette.TEXT, true)
	_text.custom_minimum_size.x = 0
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_text)
	var row := UiKit.hbox(12)
	_next = UiKit.button("Got it", _advance, Vector2(150, 44), 16)
	row.add_child(_next)
	row.add_child(UiKit.button("Skip tutorial", func() -> void: skipped.emit(), Vector2(170, 44), 15))
	v.add_child(row)
	screen.acted.connect(_check)
	_show_step()


func _show_step() -> void:
	if step >= STEPS.size():
		visible = false
		return
	visible = true
	_text.text = "%d/%d   %s" % [step + 1, STEPS.size(), step_text(screen.combat.db, step)]
	# Auto steps can still be passed by hand, except the ones the fight needs.
	_next.visible = str(STEPS[step]["until"]) in ["next", "daemon", "ward"]


func _advance() -> void:
	step += 1
	_since = screen.combat.events.size()
	_show_step()


func _check() -> void:
	if step >= STEPS.size() or screen.combat.is_over():
		visible = false
		return
	# One action can finish several steps at once (e.g. a Script that also ends your RAM).
	while step < STEPS.size() and str(STEPS[step]["until"]) != "next" and step_done(step, screen.combat, _since):
		step += 1
	_since = screen.combat.events.size()
	_show_step()
