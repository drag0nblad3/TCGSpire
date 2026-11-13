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

## Expanded soundtrack

Each mood has three tracks, selected in rotation on re-entry and after two loops
in a longer session. The playlist clock pauses in the background and while muted.
Same-mood navigation preserves the current track. Selection is independent of game RNG.

| Mood | Additional compositions | BPM |
| --- | --- | --- |
| Menu | After Hours / Glass Skyline | 78 / 92 |
| Exploration | Rain on the Relay / Carrier Drift | 96 / 108 |
| Combat | Voltage Runner / Ghost Protocol | 126 / 112 |
| Boss | Lockdown / Blackout Engine | 138 / 104 |

The eight new tracks are 16-bar compositions with changing middle/final sections,
new progressions and motifs, bell/keyboard/acid timbres, and distinct drum patterns.
Rebuild them with `python tools/compose_variety.py` (NumPy and FFmpeg required).
The original four tracks and their GDScript rendering tool remain unchanged.
