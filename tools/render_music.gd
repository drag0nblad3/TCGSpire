extends SceneTree
## Rebuild source WAVs: godot --headless --path . -s tools/render_music.gd
## Then encode to Ogg Vorbis, e.g. ffmpeg -i menu.wav -c:a libvorbis -q:a 3 menu.ogg
func _initialize() -> void:
	for mode in MusicScore.MODES:
		var stream := MusicScore.render(mode)
		stream.save_to_wav("/tmp/tcgspire-" + mode + ".wav")
		print("Rendered " + mode)
	quit()
