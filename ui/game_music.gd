class_name GameMusic
extends Node
## Two voices crossfade between original compressed loops. Same-mood navigation
## keeps the current playhead; backgrounding pauses both voices.
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
		if _cache.has(desired):
			_active = 1 - _active
			var player := _voices[_active]
			player.stop()
			player.stream = _cache[desired]
			_gains[_active] = 0.0
			player.volume_db = -80.0
			player.play()
			current = desired
		else:
			var stream := load("res://assets/music/%s.ogg" % desired) as AudioStreamOggVorbis
			if stream != null:
				stream.loop = true
				_cache[desired] = stream

	for i in 2:
		_gains[i] = move_toward(_gains[i], 1.0 if i == _active else 0.0, delta / 1.2)
		_voices[i].volume_db = linear_to_db(maxf(0.0001, _gains[i] * volume * 0.55))
		if i != _active and _gains[i] == 0.0:
			_voices[i].stop()
