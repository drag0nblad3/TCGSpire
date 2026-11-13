# TCGSpire original music

Four original eight-bar procedural electronic compositions: menu (88 BPM), map
(100 BPM), combat (116 BPM), and boss (128 BPM). D-minor harmony, synthesized pads,
FM plucks, bass, and percussion. No external recordings or samples.

Source: `ui/music_score.gd`. Run `tools/render_music.gd` with Godot to render WAVs
to `/tmp/tcgspire-{mode}.wav`, then encode with FFmpeg Vorbis quality 3. Godot
loops the Ogg streams; the score wraps note tails across its loop boundary.

The shipped Ogg files avoid synthesis work on phones. Music and effects have
independent saved volume/mute settings. Music crossfades over 1.2 seconds and
pauses when the application loses focus.
