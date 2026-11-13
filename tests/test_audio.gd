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
