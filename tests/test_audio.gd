extends TestCase

func test_sounds_are_finite_audible_and_fade_to_zero() -> void:
	for cue in GameAudio.CUES:
		var stream := GameAudio.synthesize(cue)
		check(stream.data.size() > 100, cue + " empty")
		eq(stream.data.decode_s16(0), 0, cue + " attack")
		eq(stream.data.decode_s16(stream.data.size() - 2), 0, cue + " tail")
		var peak := 0
		for i in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(i)))
		check(peak > 100 and peak < 6000, cue + " audible with mixing headroom")

func test_combat_audio_uses_actual_outcome() -> void:
	eq(GameAudio.event_cue({"t": "damage", "blocked": 4, "ward": 2}), "block")
	eq(GameAudio.event_cue({"t": "damage", "blocked": 4, "ward": 0}), "break")
	eq(GameAudio.event_cue({"t": "damage", "amount": 0}), "")
	eq(GameAudio.event_cue({"t": "combat_end", "won": false}), "defeat")
	eq(GameAudio.event_cue({"t": "combat_end", "won": true}), "victory")

func test_volume_settings_clamped_and_saved() -> void:
	var audio := GameAudio.new()
	audio.configure({"sfx_volume": 4, "sfx_muted": true})
	eq(audio.volume, 1.0)
	eq(audio.muted, true)
	var profile := Profile.new()
	profile.settings = {"sfx_volume": 0.4, "sfx_muted": true}
	var restored := Profile.from_dict(profile.to_dict())
	eq(restored.settings, profile.settings)
	audio.free()

func test_music_loops_have_headroom_and_continuous_boundaries() -> void:
	for mode in MusicScore.MODES:
		var stream := MusicScore.render(mode)
		eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD)
		eq(stream.loop_end * 2, stream.data.size())
		check(stream.get_length() >= 15.0, mode + " eight-bar score")
		var peak := 0
		for i in range(0, stream.data.size(), 2):
			peak = maxi(peak, absi(stream.data.decode_s16(i)))
		check(peak > 1000 and peak < 24000, mode + " audible without clipping")
		var seam := absi(stream.data.decode_s16(0) - stream.data.decode_s16(stream.data.size() - 2))
		check(seam < 1200, mode + " loop seam clicks")

func test_music_controls_are_independent() -> void:
	var music := GameMusic.new()
	music.configure({"sfx_muted": true, "music_volume": 0.2})
	eq(music.muted, false)
	eq(music.volume, 0.2)
	music.configure({"music_muted": true, "music_volume": -1})
	eq(music.muted, true)
	eq(music.volume, 0.0)
	music.free()

func test_additional_combat_cues() -> void:
	eq(GameAudio.event_cue({"t": "draw"}), "draw")
	eq(GameAudio.event_cue({"t": "status", "status": "burn"}), "virus")
	eq(GameAudio.event_cue({"t": "reshuffle"}), "shuffle")
	eq(GameAudio.event_cue({"t": "talisman"}), "implant")

func test_music_playlists_are_complete_and_distinct() -> void:
	var seen: Dictionary = {}
	for mood in GameMusic.PLAYLISTS:
		var tracks: Array = GameMusic.PLAYLISTS[mood]
		eq(tracks.size(), 3, mood + " variety")
		for track in tracks:
			check(not seen.has(track), "no duplicated compositions")
			seen[track] = true
			var stream := load("res://assets/music/%s.ogg" % track) as AudioStreamOggVorbis
			check(stream != null, track + " exports as audio")
			if stream != null:
				check(stream.get_length() >= 15.0, track + " complete phrase")
