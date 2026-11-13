class_name GameAudio
extends Node
## Presentation-only synthesized PCM. Never consumes gameplay RNG.
const RATE := 22050
const VOICES := 8
# Duration, starting pitch, ending pitch, noise blend, modulation, gain.
const CUES := {
	"tap": [0.045, 1250, 700, 0.12, 0, 0.2],
	"hit": [0.18, 150, 42, 0.55, 0, 0.55],
	"block": [0.15, 900, 300, 0.2, 110, 0.35],
	"break": [0.28, 1500, 120, 0.65, 80, 0.4],
	"ward": [0.24, 260, 800, 0.08, 60, 0.32],
	"heal": [0.32, 440, 880, 0.02, 5, 0.3],
	"glitch": [0.17, 700, 170, 0.4, 70, 0.28],
	"summon": [0.35, 110, 660, 0.1, 22, 0.35],
	"death": [0.4, 380, 35, 0.35, 35, 0.45],
	"explode": [0.38, 90, 28, 0.8, 0, 0.5],
	"turn": [0.14, 260, 390, 0.02, 0, 0.23],
	"pack": [0.65, 180, 1500, 0.4, 30, 0.35],
	"common": [0.15, 600, 900, 0.06, 0, 0.28],
	"uncommon": [0.24, 600, 1200, 0.04, 5, 0.3],
	"rare": [0.45, 440, 1320, 0.02, 8, 0.34],
	"mythic": [0.65, 330, 1320, 0.02, 4, 0.38],
	"victory": [0.65, 330, 990, 0.02, 4, 0.35],
	"defeat": [0.6, 220, 55, 0.08, 8, 0.35],
	"street": [0.12, 350, 150, 0.25, 0, 0.3],
	"ember": [0.22, 190, 55, 0.65, 12, 0.35],
	"tide": [0.24, 220, 850, 0.03, 35, 0.3],
	"bloom": [0.25, 180, 460, 0.06, 9, 0.32],
	"void": [0.23, 600, 60, 0.08, 48, 0.3],
	"chrome": [0.18, 1100, 220, 0.12, 170, 0.3],
	"noise": [0.2, 850, 230, 0.5, 90, 0.3],
}
static var instance: GameAudio
var muted := false
var volume := 0.6
var _cache: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _last: Dictionary = {}
var _variation := 0

func _ready() -> void:
	instance = self
	for cue in CUES:
		_cache[cue] = synthesize(cue)
	for i in VOICES:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

func _exit_tree() -> void:
	if instance == self:
		instance = null

func configure(settings: Dictionary) -> void:
	muted = bool(settings.get("sfx_muted", false))
	volume = clampf(float(settings.get("sfx_volume", 0.6)), 0.0, 1.0)
	for player in _players:
		player.volume_db = linear_to_db(maxf(volume, 0.0001))
		if muted or volume == 0.0:
			player.stop()

static func play(cue: String) -> void:
	if is_instance_valid(instance):
		instance._play(cue)

func _play(cue: String) -> void:
	if muted or volume <= 0.0 or not _cache.has(cue) or DisplayServer.get_name() == "headless":
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(cue, -1000)) < 55:
		return
	_last[cue] = now
	for player in _players:
		if not player.playing:
			player.stream = _cache[cue]
			player.volume_db = linear_to_db(volume)
			player.pitch_scale = 1.0 + float(_variation % 5 - 2) * 0.012
			_variation += 1
			player.play()
			return

static func event_cue(e: Dictionary) -> String:
	match e.get("t", ""):
		"damage":
			if int(e.get("blocked", 0)) > 0:
				return "break" if int(e.get("ward", 0)) == 0 else "block"
			return "hit" if int(e.get("amount", 0)) > 0 else ""
		"ward", "heal", "summon", "death": return str(e["t"])
		"status", "strip": return "glitch"
		"expire": return "death"
		"daemon_explosion": return "explode"
		"enemy_phase", "turn_start": return "turn"
		"combat_end": return "victory" if e.get("won", false) else "defeat"
	return ""

static func synthesize(cue: String) -> AudioStreamWAV:
	var p: Array = CUES[cue]
	var count := int(float(p[0]) * RATE)
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var phase := 0.0
	var noise_state := 314159
	for i in count:
		var t := float(i) / RATE
		var u := float(i) / maxf(1.0, count - 1.0)
		var frequency := lerpf(float(p[1]), float(p[2]), u)
		phase += TAU * frequency / RATE
		noise_state = (noise_state * 1664525 + 1013904223) & 0x7fffffff
		var noise := float(noise_state) / 1073741824.0 - 1.0
		var tone := sin(phase + 0.7 * sin(TAU * float(p[4]) * t))
		tone = tone * 0.75 + sin(phase * 2.01) * 0.25
		var envelope := minf(t / 0.006, 1.0) * pow(1.0 - u, 2.0)
		var value := lerpf(tone, noise, float(p[3])) * envelope * float(p[5]) * 0.3
		bytes.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream
