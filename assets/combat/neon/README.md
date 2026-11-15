# Neon enemy art

67 unique virtual-creature bases, plus two transparent elite overlay layers per
faction. The seven atlases use lossless WebP with alpha and 440 × 340 cells.
Faction sheets have three columns; the neutral sheet has five.

`EnemyPortraits.ROSTER` maps each non-boss enemy to a base cell. The last two
occupied cells in each atlas are the rear shoulder fins and front guards/rank
glyph. The renderer composes these only for elites. Animated faction signals
remain separate code layers; no gameplay data or boss art changes.

`provenance.json` records the generated source sheets and hashes. Rebuild with
`tools/pack_neon_enemies.py` and the nine sources in its documented order.
The packer only crops, resizes, and arranges cells, preserving their alpha.

`tools/preview_neon_enemies.gd` renders all normal and elite combinations using
the production renderer. `scripts/test.sh enemy_art` checks roster coverage,
unique cell mapping, atlas bounds, alpha, and both elite layers.

All 67 bases now use continuous, twelve-strip idle deformation: heat breathing,
fluid sway, organic pulses, servo motion, signal beats, or spectral drift.
Elite layers use the same deformation so they remain attached. Each roster slot
has a phase offset; combat also offsets individual copies. Existing action lunges,
hit reactions, faction signals and void slice glitches are preserved.
Run the preview tool with `-- animate` to capture 48 production-rendered frames
under `/tmp/neon-review/` (12 fps); no new sprite frames or textures are needed.
