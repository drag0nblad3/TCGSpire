class_name GameMusic
extends Node
## Two voices crossfade between original compressed loops. Same-mood navigation
## keeps the current playhead; backgrounding pauses both voices.
const PLAYLISTS := {
	"menu": ["menu", "menu_afterhours", "menu_glass"],
	"map": ["map", "map_rain", "map_drift"],
	"combat": ["combat", "combat_voltage", "combat_ghost"],
	"boss": ["boss", "boss_lockdown", "boss_blackout"],
}
static var instance: GameMusic
var volume := 0.4
var muted := false
var desired := "menu"
var current := ""
var _cache: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _gains := [0.0, 0.0]
var _active := 0
var _background := false
var _positions: Dictionary = {}
var _track := ""
var _elapsed := 0.0
var _rotation_after := 0.0

func _ready() -> void:
	instance = self
	for i in 2:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_voices.append(player)

func _exit_tree() -> void:
	if instance == self:
		instance = null

static func mood(value: String) -> void:
	if is_instance_valid(instance) and value in MusicScore.MODES:
		instance.desired = value

func configure(settings: Dictionary) -> void:
	volume = clampf(float(settings.get("music_volume", 0.4)), 0.0, 1.0)
	muted = bool(settings.get("music_muted", false))
	if muted or volume == 0.0:
		for player in _voices:
			player.stop()
		_gains = [0.0, 0.0]
		current = ""

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_background = true
	elif what in [NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		_background = false
	if what not in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN]:
		return
	for player in _voices:
		if is_instance_valid(player):
			player.stream_paused = _background

func _process(delta: float) -> void:
	if DisplayServer.get_name() != "headless":
		_advance(delta)

func _advance(delta: float) -> void:
	if muted or volume == 0.0 or _background:
		return
	if desired != current:
		_start_next(desired)
	elif _rotation_after > 0.0:
		_elapsed += delta
		if _elapsed >= _rotation_after:
			_start_next(desired)

	for i in 2:
		_gains[i] = move_toward(_gains[i], 1.0 if i == _active else 0.0, delta / 1.2)
		_voices[i].volume_db = linear_to_db(maxf(0.0001, _gains[i] * volume * 0.55))
		if i != _active and _gains[i] == 0.0:
			_voices[i].stop()

func _start_next(mode: String) -> void:
	var playlist: Array = PLAYLISTS[mode]
	var position := (int(_positions.get(mode, -1)) + 1) % playlist.size()
	var track: String = playlist[position]
	if not _cache.has(track):
		var stream := load("res://assets/music/%s.ogg" % track) as AudioStreamOggVorbis
		if stream == null:
			return
		stream.loop = true
		_cache[track] = stream
	_positions[mode] = position
	_active = 1 - _active
	var player := _voices[_active]
	player.stop()
	player.stream = _cache[track]
	_gains[_active] = 0.0
	player.volume_db = -80.0
	player.play()
	current = mode
	_track = track
	_elapsed = 0.0
	# Two complete phrases before rotating. The incoming downbeat starts at
	# the loop boundary, with a short overlap to avoid abrupt ambience changes.
	_rotation_after = player.stream.get_length() * 2.0
