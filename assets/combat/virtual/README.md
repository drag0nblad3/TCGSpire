# Virtual boss portraits

All 24 existing boss IDs use original generated virtual-entity art. The four
source sheets were generated in the boss graphics conversation; provenance.json
records exact source image identifiers and extraction rectangles. Captions and
sheet borders are excluded. Existing SVG assets remain available for rollback.

All 24 bosses use VirtualBossArt: bounded horizontal texture
warps plus faction-specific particles, cell rings, data streams, drone orbits,
and signal bars. FighterView supplies the current theme accent, signature charge
and a decaying burst driven by the existing enemy_move event. Dead bosses use a
static portrait. No combat rules, save data, timing or random streams change.

To disable these animations, make VirtualBossArt.supports return false. Portraits remain.
The preview tool tools/preview_virtual_bosses.gd renders the same draw function
at reproducible times; its middle section demonstrates the move burst.
