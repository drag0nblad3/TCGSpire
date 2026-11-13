# Field Service card art

Approved November 12, 2026. All 88 card ids map to 448 × 168 regions in
`data/card_art.json`. `ui/card_art.gd` caches AtlasTexture views; CardView uses
these across all screens, retaining procedural art for future unmapped cards.

The WebP atlas contains the approved Street, Burner, Clinic, Flux, Null,
Pirate and Chrome illustrations. Sync Pulse, Capacitor Coil, Null Lance,
Firestorm Protocol, Rekindle Protocol and Leviathan Server use the final
refinement sheet. Review captions are excluded; game names come from CardDef.
Chrome's temporary workshop captions do not rename cards.

Artwork is fitted without stretching or cropping its composition. Two-pixel
extruded gutters and AtlasTexture.filter_clip prevent adjacent art bleeding.
The atlas is preloaded for export; the manifest is under the existing exported
`data/**/*.json` filter. Source sheet identifiers and extraction rectangles are
recorded in provenance.json. Original generated sheets remain in the review
conversation. No gameplay data or card ids changed.

## Preview expansion

The expansion adds 68 distinct illustrations in `field_service_expansion.webp`,
with stable card-id regions in `data/card_art_expansion.json`. The original atlas
and its 88 mappings are unchanged. Both atlases use the same 448 × 168 framing,
non-stretched fitting, clipped sampling and two-pixel gutters. Source sheets and
crop rectangles are recorded in `expansion_provenance.json`.

New art follows the Field Service ink-and-ivory hardware style: faction-colored
components, monochrome Street equipment, and both faction accents on joint cards.
All 156 current cards have artwork, including primary daemon summon portraits.
The coverage test requires every database card to resolve to a unique region.
