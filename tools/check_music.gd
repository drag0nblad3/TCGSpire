extends SceneTree
## Real scene-tree audio lifecycle check (Dummy audio driver supported).
func _initialize() -> void:
	call_deferred("_check")

func _check() -> void:
	var music := GameMusic.new()
	root.add_child(music)
	music._advance(0.1)
	music._advance(1.2)
	assert(music.current == "menu")
	assert(music._voices[music._active].playing)
	var first := music._active
	music._advance(0.1)
	assert(music._active == first, "Same mood must not restart")
	GameMusic.mood("boss")
	music._advance(0.1)
	music._advance(0.1)
	assert(music.current == "boss")
	assert(music._active != first)
	music._advance(1.2)
	assert(not music._voices[first].playing)
	music._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert(music._voices[music._active].stream_paused)
	music._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(not music._voices[music._active].stream_paused)
	var previous_track := music._track
	music._advance(music._rotation_after + 0.1)
	assert(music._track != previous_track, "Long sessions rotate tracks")
	var second_track := music._track
	music._advance(music._rotation_after + 0.1)
	assert(music._track != second_track and music._track != previous_track)
	music._advance(music._rotation_after + 0.1)
	assert(music._track == previous_track, "Playlist wraps after all three tracks")
	music._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var elapsed := music._elapsed
	music._advance(999.0)
	assert(music._elapsed == elapsed, "Background time does not advance playlist")
	music._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	music.configure({"music_muted": true})
	for player in music._voices:
		assert(not player.playing)
	music.configure({"music_muted": false})
	music._advance(0.1)
	assert(music.current == "boss")
	music.configure({"music_muted": true})
	await create_timer(0.2).timeout
	music.free()
	await create_timer(0.2).timeout
	print("OK: music playback, crossfade, mute, and background lifecycle and playlist rotation")
	quit()
