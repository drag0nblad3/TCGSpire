# TCG Spire

An original card roguelike for Android with a collectible-card meta: build a
collection between runs, pick a few cards from it to seed each run, draft the
rest as you climb, and earn packs by playing.

Built with Godot 4.4. All visuals are code (procedural sigils, shaders, typography),
so there's very little hand-made art to maintain.

![Screens](docs/screens.png)

## Status
Playable prototype:
- Branching seeded map with fights, elites, events, rest sites, shops, treasure and 2 bosses
- 2 acts, 5 factions (Neutral, Ember, Tide, Bloom, Void), 62 cards, units on a 3-slot board, 11 statuses
- 25 talismans with trigger hooks, 11 events, curses, 4 bosses
- Collection with crafting/disenchanting, pack opening, a pre-run deck picker
- Long-term progression: account levels, card mastery (dust, then a foil copy), 6 heat levels
Next: act 3 and a final boss, card art polish, Android export.

## Develop
Open the folder in Godot 4.4 and press Play, or from a shell:

    scripts/test.sh      # tests + smoke boot
    scripts/cards.sh     # card list
    scripts/sim.sh       # balance sim

See `CLAUDE.md` for architecture and conventions.
