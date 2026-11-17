# TCG Spire — agent guide

Original Android card roguelike (Godot 4.4, GDScript) with a collectible-TCG meta.
Original design only: don't copy cards, names, characters or look from existing games.

## Commands (all print a few lines; prefer them over reading files)
- `scripts/test.sh [filter] [-v]` — headless tests + UI smoke boot. Green = one `OK:` line.
- `scripts/cards.sh [filter]` — every card as one line with generated rules text.
- `scripts/sim.sh [n=200] [deck=a,b] [enc=mites,golem]` — bot plays seeded fights, one line per encounter.
- `scripts/sim.sh mode=run [n=100] [heat] [job=ember|all] [profile=new|experienced|veteran|max] [acts=1]` — bot plays whole runs: win %, avg floor,
  top killers; `acts=1` adds per-act death share and turns per normal/elite/boss fight. `profile=experienced`/`veteran` = save after 10/39 bot runs with likely spending, `max` = everything owned/bought (`meta/profile_bot.gd`). Default heat per profile: new 0, experienced 1, veteran 3, max 6. `SAVE_OUT=f.json` writes the built profile, `SAVE_IN=f.json` plays from it instead: compare two builds from the same save (any card or bot change otherwise changes the experienced/veteran save itself).
- `scripts/card_sim.sh [n=60] [profile=new] [heat] [cards=a,b] [jobs=4] [out=/tmp/card_sim]` — per-card balance: 2 copies of each pack card
  forced into the starter picks on its crew's job, scored by floor reached vs seed-paired baseline runs (`rel` = vs crew median), plus
  bot picks/offers and plays/damage/Firewall per play; writes `report.tsv` in `out`. ~10 min for every card at n=80 on 4 cores. Low plays/run = bot blind spot.
- `tools/diag_crew.gd` (`godot --headless --path . -s res://tools/diag_crew.gd -- job=chrome n=200 profile=veteran`, `SAVE_IN` works): per act/kind fight stats (HP in/lost, turns, damage per turn), card picks per crew, the deck at each act boss. `boss3=<encounter>` swaps every act-3 Core for that one (probe one boss against each crew's deck); `focus=<encounter>` splits damage to you by enemy move for that fight (and counts twin crashes).
- `scripts/sim_matrix.sh` — the standard balance check Tyler wants: 150 runs per cell, new heat 0-1, experienced 1-3, veteran 2-5, max 4-6.
- `scripts/shot.sh screen=<name|all> out=/tmp/x.png [plays=2] [end_turn=1] [inspect_enemy=1] [log=1] [theme=archive] [hand=id,id] [pick=1]` — real render to PNG (xvfb). `hand=` sets the combat hand; `pick=1` opens the Dump/recover pick overlay, `log=1` the combat log.
  Screens: hub hub_heat map combat reward rest shop event collection picker pack pack_open pack_shelf pack_premium pack_crew weekly weekly_map login signal_result ice deep end boss inspect rules jobs rig perk tinker crew firmware recompile menu settings resume tutorial coach foil lethal. Uses a throwaway profile.
- Godot binary: `godot` on PATH, or set `GODOT=/path/to/godot`. Cloud sessions: download
  `Godot_v4.4.1-stable_linux.x86_64.zip` from the godotengine GitHub releases.

## Layout
- `core/` pure rules, no Nodes: `combat.gd` (turn flow, piles, events log), `effects.gd`
  (op vocabulary shared by cards AND enemy moves), `statuses.gd`, `card_db.gd` (loads data),
  `game_rng.gd` (seeded, `fork(stream)`), `bot.gd` (state-aware greedy autoplayer for sims),
  `talismans.gd` (passive items: trigger hooks fired by Combat, effects use Effects ops),
  `card_mods.gd` (one mod per CardInstance: cost/keyword/effect changes, restrictions).
- `meta/` between-run state: `profile.gd` (versioned save, `_migrate`), `collection.gd`
  (counts, dust, craft/disenchant), `packs.gd` (pack kinds: "normal", "premium" (Zero-day cache), "crew:<faction>" for all 7 crews;
  `balance.pack_types` overrides `balance.pack` per type; `Profile.packs` counts by kind, `Profile.pack_pity` keeps mercy timers per kind;
  each Core breached pays a crew pack of the client crew (`RunState.client_crew`, Street when freelance), a finished job pays premium, everything else is normal; `ui/pack_art.gd` draws each kind), `run_state.gd` (deck/HP/gold/talismans/heat,
  rest, shop, events; `to_dict`/`from_dict`), `run_save.gd` (run in progress, saved at every run screen change by
  `main._save_run`, resumed from the hub; a fight restarts from turn 1), `run_map.gd` (seeded branching map; short `walls` = segments in map space that cut every link they cross,
  a stranded node gets an unwalled diagonal; walls are centred on the 1-2 links they cut; nodes sealed off become "vault" (elite guard, then rare implant + creds); jumps are an earned
  ability, perk mod `jumps` = charges per act: diagonal up one floor through walls, you play the landing node, `RunState.jump_moves`), `run_outcomes.gd` (run-level ops for
  events/pickups), `run_bot.gd` (plays whole runs for sims), `profile_bot.gd` (builds experienced/veteran/maxed saves for sims). Progression: XP levels, card mastery, heat.
  `jobs.gd`: every run is a job for one client faction (data/factions.json, 6 crews in 3 rival pairs) run
  against targets (the rival, plus heat mod "extra_targets"): >= half the cards picked (rounded up, not of the slots) are the client's (joint ops count, Street doesn't; `Jobs.check` for the picker, `Jobs.fit` trims any start), targets banned
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
  that is up tops its HP back up. Daemon-only trigger `closed` fires when that daemon shuts down (ran out, hit, crashed); re-running a daemon with a `closed` rule restarts it instead (payoff fires, fresh HP): Botnet Lease. Implant trigger `daemon_closed` and Hive Link's blast fire on "destroyed or refreshed": shut down, and also when re-running tops a daemon up. Hive Link (`manual_crash` mod) adds a combat "Shut down" button (`Combat.shutdown_daemon`). Rig mods may list the total per rank (`[10, 25, 45]`, `Perks.mod_at`). Scaling: `daemon_hp` (rig/subroutine mod, implant `"daemon": {"hp": n}`),
  `rally` (+HP to all daemons), Patch on a daemon (cards with `"target": "ally"`). In a daemon rule trigger, `"to": "this"` targets that daemon (Leech Line repairs itself). Daemon hits come from you but skip your own attack modifiers (Boost, Throttled, `attack_bonus`); their damage buff is the player status `uplink` (Uplink, +1 per stack to daemon hits; Chrome: Hive Sync, Overclock Grid). Per source `daemons` = daemons up. Daemon "front" hits skip a shielded boss and land on the first enemy they can hurt (its pylons).
- Card pool: every crew (Street included) has 10 common / 10 uncommon / 6 rare / 2 mythic (`test_data` enforces it).
  Joint ops (`data/cards/joint.json`, `"faction2"`): one per non-rival crew pair, on top of the spread. They count as
  both crews for job picks (`CardDef.is_of`), are banned if either crew is a target (`banned_by`), stay out of binders,
  and firmware is paid in the home crew's rep. Cards without an entry in `card_art.json` draw the procedural fallback.
  Ops added for them: `amplify` (multiply a status), `strip` (remove an enemy's helpful statuses), `sacrifice` (crash your
  front daemon, its HP becomes damage/ward/heal/draw/energy), `damage_per_status` with `"of": "target"`, status `stall`
  (Lagged: the enemy skips one move and keeps the intent; never stacks).
- Records (`meta/records.gd`, cosmetic/currency only): run tally from combat events (`RunState.tally`), contract bonus
  clauses (`data/contracts.json`, rolled per job offer, pay rep), exploit log (`data/exploits.json`, lifetime stats),
  binders (own every card of a crew rarity page: dust, full set = card back + title), daily breach (fixed seed/job per
  date, one try, scored), weekly challenge (`meta/weekly.gd`: Monday-keyed job at balance.weekly.heat, rule modifiers
  from `data/weekly.json` (perk-shaped: mods/heat/triggers/pickup + text), own cards but no rig/firmware, first clear pays a premium pack,
  never unlocks heat), daily login bonus (`meta/login_bonus.gd`, balance.login: every day one normal pack plus scrap, day 7 upgrades it to premium, missed days never reset), quick scrap in pack opening (`Profile.quick_scrap`: only copies beyond the deck limit), glitch foils (`pack.foil_chance`, `shaders/glitch_foil.gdshader`), 3 saved loadouts per crew.
- Card abilities wave (`data/cards/abilities.json`, 4 per crew; art pending, `test_card_art` AWAITING_ART):
  X cost (`"cost": "X"` = `CardDef.X_COST`; spends all RAM, `Combat.x_spent`; cost mods don't fit). Scaling: any effect may carry
  `per` (`Effects.PER_SOURCES`: x, draw_pile, discard_pile, hand, wiped, dumped) + `per_mult` + `per_key` (default `LOOP_KEY`):
  number = printed + floor(count x per_mult), text "6X"/"3+N". Dump (`dump` op, amount 0 = whole hand) is a cost: needs that many
  other cards (`Combat.dump_need`); player picks via `play_card(idx, target, picks)` (UI overlay from `Combat.pick_request`), the rest
  are picked "When dumped" cards first, then Locked, then left to right. Card field `on_dump` (upgrade may replace it) fires when dumped.
  `recover` op (`from` discard/wiped, `into` draw/top): shuffle a picked card back in; no Rootkits or recover cards back from Wipe.
  Evolve: card field `"evolve": {"after": 20, "into": id}`; `CardInstance.uses` counts runs for the whole job (saved in the run deck),
  the copy turns into the evolved card mid-fight (keeps upgrade/firmware/mod); combat copies keep `origin`, `Combat.sync_origins()`
  (called by `RunState.finish_combat`) writes progress back. Evolved forms are `"token": true`: `CardDB.ids_where` skips them, so
  they never drop, sell or count for binders.
- Interrupt (`interrupt` op: `kinds` from `Intents.INTERRUPTIBLE`, optional `effects` paid once per enemy cut): cancels only the named
  intent kinds of the target's next move (`Fighter.interrupted`, cleared after the move); misses if the intent isn't there. `Intents.kind_of`
  classifies a move effect. One uncommon Interrupt program per crew (spread is now 9 uncommons); they await art (`test_card_art` allowlist).
- Deep Stack (`balance.deep_stack`, `Records.deep_unlocked`: a win at `unlock_heat`+): normal jobs only (`RunState.deep_ok`). After the final Core
  the run waits (`deep_pending`) for `descend()` (new last-act map, enemy HP/damage compound per `deep` layer) or `jack_out()`. The win is banked
  first; each deep Core still pays a crew pack (`deep_cores`), but no rep/act XP; depth sets `stats.best_depth`. The run bot always jacks out.
- ICE database (Records screen "ICE" tab): `RunState.ice` counts enemies per fight (`Records.tally_ice`), folded into `Profile.ice` at run end;
  `balance.ice_db.reveal` fights decode an entry (moves + `data/ice_lore.json` line; every enemy needs one, `Records.validate`).
- Boss rules (`core/boss_rules.gd`, enemy def `"rules": {...}`; hooks called by Combat, chips/inspector/rules page/ICE text generated from it): `phases` (new moves at HP marks, a hit can't
  carry past a mark, debuffs wiped), `timer` (Trace: Boost every move after N moves), `tide` (high/low damage-taken cycle by round, `low_move`), `gauge` (your attack hits add heat; full = effects
  stapled to its next move via `Fighter.bonus`), `jam` (intent hidden every Nth turn; Exposed or any Interrupt clears it), `twin` (survivor's move after next is Restore = op `revive`, counts as Repair
  for Interrupt), `pool` + `leaves_at` (bodies share one HP total, `Combat.pools`), `taken` (multiplier per damage kind), `shielded_by` + `respawn` (pylons; `grounded`: boss loses half a status, rounded up, when the last pylon falls: Storm Regent Might), `guarded` (single-target hits land on
  escorts: `BossRules.guard_target`), `bond` (survivor heals + status). Ops added: `devour` (eats `Fighter.spawned` helpers), `revive`, `add_card` `"pile": "draw"`; card field `"hatch"` (Spore Pod
  spawns that enemy if discarded unplayed). One-off moves use `Fighter.override`. Extra boss bodies/pylons use transparent art via `BossSupportArt`, with animation in `VirtualBossArt`. The hatchable Spore Pod has dedicated Field Service card art. Balance of these is untested by sims.
  `scripts/shot.sh screen=boss enc=<encounter id>` renders any boss fight.
- Offer nudge (`meta/offer_nudge.gd`, `balance.nudge`): hidden weights inside a rolled rarity for run offers (rewards, rerolls, shop cards/implants, implant drops; never packs): missing Handshake partner, answers to this act's boss rules, deck strategy themes, implants that fit the deck. Capped per card; at most half an offer (rounded up) comes from weighted picks.
- Combat log: `core/combat_log.gd` turns `combat.events` into plain lines (new event types: add a case in `CombatLog._text`); the Log button under the hand opens `ui/combat_log_overlay.gd` (tap closes).
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
  card_played (filters card_type, keyword, every), kill, daemon_closed, loop, reshuffle. Implants can also carry `mods` (perk mod keys in `Talismans.MOD_KEYS`,
  incl. `jumps`, `run_scrap`, `bonus_packs`), `flags` (always-on `DaemonRules.FLAGS`, `flags_while_daemon`), `daemon` {hp, hp_mult}, `run` triggers
  (jump, vault -> run outcomes) and a `faction` (never rolls when that crew is a target). Event outcomes use `RunOutcomes.OPS`.
- Balance check after content changes: `scripts/sim.sh mode=run n=400 job=all` (~20 s). Bot baseline at heat 0
  on jobs (new profile, 3 acts): ~30% clear act 1, ~5% win; experienced (10 runs) ~37% win at heat 1, ~5% at heat 2; veteran (25 runs, now 39) ~47% at heat 2,
  ~15% at heat 3; max ~89% at heat 3, ~33% at heat 6 (Tyler is fine with lower rates since Act 3). Heat `enemy_hp_pct`/`enemy_dmg_pct` compound per level (`RunState.heat_mult`), the main lever. `balance.enemy_dmg_mult` (0.85) scales all enemy damage on top. The first 2 floors of each act are eased (`balance.act_start_ease`: -20% enemy HP, -10% damage, multiplied on top of act/heat/perk mults; `RunState.act_start_mult`).
  Runs pay `packs_per_boss`. Humans should do much
  better. Watch the killers list. `core/bot.gd` values (card, target) pairs from live state (no search/copies);
  `meta/run_bot.gd` uses static `card_value` for picks/upgrades/shop and scores event outcomes. Keep both cheap.
- Save format change: bump `Profile.SAVE_VERSION` and add a step in `_migrate()`.
- Packs are earned by play only. Rarity should add complexity, not raw power.
- Implant rarity is complexity too: common = flat always-on bonus, uncommon = a condition or counter, rare = changes a rule, boss = strong or unique. Implants never carry a penalty (no lost HP/slots/hand, no curses; `test_implants_have_no_penalties`). Keep power close across rarities and avoid two implants that differ only in size.
- GDScript gotcha: `var x := untyped_value` fails to parse; write `var x: Type = ...`.

## Android builds (only when Tyler asks for one)
- `scripts/build_apk.sh` -> `build/tcgspire.apk` (debug, arm64). Needs Godot 4.4.1 export templates
  in `~/.local/share/godot/export_templates/4.4.1.stable/`, a JDK and an Android SDK with build-tools.
- GitHub: Actions tab -> "android-apk" -> Run workflow (manual only, never on push; optional `ref` input picks the commit). It publishes the APK
  as a prerelease (tag `build-<run>-<sha>`) with a direct download link, and also keeps it as the run artifact.
- Signing: `signing/debug.keystore` (pass "android") is committed on purpose so every APK has the same signature
  and installs over the last one. Never regenerate it, or phones must uninstall (losing the save).
- Game icon: `node tools/icon/make_icon.js` redraws `icon.png` and the Android adaptive layers in `assets/icon/` (foreground/background/monochrome,
  432px, art kept inside the 66dp safe circle). `pick=<design>` swaps design, `out=/tmp/x` renders every design for review.
- `export_presets.cfg` includes `data/**/*.json` (data files aren't resources); keep that filter.
- Cloud sessions can't reach dl.google.com, so there's no real SDK there. A stand-in apksigner can be
  built from `com.android.tools.build:apksig` on Maven Central (v2 signing only, Android 7+).
