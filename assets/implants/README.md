# Implant artwork and activation frames

All 50 implant IDs in the merged `data/talismans.json` have distinct idle and
activated illustrations. Four 1250×1250 WebP atlases contain 25 250×250 cells each.
`data/implant_art.json` is the authoritative ID-to-cell mapping and specifies
accent colors, activation hot spots and motion families. No game rules were changed.

Art direction / generation specification: compact ivory ceramic, graphite and
copper surgical hardware, confident hand-inked contours, restrained faction colors,
field-service manual shading, strong small-scale silhouettes, uniform warm ivory
background, no labels or frames. Built-in image generation produced two idle 5×5
atlases, then two matching activation edits preserving each device's position,
size, angle and construction while changing a local working component. Asset
preparation normalized the atlas dimensions and removed the ivory paper from
both frame sets using alpha masks. Tile positions and activation hot spots are unchanged.
First atlas follows the first 25 data entries (Hot Chip through Gilded Chip); second
atlas follows the remaining 25 (Ceramic Casing through Inside Contact).

Runtime: `TalismanView` blends the matching active frame over 0.72 seconds and
adds a localized spark, gate, ring, vent, scan, pulse or signal effect. Idle icons
stop processing. Numerical progress/pips, activation totals, single-use state and
daemon-gated status come from `ImplantTracker`, replaying presentation events so
it never reveals counters from a not-yet-animated action. Continuous bonuses show
ON, conditional bonuses ON/OFF, and acquisition-only effects TAKEN. These do not
invent repeated activations. Map triggers have saved run totals and one-shot pulses.

Tap combat/run icons for a larger illustration, current generated rules and live
tracking details. Preview activation is explicitly cosmetic. Implant strips scroll
horizontally so large collections do not consume the battle board.

Reproduce review pages with `tools/implant_review.gd -- page=0`, `page=1`, or
`page=motion`, using a graphical Godot session. The latter emits 18 PNG frames in
`/tmp` for animation review. `tests/test_implant_art.gd` checks full coverage,
filtered progress, no future-state leakage, daemon gates, current thresholds,
save compatibility, and animation shutdown.
