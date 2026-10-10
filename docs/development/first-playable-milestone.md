# First playable: mining, refining and recycling

## Milestone status

**Reached as a cooperative Windows source prototype on 2026-10-10.** The owner confirmed cooperative multiplayer and restart persistence as requirements. The community selected mining, refining and recycling, with Take On Mars-style extraction and containers first. See [launch instructions](first-playable-running.md), [acceptance evidence](first-playable-acceptance.md) and [agent handoff](FIRST_PLAYABLE_HANDOFF.md).

This status applies to the bounded development build. A packaged public or Steam release needs additional distribution, identity, deployment and usability work.

## Player loop

Find a deposit → extract into a canister → carry to a workstation → unload → refine useful material and waste → print/collect a physical plate → recycle → print again.

| Requirement | Implemented and verified |
| --- | --- |
| Extraction | Finite sites, owned canister, reach/power/energy checks and depletion |
| Handling | Actual shell + payload mass, physical pickup/drop, transport and scoped inventory |
| Refining | Trusted recipes, reserved timed batches, finite energy, explicit outputs/byproducts |
| Craft/recycle | Stable physical plate, inventory transaction, recovered iron reused for printing |
| Guidance | Seven-stage session guide with readable actions; graphical route completes |
| Cooperation | Two authenticated clients, shared host state, revision contention and private cargo |
| Restart | Worker checkpoints, validated startup restore, active batch continuation and retained retry |

## Acceptance and limitations

Automated Windows acceptance checks the complete route, simultaneous extraction, unauthorized cargo, full-container rejection, missing-input/power rejection, outage pause and cancellation recovery, physical-item restore, corrupt alternate save fallback and restarted batch completion without duplication. Graphical checks drive the same controls with local movement. This does not replace human usability review or broad stress testing.

Two invite slots and periodic/manual checkpoints are the current operational model. Detailed collision authority, Steam identity, Linux execution evidence, standalone exports and public TLS deployment remain pending. The legacy lab includes wider experiments that are not all exposed in the cooperative client.

## Next milestones

First collect two-player feedback and measure the active route. Add sustained hand-tool extraction and craftable carriers, then Space Station 13-style terrain excavation through material/chunk transactions. Improve transport movement authority, persistence guarantees and distribution readiness as audience grows.

[Planet-start civilization progression](../design/civilization-to-space-progression.md), informed by the owner's Civ13 reference, is a later update. Full chemistry/medicine, atmospheric survival, modular colonies/ships, procedural planets, away missions, platform chat/voice, LLM automation and broad roleplay remain long-term work. Optional VR is not required for this first playable route.
