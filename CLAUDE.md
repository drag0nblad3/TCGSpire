# TCG Spire — agent guide

Original Android card roguelike (Godot 4.4, GDScript) with a collectible-TCG meta.
Original design only: don't copy cards, names, characters or look from existing games.

## Commands (all print a few lines; prefer them over reading files)
- `scripts/test.sh [filter] [-v]` — headless tests + UI smoke boot. Green = one `OK:` line.
- `scripts/cards.sh [filter]` — every card as one line with generated rules text.
- `scripts/sim.sh [n=200] [deck=a,b] [enc=mites,golem]` — bot plays seeded fights, one line per encounter.
- `scripts/shot.sh out=/tmp/x.png [plays=2]` — real render of the main scene to PNG (xvfb).
- Godot binary: `godot` on PATH, or set `GODOT=/path/to/godot`. Cloud sessions: download
  `Godot_v4.4.1-stable_linux.x86_64.zip` from the godotengine GitHub releases.

## Layout
- `core/` pure rules, no Nodes: `combat.gd` (turn flow, piles, events log), `effects.gd`
  (op vocabulary shared by cards AND enemy moves), `statuses.gd`, `card_db.gd` (loads data),
  `game_rng.gd` (seeded, `fork(stream)`), `bot.gd` (greedy autoplayer for sims).
- `meta/` between-run state: `profile.gd` (versioned save, `_migrate`), `collection.gd`
  (counts, dust, craft/disenchant), `packs.gd`, `run_state.gd`.
- `ui/` presentation only. Reads `combat.events` to animate; never changes rules.
  All art is code: `sigil.gd` (procedural glyphs), `palette.gd` (all colors), `shaders/`.
- `data/` all content as JSON: `cards/<faction>.json` (one card per line), `enemies/`,
  `encounters.json`, `balance.json` (every tuning number).
- `tests/test_*.gd` extend `TestCase`; methods named `test_*` run automatically.

## Rules of thumb
- Content change (new card/enemy/number) = edit JSON only, then `scripts/test.sh data` and `scripts/sim.sh`.
- New mechanic = add op to `Effects.OPS` + `resolve()` + `describe()` (+ status in `Statuses.DEFS`),
  then a test in `tests/test_effects.gd`. Unknown ops/params/statuses fail `test_data`.
- Keep `core/` free of Node/scene code so it stays testable headless and deterministic.
  All randomness goes through `GameRng`; events hold ids/numbers only.
- Save format change: bump `Profile.SAVE_VERSION` and add a step in `_migrate()`.
- Packs are earned by play only. Rarity should add complexity, not raw power.
- GDScript gotcha: `var x := untyped_value` fails to parse; write `var x: Type = ...`.

## Android export (not set up yet)
Needs Android SDK + JDK 17 + export templates, an `export_presets.cfg` with
`*.json` in the include filter (data files aren't resources), and a debug keystore.
