# Localized injury foundation

## Implemented scope

`BodyInjuryState` now composes into each current health body. It tracks six prototype human parts (head, torso, left/right arms and legs), blunt/burn severity per part and accumulated oxygen injury. Stable anatomy is a bounded initial human fixture, not yet a data-driven species/organ catalog. Future cyborg/species physiology must supply explicit compatible definitions rather than assuming these parts universally.

Canonical severities are fictional integer permille 0..1000. They are not impact energy, damage-per-second or real physiology. There is no single total health bar or automatic death/destruction. Limb and burn injury are recorded, but do not yet model pain, bleeding, broken bones or disabled hands.

## Plans and fixed-tick application

`plan_change(operation, part_id, kind, amount, tick)` returns detached before/after records. `damage` adds bounded severity, `heal` removes it, clamped to actual available capacity/injury; the plan reports the actual planned change. It requires a newer mutation tick and revision capacity. Target is a registered part with blunt/burn kind, or `systemic`/`oxygen`. Multiple operations for the same body at one tick need a future batch transaction; this prototype permits one queued change per body/tick.

`HealthSimulationSystem.queue_injury_change()` is an internal trusted adapter API with current injury revision and precisely the next tick. It admits a plan without changing saved anatomy. Pending changes prevent partial checkpoints and are applied only on the accepting tick; skipped/stale changes discard with diagnostics. Old revisions cannot replay a committed injury/treatment. There is no retained injury-specific retry acknowledgement yet; callers must inspect current state after an uncertain outcome rather than submit it as a new operation.

This API is not a player/LLM damage or free-healing endpoint. Future physical contact policy must derive injury from authoritative impacts/armor. Treatment adapters must validate patient access, tools and consume finite medicine/resources atomically; these are not implemented by a severity delta. Existing command ordering and bounded assessment deferral still apply.

## Consciousness and basic gameplay

Head blunt severity maps to an injury-owned suppression cause; accumulated oxygen injury maps to another. These combine with existing trusted source causes through the current consciousness policy. Reserved IDs `anatomy.head-trauma` and `anatomy.oxygen-injury` cannot be supplied externally. The combined set remains bounded to sixteen; admission rejects over-capacity plans/observations without partial state changes. A saturated external source set may need reduction by its trusted producer before an anatomy contribution can fit; never silently drop a cause.

This is a provisional head/oxygen effect mapping, not organ simulation. Healing head trauma cannot remove sedation; reducing oxygen injury cannot repair breathing or supply gas. Continued physiological oxygen deprivation must eventually add new injury through a separate breathing/circulation adapter. Consciousness recovery still requires all remaining causes to allow it for the configured safe interval.

Injury-driven unconsciousness now reaches the existing inventory capability bridge: actor actions reject, unfinished work/grips stop, and passive-target interactions remain available. Physical capsule/VR movement and airlock development identities still require canonical body binding. No claim of completed combat or medical gameplay is made.

## Persistence and migration

Health snapshots now write v2, including a separate versioned injury record per body. Validation checks exact parts/kinds, finite bounded integers, body identity, mutation tick not ahead of the snapshot, latest consciousness/source consistency and immediate due scheduling for changed injuries not yet assessed. Injury revision zero must be healthy and unmutated. Source revisions and injury revisions are independent.

V1 health snapshots migrate with zero anatomy damage, preserving their preexisting source causes, consciousness state and recovery; no old suppression is guessed into a particular wound. Sources using newly reserved anatomy IDs reject explicitly rather than being reinterpreted. Snapshots missing health retain the existing initialization policy. The outer world envelope remains v1; its schema permits health v1/v2.

Fixture: `data/health/injury.default.v1.json`. Schemas: body injury v1 and health system v2. Owner/injury observations are detached, and no chemical quantities or transient queued operations are written to saves.

## Verification and next work

Windows import and `body_injury_runtime_test.gd` cover localized pure plans, bounded healing, invalid anatomy/numbers, immutable inputs, queued versus committed damage, duplicate/stale revision rejection, injury-driven inventory incapacity, JSON restoration, persistent sedation after head healing, safe recovery, independent oxygen injury and v1 migration. CI includes the test on Windows/Linux.

Next implement a basic damage/treatment command boundary with authenticated body binding and finite treatment resources, player health observations/feedback, breathing-generated injury and physical contact sources. Species anatomy, organs, bleed/pain and advanced medicine remain later layers. Away missions and Twitch features remain separate from this gameplay work.
