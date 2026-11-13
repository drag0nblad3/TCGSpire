# Program combos expansion

Seven new uncommon cards: one per crew, bringing each crew to 8 common / 7 uncommon / 4 rare / 2 mythic. The initial additions preserve existing card IDs; the later refresh below revises seven older cards. The additions enter normal collection, pack, crafting, job, shop and reward filters. All cost 1 RAM.

| Card | Crew | Base rules | Recompile (+) |
|---|---|---|---|
| Uplink | Street | Cache. 5 Firewall. If Downlink was played this turn, draw 2. | 7 Firewall |
| Downlink | Static | Cache. 6 damage. If Uplink was played this turn, deal 3 additional damage to all enemies. | 8 damage; 4 to all |
| Capacitor Lance | Burner | 6 damage. Each unplayed end-turn discard charges this copy by 4, capped at +8; playing resets charge. | 8 base; +5 charge, capped at +10 |
| Pocket Compiler | Chrome | Cache (Retain). 3 Firewall. Store up to three other plays while held: Exploit adds 3 damage, Script/Daemon adds 3 Firewall, Rootkit adds draw 1. Play to execute and clear. | 4 base Firewall and 4 per damage/Firewall instruction |
| Seed Packet | Wetware | 3 Firewall. Plant 7 Firewall on the top draw-pile card, triggered once when drawn. | 4 immediate, 9 planted |
| Breach Sequence | Null | 6 damage. If the immediately previous plays this turn were Script then Exploit, deal 5 more and draw 1. | 8 base, 7 bonus |
| Signal Baton | Flux | 4 Firewall. Give leftmost other hand card Relay 2: on play gain that much Firewall, then pass +1 to the leftmost remaining card, capped at 5. | 6 immediate, Relay 3, capped at 6 |

Handshake partners can be cached across turns to line up the desired order. Street Uplink is available alongside every client faction. A sequence never counts its own payoff card. Compile only records cards held before the other play started, cannot record itself, and retains stored instructions across turns. Compiler damage uses its chosen enemy target.

Payload and Relay collisions keep the stronger value instead of adding. Plant does nothing with an empty draw pile. Relay ends if no other card remains. Charge, instructions, payload and Relay survive pile movement but reset at the start of a new combat. Combat copies the run deck, so preview/runtime memory cannot leak back into saved deck instances.

Card text shows live stored state. Combat hints show the last two card types when a Sequence card is held, and name ready Handshake cards. The inspector and rules reference explain all six mechanics. Fork is not included in this batch.

New art: `assets/cards/field_service_programs.webp`, mapped by `data/card_art_programs.json`; seven unique 448×168 regions. Prompt: original field-service technical hardware, ivory ink and engraved hatching on charcoal, monochrome Street/Chrome and faction-colored components, 2×4 atlas with no labels. Generated with the built-in image tool, then fitted without stretching; source crop provenance is beside the atlas.

Validation: `scripts/test.sh`, `scripts/sim.sh mode=run n=400 job=all`. Focused regressions live in `tests/test_programs.gd`; deterministic full fights, copies/reset, invalid plays, caps, Retain, history, draw payloads and card upgrades are covered. Phone inspection can be rendered with `scripts/shot.sh screen=inspect card=pocket_compiler out=/tmp/compiler.png` when Xvfb is installed.

## Wave two: fourteen more cards

Each crew gains one uncommon and one rare, for 8 common / 8 uncommon / 5 rare / 2 mythic. There are now 21 cards across both program-combo batches.

| Card | Crew · RAM | Purpose |
|---|---|---|
| Checksum | Street · 0 | 2/4 Firewall; after Uplink, draw 1. Once per turn. |
| Reserve Parcel | Street · 0 | Plant 6/9 Firewall on the next draw; Wipe. |
| Thermal Reservoir | Burner · 1 | 5/7 Firewall; unplayed discards charge +3/+4, capped at +6/+8. |
| Arc Vent | Burner · 2 | 5/7 damage to all enemies; unplayed discards charge +3, capped at +6. |
| Carrier Wave | Flux · 1 | 5/7 damage and Relay 2, capped at 5. |
| Circuit Breaker | Flux · 1 | 5/8 damage, plus twice this copy's Relay. Keep its Firewall payout but end the chain. |
| Spore Cache | Wetware · 1 | Gain 1/2 Patch and plant 6/7 Firewall. |
| Graft Compiler | Wetware · 1 | Cache; 2/3 Firewall plus up to three stored plays, each granting 3/4 Firewall. Rootkits instead draw 1. |
| Assembly Call | Chrome · 1 | 5/7 Firewall; after Pocket Compiler, draw 2. |
| Queue Forge | Chrome · 2 | Cache; four instruction slots at strength 4/5, followed by Relay 2/3, capped at 5. |
| Ghost Key | Null · 0 | 3/4 damage; after Script → Script, apply 1/2 Exposed. Once per turn. |
| Backdoor | Null · 1 | 6/9 damage; after Exploit → Script, apply Lagged. |
| Rebroadcast | Static · 1 | 4/6 Firewall; after Downlink, grant Relay 3/4, capped at 6. |
| Encore Buffer | Static · 1 | 5/8 damage; after Rebroadcast, refund 1 RAM and draw 1. Once per turn. |

Numbers separated by `/` are base/Recompile (+). Firmware scales the supported numeric effects as in the first batch. Reserve Parcel is a distinct new ID; the older Dead Drop keeps its separate ID and is refreshed below.

Examples: Uplink → Checksum → Ghost Key sets up Exposed; Downlink → Rebroadcast → Encore Buffer passes a signal while refunding Encore's RAM; Carrier Wave can place Relay on a leftmost Circuit Breaker for an immediate finisher. Pocket Compiler and Assembly Call give Chrome a release-then-refill pattern. Compilers always retain.

The new art atlas is `assets/cards/field_service_programs_wave2.webp`; mappings and generation provenance follow the first batch's conventions. Each of the fourteen cards has a unique illustration.


## Focused refresh of seven older cards

The audit found a few redundant effects, rather than a need to make the whole pool complex. Flux Wall, Soft Reboot, Defrag, Hotfix, and the starting cards stay straightforward. This refresh adds no cards and changes no existing IDs, rarities, costs, ownership, or art.

| Existing card | Previous role | New base behavior |
|---|---|---|
| Hydraulic Slam | 2 RAM, 11 damage | 10 damage; each unplayed end-turn discard charges +4, capped at +8; resets on play. Upgrade: 14 base. |
| Hard Reset | 2 RAM, 10 damage | 9 damage. After Script → Exploit this turn, strip the target's helpful statuses, then deal 5 more. Upgrade: 13 base +6. |
| Overwatch Protocol | Daemon +1 HP and 4 Firewall; close to Plate Up | Daemon +1 HP, 2 Firewall, Relay 2 on the leftmost other hand card, capped at 4. Upgrade: +2 HP and 3 immediate Firewall. |
| Dead Drop | Cache, draw 2 | Cache, draw 1, then plant 6 Firewall on the next draw-pile card. Upgrade: draw 2, plant 8. |
| Cold Storage | Cache, 7 Firewall | Cache, 2 Firewall; compile two other plays for +3 Firewall each, with Rootkits instead drawing 1. Upgrade: 3 base +4 per instruction. |
| Bone Saw | 9 damage and 2 Feedback | 10 damage; after Nerve Lash this turn, gain 4 Feedback. Upgrade: 14 damage and 5 conditional Feedback. |
| Nerve Lash | 6 damage and 1 Feedback | Keeps its existing effects; after Bone Saw this turn, also draw 1. Its existing numerical upgrade is preserved. |

Hydraulic Slam's installed damage mods still affect its base damage, never its charge step/cap. Dead Drop's payload is planted **after** its immediate draws, so it remains a future reward. Hard Reset's first hit occurs before the conditional strip, so enemy Feedback can still retaliate on that first hit.

The new wave-two card formerly named Heat Sink is now **Thermal Reservoir** (ID `heat_sink` stays stable). The original Heat Sink (`molten_shield`) is unchanged. A regression check now rejects duplicate displayed card names.
