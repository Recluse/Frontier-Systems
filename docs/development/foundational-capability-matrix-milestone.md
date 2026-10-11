# Foundational civilization/station capability baseline (v1)

## Milestone boundary

Documentation successor to merged PR #42 (`ca99cd40c66e22a09ef0352c4b875de3771905df`), based on integration commit `48b5baed38e0a1cbd8560e582e635697342ddaaf`. Research date: 2026-10-11 (America/New_York). Implements the first narrow research slice of [the owner's broad parity direction](civilization-station-capability-parity.md), preserving [later civilization progression](../design/civilization-to-space-progression.md).

The [machine-readable matrix](../research/foundational-capability-matrix.v1.csv) covers character control prerequisites, hands/inventory, ordinary item interactions and material construction/repair/salvage. It is neither an exhaustive Civ13/SS13 inventory nor a coverage denominator. SS13 references here mean the pinned /tg/station variant only. No percentage or full parity claim is justified.

This change adds no runtime behavior, schemas, dependencies or art. Integrated client layout, actual input/recovery testing, colonies, ships and rails remain separate work. This milestone does not approve their implementation or any merge, deployment or integration-branch push.

## Reading status and evidence

Each CSV row has a stable capability ID, matrix version, source keys, independently expressed action/outcome, owner, dependencies, status, inspected Frontier evidence, acceptance requirements, gap and decision state. Source keys resolve below; paths resolve relative to this repository. Semicolons delimit collections inside cells.

Use the parity plan's statuses: unresearched, planned, implementing, verified, exclusion proposed, exclusion owner-approved. Here **planned** means a sourced capability has a requirement and mapped owner, not that its remaining implementation is scheduled or approved. Existing slices can be implemented while the broader capability remains planned. **Unresearched** retains an owner requirement without attributing behavior to an unreviewed upstream subsystem.

Frontier evidence below is static inspection of contracts and test assertions at the baseline commit. Tests were not executed in this research change. Prior milestone reports are historical claims, not fresh verification. No row is marked verified: production authorization, integrated scenarios and fresh acceptance evidence remain necessary. A passed documentation check cannot promote runtime status. Future verified entries need immutable commit/check or artifact references and their platform, domain, transport, live-service and graphical scope.

## Pinned reference excerpts and rights

Civ13 revision: `0d38999d5f9f987a944493f11c456537f39ac2f6`. /tg/station revision: `ab176e0dfd1ee1a1a97e9546bad0b9c4e3ff78b1`. Read immutable Git object excerpts, not mutable working-tree contents. Scope selectors below identify inspected portions; a listed file does not imply full-file review. These seven reviewed paths are also recorded separately in [the reference manifest](../research/reference-manifest.csv).

| Key | Pinned reference and inspected scope | Observed behavior and independent lesson |
| --- | --- | --- |
| C1 | [Civ13 code/game/mob/inventory.dm](https://github.com/Civ13/Civ13/blob/0d38999d5f9f987a944493f11c456537f39ac2f6/code/game/mob/inventory.dm), first 200 lines | Active/inactive hands, guarded slot placement, storage insertion and drop entry point. Distinguish held, equipped and stored state; reject incompatible placement without losing the item. Drop side effects beyond this excerpt were not audited. |
| C2 | [Civ13 code/game/mob/living/carbon/human/inventory.dm](https://github.com/Civ13/Civ13/blob/0d38999d5f9f987a944493f11c456537f39ac2f6/code/game/mob/living/carbon/human/inventory.dm), u_equip entry and first 22 following lines | Removing an outer equipment prerequisite can release dependent carried bindings. Frontier needs an explicit dependency policy with conserved items; do not inherit slot names or implementation. Other human hand overrides were not reviewed. |
| C3 | [Civ13 code/game/objects/items/stacks/stack.dm](https://github.com/Civ13/Civ13/blob/0d38999d5f9f987a944493f11c456537f39ac2f6/code/game/objects/items/stacks/stack.dm), can_use/use and transfer_to declaration contexts, list_recipes contexts, Topic construction branch, produce_recipe first 100 lines | A carried stack exposes recipe selection; the request checks actor state, active hand and positive quantity. Early production branches contain location/context restrictions. Recipe completion, all costs and the large recipe catalog were not audited; no claim of universal conservation or epoch coverage. |
| C4 | [Civ13 code/game/objects/structures/repairing.dm](https://github.com/Civ13/Civ13/blob/0d38999d5f9f987a944493f11c456537f39ac2f6/code/game/objects/structures/repairing.dm), first 160 lines | Specialized benches accept selected gear classes; work can finish or interrupt and change condition. Independently require appropriate equipment and recoverable repair results. Upstream deletion at exhausted condition and durability tradeoffs are not adopted into Frontier. |
| T1 | [/tg/station code/modules/mob/inventory.dm](https://github.com/tgstation/tgstation/blob/ab176e0dfd1ee1a1a97e9546bad0b9c4e3ff78b1/code/modules/mob/inventory.dm), first 220 lines | Indexed held-item queries, active/inactive selection, hand availability hooks and held tool-quality queries. Explicit stable hand identities and derived capabilities are useful; this excerpt does not establish functioning anatomy, pickup or all species behavior. |
| T2 | [/tg/station code/_onclick/item_attack.dm](https://github.com/tgstation/tgstation/blob/ab176e0dfd1ee1a1a97e9546bad0b9c4e3ff78b1/code/_onclick/item_attack.dm), first 145 lines | Held-item activation and item-on-target dispatch distinguish handled/blocked ordinary interaction from further attack dispatch. Frontier needs explicit authorized interaction outcomes. Combat, signal handlers and individual object tool actions were not reviewed. |
| T3 | [/tg/station code/game/objects/items/stacks/stack.dm](https://github.com/tgstation/tgstation/blob/ab176e0dfd1ee1a1a97e9546bad0b9c4e3ff78b1/code/game/objects/items/stacks/stack.dm), ui_act and make_item first 90 following lines, intervening radial_check | Trusted recipe validation, finite positive quantity, builder checks, interrupted timed work, rechecking before completion and material attribution. Frontier should validate recipes/resources at authoritative completion with provenance. Helper internals and every recipe were not audited. |
| H1 | Owner's AGENTS.md architecture and docs/development/civilization-station-capability-parity.md; docs/design/civilization-to-space-progression.md, Frontier baseline commit above | Independent requirements for canonical body control, bounded fixed-tick commands, material conservation, repairable components and eventual broad gameplay. Not evidence of a particular upstream capability. |

Civ13 consultation is owner-authorized; the repository declares AGPL-3.0 and inherited/file-level ownership is unresolved. /tg/station consultation is narrowly authorized; its recorded code/license boundary is AGPL/GPL and assets CC BY-SA unless stated otherwise. Neither authorization establishes MIT redistribution permission. No upstream code, text, assets, balance values or dependencies are imported/adapted. These lessons are independently expressed requirements, not specifications transcribed from upstream.

Baystation source and source-derived excerpts were not accessed. No human Baystation requirement notes were supplied, so Baystation coverage remains unknown. Any proposed source/asset reuse still needs file-level clearance and explicit owner approval through Coordinator.

## Frontier owner and authority map

| Owner or boundary | Inspected contract and persistence/cadence | Practical limit |
| --- | --- | --- |
| InventorySimulationSystem / SharedInventoryCoordinator | src/core/inventory/inventory_simulation_system.gd (apply_local, grip guards); src/core/inventory/shared_inventory_coordinator.gd (apply_self); priority 200; inventory-system-state-v4 schema; retained owner receipts and body/equipment/storage links | Logical development-local bodies, registered storage and bounded revisioned transactions. Production inventory sessions, collision/occlusion and controller-change integration are separate. |
| PhysicalInteractionPolicy / inventory grip owner | src/core/locomotion/physical_interaction_policy.gd; docs/architecture/inventory-grip-runtime.md; inventory snapshot v4 and bounded grip counters | Pure availability assessment and logical hand reservations. No applied force, crate motion, physical ladder traversal or authoritative contacts. |
| LocalHabitatCharacter | docs/architecture/local-character-navigation.md; presentation fixed-frame physics; pose absent from canonical snapshot | Client preview character is not a production authority source or replicated player body. Navigation test scope is historical documentation, not fresh evidence here. |
| ToolSimulationSystem / ToolAssemblyLedger | src/core/tools/tool_simulation_system.gd (priority 250, prepare_repair, snapshot/profiling); docs/architecture/modular-tool-components.md; tool-system v1 | Component condition/provenance, energy-paid maintenance and bounded completed-work wear. Catalog/tool-specific implementation is not general anatomy, arbitrary repair or automatic program authority. |
| ProductionSimulationSystem with Inventory and Tools | src/core/production/production_simulation_system.gd (priority 300); docs/development/scratch-construction-milestone.md; current construction-coverage v2 | Current equipment/machine catalog routes and owner transactions. No general settlement bootstrap, all-world construction, sealed room topology or timed factory reservation contract. |

Profiling uses existing bounded inventory/job/grip, tool part/assembly and production resource counters. Future body and ordinary interaction owners need bounded counters and explicit persistence before implementation. Async service callbacks must enqueue validated commands; they cannot mutate these records.

## Small successor candidates

These are proposals pending Coordinator sequencing/approval; this document does not start them. Do not combine them into one parity PR or duplicate active integrated layout/input/recovery work.

| Candidate | Rows and dependency order | Bounded deliverable and acceptance gate |
| --- | --- | --- |
| FP-01: inventory authority design | foundation.character-control; foundation.hand-selection; foundation.equipment; foundation.storage; foundation.world-transfer | Design one principal/body/session binding and controller epoch contract around existing owners. Specify fixed-tick cadence, snapshot migration, revocation, duplicate receipts and counters. Gate: stale/foreign/controller-replaced intents cannot change ownership; do not trust preview transforms. Implement only in a later approved narrow change. |
| FP-02: ordinary interaction contract | foundation.object-use; after FP-01 | Define one ordinary action (activate an owned held tool on one registered work target), explicit handled/blocked/unavailable outcomes and server-derived reach/tool capabilities. Gate: wrong tool, occupied/reserved hand, stale target and duplicate command reject or replay without repeated work/cost; a blocked ordinary action does not implicitly authorize damage. |
| FP-03: equipment dependency transaction | foundation.equipment; foundation.storage; after FP-01 | One data-driven prerequisite and deterministic storage fallback for removing dependent equipment. Gate: full storage rejects atomically; valid removal conserves all nested possessions and bindings. Catalog choices require owner decision; no anatomy expansion. |
| FP-04: one timed construction job | foundation.recipe-build; foundation.staged-build; after FP-02 and explicit reservation design | One current trusted blueprint with finite material reservation and interrupt/resume/cancel semantics. Gate: competing work cannot double-spend; stale completion or restart cannot create another output. Do not replace existing atomic factories without a migration decision. |
| FP-05: one recovery chain | foundation.repair; foundation.component-replacement; foundation.salvage; after FP-02 | Add one missing combination scenario using existing component/production owners: damage disables one function, repair or replacement preserves old part, emptied shell recovers finite materials. Gate: payment/retry, foreign access, retained part provenance and occupied-container rejection. No broad gear catalog. |

Each runtime proposal must identify owner, tick cadence, versioned persistence, failure behavior and bounded profiling, and use versioned repository checks on Windows/Linux. Human usability and production multiplayer gates remain separate from domain tests. If a candidate overlaps active work, Coordinator should reconcile its evidence rather than create a duplicate milestone.

## Unknowns and exclusions

Anatomy, injuries/species, restraints, unconsciousness integration, arbitrary storage closures, throwing/combat, full material/recipe catalogs, zero-gear bootstrap and upstream deconstruction chains remain unresearched in this slice. Character movement is an owner requirement with only local prototype evidence; no upstream movement implementation was reviewed. Grip/force requirements derive from Frontier's own contracts, not a reviewed upstream pulling subsystem.

The broader taxonomy (food/agriculture, social/governance, hazards, infrastructure, logistics, civilization knowledge and space transition) remains intact and outside this bounded audit. No gameplay exclusion is proposed or owner-approved here. Missing reference review must remain visible, not be silently converted into an exclusion. Matrix decisions marked pending mean design/acceptance decisions remain with the owner through Coordinator.

## Documentation validation

Run tools/ci/check-foundational-capability-matrix.ps1 from the repository root. It checks v1 structure, stable unique IDs, statuses, required fields, source-key declarations, immutable source-manifest entries and local evidence/dependency paths. It does not execute gameplay or prove semantic parity. Also run git diff --check and inspect the outgoing docs/tool-only diff.

This research change deliberately skips runtime, live-service, graphical and actual input/recovery suites. Remote PR CI must be reported separately against the exact pushed head. Retain the managed worktree and remote feature branch for review; no merge/deployment is performed.
