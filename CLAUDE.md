# TCG Spire — agent guide

Original Android card roguelike (Godot 4.4, GDScript) with a collectible-TCG meta.
Original design only: don't copy cards, names, characters or look from existing games.

## Commands (all print a few lines; prefer them over reading files)
- `scripts/test.sh [filter] [-v]` — headless tests + UI smoke boot. Green = one `OK:` line.
- `scripts/cards.sh [filter]` — every card as one line with generated rules text.
- `scripts/sim.sh [n=200] [deck=a,b] [enc=mites,golem]` — bot plays seeded fights, one line per encounter.
- `scripts/sim.sh mode=run [n=100] [heat=0]` — bot plays whole runs: win %, avg floor, top killers.
- `scripts/shot.sh screen=<name|all> out=/tmp/x.png [plays=2] [end_turn=1] [theme=archive]` — real render to PNG (xvfb).
  Screens: hub map combat reward rest shop event collection picker pack end inspect rules. Uses a throwaway profile.
- Godot binary: `godot` on PATH, or set `GODOT=/path/to/godot`. Cloud sessions: download
  `Godot_v4.4.1-stable_linux.x86_64.zip` from the godotengine GitHub releases.

## Layout
- `core/` pure rules, no Nodes: `combat.gd` (turn flow, piles, events log), `effects.gd`
  (op vocabulary shared by cards AND enemy moves), `statuses.gd`, `card_db.gd` (loads data),
  `game_rng.gd` (seeded, `fork(stream)`), `bot.gd` (greedy autoplayer for sims),
  `talismans.gd` (passive items: trigger hooks fired by Combat, effects use Effects ops).
- `meta/` between-run state: `profile.gd` (versioned save, `_migrate`), `collection.gd`
  (counts, dust, craft/disenchant), `packs.gd`, `run_state.gd` (deck/HP/gold/talismans/heat,
  rest, shop, events), `run_map.gd` (seeded branching map), `run_outcomes.gd` (run-level ops for
  events/pickups), `run_bot.gd` (plays whole runs for sims). Progression: XP levels, card mastery, heat.
- `ui/` presentation only, built in code (no .tscn besides main). `main.gd` is the screen flow;
  `ui_kit.gd` has label/button/flow/scroll/toast helpers. Reads `combat.events` to animate.
  All art is code: `sigil.gd` (procedural glyphs), `intent_icon.gd`, `palette.gd` (all colors), `shaders/`.
- Worlds/themes: `ui/themes.gd` (colors, fonts, frame shape, backdrop style, and `words`: title, hero,
  pack/dust names, faction names). Read them via `Palette.*`, `Palette.w("dust")`, `Palette.faction_name(f)`;
  never hardcode colors or world words in screens. Choice saved in `Profile.settings.theme`.
- Input: custom controls use `Tap` (`ui/tap.gd`) for tap vs drag vs long-press. Never handle
  InputEventScreenTouch too (Android emulates mouse from touch: double events = select/deselect bug).
  Long-press a card = `CardInspector`; rules text lives in `Rules` (generated from Statuses.DEFS,
  CardDef.KEYWORD_DESC, Intents.DESC) so new content documents itself.
- Combat animation: `CombatScreen._play_events` replays `combat.events` step by step (input blocked);
  damage/ward/heal events carry `hp`/`ward` after the change for the bars. `step_scale = 0` in tests.
- `data/` all content as JSON: `cards/<faction>.json` (one card per line), `enemies/`,
  `encounters.json` (kind normal/elite/boss, tier), `talismans.json`, `events.json`,
  `balance.json` (every tuning number: map weights, prices, heat levels, XP, mastery).
- `tests/test_*.gd` extend `TestCase`; methods named `test_*` run automatically.

## Rules of thumb
- Content change (new card/enemy/number) = edit JSON only, then `scripts/test.sh data` and `scripts/sim.sh`.
- New mechanic = add op to `Effects.OPS` + `resolve()` + `describe()` (+ status in `Statuses.DEFS`),
  then a test in `tests/test_effects.gd`. Unknown ops/params/statuses fail `test_data`.
- Keep `core/` free of Node/scene code so it stays testable headless and deterministic.
  All randomness goes through `GameRng`; events hold ids/numbers only.
- New talisman/event = JSON only. Talisman triggers: combat_start, turn_start, turn_end,
  card_played (filters card_type, every), kill. Event outcomes use `RunOutcomes.OPS`.
- Balance check after content changes: `scripts/sim.sh mode=run n=150`. Greedy bot baseline at heat 0:
  ~12% clear act 1, ~3% win the full 2-act run (humans should do much better). Watch the killers list.
- Save format change: bump `Profile.SAVE_VERSION` and add a step in `_migrate()`.
- Packs are earned by play only. Rarity should add complexity, not raw power.
- GDScript gotcha: `var x := untyped_value` fails to parse; write `var x: Type = ...`.

## Android builds (only when Tyler asks for one)
- `scripts/build_apk.sh` -> `build/tcgspire.apk` (debug, arm64). Needs Godot 4.4.1 export templates
  in `~/.local/share/godot/export_templates/4.4.1.stable/`, a JDK and an Android SDK with build-tools.
- GitHub: Actions tab -> "android-apk" -> Run workflow (manual only, never on push). APK is the artifact.
- `export_presets.cfg` includes `data/**/*.json` (data files aren't resources); keep that filter.
- Cloud sessions can't reach dl.google.com, so there's no real SDK there. A stand-in apksigner can be
  built from `com.android.tools.build:apksig` on Maven Central (v2 signing only, Android 7+).
