# TCG Spire — agent guide

Original Android card roguelike (Godot 4.4, GDScript) with a collectible-TCG meta.
Original design only: don't copy cards, names, characters or look from existing games.

## Commands (all print a few lines; prefer them over reading files)
- `scripts/test.sh [filter] [-v]` — headless tests + UI smoke boot. Green = one `OK:` line.
- `scripts/cards.sh [filter]` — every card as one line with generated rules text.
- `scripts/sim.sh [n=200] [deck=a,b] [enc=mites,golem]` — bot plays seeded fights, one line per encounter.
- `scripts/sim.sh mode=run [n=100] [heat] [job=ember|all] [profile=new|experienced|veteran|max] [acts=1]` — bot plays whole runs: win %, avg floor,
  top killers; `acts=1` adds per-act death share and turns per normal/elite/boss fight. `profile=experienced`/`veteran` = save after 10/39 bot runs with likely spending, `max` = everything owned/bought (`meta/profile_bot.gd`). Default heat per profile: new 0, experienced 1, veteran 3, max 6.
- `scripts/sim_matrix.sh` — the standard balance check Tyler wants: 150 runs per cell, new heat 0-1, experienced 1-3, veteran 2-5, max 4-6.
- `scripts/shot.sh screen=<name|all> out=/tmp/x.png [plays=2] [end_turn=1] [theme=archive]` — real render to PNG (xvfb).
  Screens: hub map combat reward rest shop event collection picker pack pack_open end inspect rules jobs rig perk tinker crew firmware recompile menu settings resume tutorial coach. Uses a throwaway profile.
- Godot binary: `godot` on PATH, or set `GODOT=/path/to/godot`. Cloud sessions: download
  `Godot_v4.4.1-stable_linux.x86_64.zip` from the godotengine GitHub releases.

## Layout
- `core/` pure rules, no Nodes: `combat.gd` (turn flow, piles, events log), `effects.gd`
  (op vocabulary shared by cards AND enemy moves), `statuses.gd`, `card_db.gd` (loads data),
  `game_rng.gd` (seeded, `fork(stream)`), `bot.gd` (state-aware greedy autoplayer for sims),
  `talismans.gd` (passive items: trigger hooks fired by Combat, effects use Effects ops),
  `card_mods.gd` (one mod per CardInstance: cost/keyword/effect changes, restrictions).
- `meta/` between-run state: `profile.gd` (versioned save, `_migrate`), `collection.gd`
  (counts, dust, craft/disenchant), `packs.gd`, `run_state.gd` (deck/HP/gold/talismans/heat,
  rest, shop, events; `to_dict`/`from_dict`), `run_save.gd` (run in progress, saved at every run screen change by
  `main._save_run`, resumed from the hub; a fight restarts from turn 1), `run_map.gd` (seeded branching map), `run_outcomes.gd` (run-level ops for
  events/pickups), `run_bot.gd` (plays whole runs for sims), `profile_bot.gd` (builds experienced/veteran/maxed saves for sims). Progression: XP levels, card mastery, heat.
  `jobs.gd`: every run is a job for one client faction (data/factions.json, 6 crews in 3 rival pairs) run
  against targets (the rival, plus heat mod "extra_targets"): >= half the picks the client's, targets banned
  from picks and offers, targets' enemies (`data/enemies/factions.json`, encounters with "faction") fill
  ~60% of fights/elites and 75% of bosses (18 crew bosses, 3 acts), pays the client's rep.
  Heat 6 "double_cross": the client joins the targets for the last act and its Core is the final boss. Firmware tier 2 bakes a mod
  into a card (`Profile.bake_firmware_mod`). `perks.gd`: scope "run" = subroutines (picked after
  elites/act boss), scope "rig" = permanent ranks bought with the perk's faction rep. Firmware
  (`Profile.flash_firmware`) permanently upgrades a card id: rep for faction cards, dust for Street/starter.
- `ui/` presentation only, built in code (no .tscn besides main). `main.gd` is the screen flow;
  `ui_kit.gd` has label/button/flow/scroll/toast helpers. Reads `combat.events` to animate.
  Card illustrations use `assets/cards/field_service.webp` via `ui/card_art.gd` and `data/card_art.json`. Other art uses `sigil.gd` (procedural glyphs), `intent_icon.gd`, `palette.gd` (UI colors), and `shaders/`.
- Setting: cyberpunk hacking sim ("Neon Undercity"). Player = Ghost, cards = programs, energy = RAM,
  Ward = Firewall, units = daemons, talismans = implants, map = the Stack. Ids in JSON/code keep the old
  generic names (burn, ward, exhaust...) so saves and tests stay stable; player-facing names live in
  `core/lexicon.gd` (statuses, keywords, card types, factions) and `Palette.DEFAULT_WORDS`. New content:
  name it in-world, write text with Lexicon terms.
- Skins: `ui/themes.gd` (colors, fonts, frame "plain"/"circuit", backdrop style 0-4). Default "glassnet"
  (shattered holo-glass + neon cracks). Read via `Palette.*`; never hardcode colors. Saved in `Profile.settings.theme`.
- Input: custom controls use `Tap` (`ui/tap.gd`) for tap vs drag vs long-press. Never handle
  InputEventScreenTouch too (Android emulates mouse from touch: double events = select/deselect bug).
  Long-press a card = `CardInspector`; rules text lives in `Rules` (generated from Statuses.DEFS,
  CardDef.KEYWORD_DESC, Intents.DESC) so new content documents itself.
- Daemons (unit cards) are temporary rule changes, not attackers: `summon` = {name, hp, rule}; `rule` = passive
  `flags` (`DaemonRules.FLAGS`) + implant-style `triggers`. HP is the countdown: -1 at the start of each of your
  turns, -1 per hit taken, Purge moves (enemy damage `"to": "daemon"`) take their full number. Re-running a daemon
  that is up tops its HP back up. Scaling: `daemon_hp` (rig/subroutine mod, implant `"daemon": {"hp": n}`),
  `rally` (+HP to all daemons), Patch on a daemon (cards with `"target": "ally"`).
- Card pool: every crew (Street included) has 8 common / 6 uncommon / 4 rare / 2 mythic (`test_data` enforces it).
  Joint ops (`data/cards/joint.json`, `"faction2"`): one per non-rival crew pair, on top of the spread. They count as
  both crews for job picks (`CardDef.is_of`), are banned if either crew is a target (`banned_by`), stay out of binders,
  and firmware is paid in the home crew's rep. Cards without an entry in `card_art.json` draw the procedural fallback.
  Ops added for them: `amplify` (multiply a status), `strip` (remove an enemy's helpful statuses), `sacrifice` (crash your
  front daemon, its HP becomes damage/ward/heal/draw/energy), `damage_per_status` with `"of": "target"`, status `stall`
  (Lagged: the enemy skips one move and keeps the intent; never stacks).
- Records (`meta/records.gd`, cosmetic/currency only): run tally from combat events (`RunState.tally`), contract bonus
  clauses (`data/contracts.json`, rolled per job offer, pay rep), exploit log (`data/exploits.json`, lifetime stats),
  binders (own every card of a crew rarity page: dust, full set = card back + title), daily breach (fixed seed/job per
  date, one try, scored), glitch foils (`pack.foil_chance`, `shaders/glitch_foil.gdshader`), 3 saved loadouts per crew.
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
- New talisman/event/mod/perk = JSON only (`mods.json`, `perks.json`; perk mod keys in `Perks.MODS`). Talisman triggers: combat_start, turn_start, turn_end,
  card_played (filters card_type, every), kill. Event outcomes use `RunOutcomes.OPS`.
- Balance check after content changes: `scripts/sim.sh mode=run n=400 job=all` (~20 s). Bot baseline at heat 0
  on jobs (new profile, 3 acts): ~30% clear act 1, ~5% win; experienced (10 runs) ~37% win at heat 1, ~5% at heat 2; veteran (25 runs, now 39) ~47% at heat 2,
  ~15% at heat 3; max ~89% at heat 3, ~33% at heat 6 (Tyler is fine with lower rates since Act 3). Heat `enemy_hp_pct`/`enemy_dmg_pct` compound per level (`RunState.heat_mult`), the main lever.
  Runs pay `packs_per_boss`. Humans should do much
  better. Watch the killers list. `core/bot.gd` values (card, target) pairs from live state (no search/copies);
  `meta/run_bot.gd` uses static `card_value` for picks/upgrades/shop and scores event outcomes. Keep both cheap.
- Save format change: bump `Profile.SAVE_VERSION` and add a step in `_migrate()`.
- Packs are earned by play only. Rarity should add complexity, not raw power.
- GDScript gotcha: `var x := untyped_value` fails to parse; write `var x: Type = ...`.

## Android builds (only when Tyler asks for one)
- `scripts/build_apk.sh` -> `build/tcgspire.apk` (debug, arm64). Needs Godot 4.4.1 export templates
  in `~/.local/share/godot/export_templates/4.4.1.stable/`, a JDK and an Android SDK with build-tools.
- GitHub: Actions tab -> "android-apk" -> Run workflow (manual only, never on push). APK is the artifact.
- Signing: `signing/debug.keystore` (pass "android") is committed on purpose so every APK has the same signature
  and installs over the last one. Never regenerate it, or phones must uninstall (losing the save).
- `export_presets.cfg` includes `data/**/*.json` (data files aren't resources); keep that filter.
- Cloud sessions can't reach dl.google.com, so there's no real SDK there. A stand-in apksigner can be
  built from `com.android.tools.build:apksig` on Maven Central (v2 signing only, Android 7+).
