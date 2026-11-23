# TCG Spire systems reference

Detail for individual systems, moved out of CLAUDE.md so every thread doesn't read all of it.
Read the section for the system you're changing. CLAUDE.md keeps commands, layout and rules of thumb.

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
- Upgraded offers (`balance.offer_upgrade`): each program in a fight reward or the shop may arrive one upgrade step ahead (same step as a safehouse upgrade);
  chance = base + per_act x (act - 1 + deep) + per_heat x heat, times `kind_mult`, capped at `max`. `RunState.offer_upgraded(id, kind)` is seeded per floor/kind/card
  (resume-safe, other offer streams untouched); shop items carry `"up"`, rewards carry `"up"` ids; `add_card(id, up)`.
- Combat log: `core/combat_log.gd` turns `combat.events` into plain lines (new event types: add a case in `CombatLog._text`); the Log button under the hand opens `ui/combat_log_overlay.gd` (tap closes).
- Combat animation: `CombatScreen._play_events` replays `combat.events` step by step (input blocked);
  damage/ward/heal events carry `hp`/`ward` after the change for the bars. `step_scale = 0` in tests.

- Fight resume: every player action is logged in `Combat.actions` (`["play", hand_idx, target_idx, pick_idxs]`, `["shut", idx]`, `["end"]`;
  undo rolls it back with the rest of the state). Main saves `Combat.checkpoint()` (actions through the last End turn) in the run save's
  resume dict at each turn start; resuming replays them on a fresh copy of the seeded fight (`Combat.replay`), or restarts it if they no longer fit.
- Events (`data/events.json`): optional `"acts": [1, 2]` and `"job": true` (only on crew jobs with a target; text may use `{client}`/`{target}`,
  `add_card` may use `"faction": "client"`). `RunState.pick_event` avoids events already met this run (`events_seen`, keyed by deep:act:floor so a
  resumed node gets the same event). `test_data` checks the fields.
- Encounters: each crew has 2 normal encounters per tier per act, 2 elites and 2 Cores per act (`<crew>_a<act>t1b`, `..eb`, `..b2`).
  Enemy field `"art": "<enemy id>"` borrows another enemy's illustration (the second Cores reuse other acts' boss art); `FighterView.art_id`.
- Map: `RunMap._spread_types` rerolls a Safehouse, Fixer or Black sentry that follows the same kind on a path, and any Safehouse on the row under
  the last-row one (runs after walls, which add links).
- Settings: `Palette.apply_access` reads text size (`text_size` -> `Palette.text_scale`, applied in `UiKit.label/button`), `colorblind`
  (Okabe-Ito intent colours, `IntentIcon.SAFE`), `no_shake`; `battery_saver` = 30 fps everywhere and a still backdrop (shader `speed`).
- Saves: `Profile.save` verifies the written JSON, keeps `profile.json.bak`; a corrupt profile is moved aside and the backup loaded.
  Login bonus and daily breach only open on a date later than the last one (`LoginBonus.can_claim`, `Records.daily_used`).
