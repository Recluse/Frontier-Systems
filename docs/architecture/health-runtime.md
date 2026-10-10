# Health scheduling and world recovery

## Implemented scope

[Localized injuries](localized-injuries.md) now add body-owned part damage and accumulated oxygen injury, composing their derived causes with retained sources. Health snapshots write v2 and migrate v1 without inventing wounds. The details below describe the original scheduling foundation; injury/treatment resource and physics adapters remain pending.

`HealthSimulationSystem` registers in `WorldRuntime` at priority 100, ahead of inventory priority 200. It owns one `ConsciousnessOwner` per current logical inventory body. Both default humans start alert. Wounds, finite drug quantities/metabolism, organ physiology and player-action enforcement remain pending; this is not finished knockout gameplay.

The registry is configured once and bounded to 64 bodies. World checkpoint validation requires exactly one health entry per current inventory body and rejects missing/orphaned entries. Future species applicability and body creation/removal need explicit lifecycle contracts.

## Trusted observations and scheduling

`queue_observation(body_id, causes, expected_revision, observed_tick)` is an internal trusted adapter API, not a player/script/LLM endpoint. It accepts one pending observation per body, with current source revision and precisely the next system tick. Causes are normalized bounded physiological observations, not chemical quantities. Queueing does not mutate consciousness; pending observations prevent checkpoint capture.

On the accepting fixed tick, fresh causes replace the source set and advance source revision. Stale queued observations discard with a failure counter. Sources persist until replaced, so finite chemistry must eventually derive updated observations through its own owner. Clients cannot declare their own recovery.

Updated bodies become due immediately, subject to a cap of **12 assessments per tick**. Initial due ticks spread across six phases by sorted body ID. Due work sorts by earliest tick, then stable ID; excess remains overdue and visible in diagnostics. Each attempted assessment reschedules six ticks later. A 64-body simultaneous observation burst may defer incapacity for some bodies; urgent injury/capability consequences require further integration before gameplay use.

At the default 60 Hz, six ticks is 0.1 second. Health snapshots declare the actual 60/72/90 Hz process timebase. Benchmark rate changes retain existing tick-based rules; this is not physiology retuning. Mid-session rate changes reject health advancement, observations and capture. Restore at another rate rejects until an explicit migration exists.

## Persistence and migration

The v1 snapshot stores timebase, exact last world tick, and each owner, source revision/causes and next assessment tick. Validation checks bounded fields, timebase/tick agreement, source consistency, unique identities, due scheduling, owner history and inventory links. Public observations and records are detached. Pending inputs and volatile counters are not saved.

World snapshots include `systems.health`; the outer envelope stays v1. Restore validates records/links before applying systems and preserves source state, recovery progress, receipts and assessment phases without replay. Legacy snapshots without health initialize unassessed alert owners for their existing inventory bodies, due after the saved tick. Worlds without inventory migrate empty inventory and health together. A present malformed health record rejects rather than resets. Migration creates no items, chemicals or historical injury records.

## Checks and next work

Bounded counters expose bodies, last assessments, overdue bodies, pending observations and failures. No service/file I/O or promise waits occur in ticks. Windows checks cover queued versus applied state, stale revision/tick rejection, pending checkpoint refusal, phases, sustained recovery, JSON continuation, invalid schedules/body links, migration, 64-body cap/backlog drainage, reconfiguration and timebase mismatch. Inventory, grip, control, XR and motion regressions passed; Windows/Linux CI includes the focused script.

The [inventory capability bridge](inventory-consciousness-capabilities.md) blocks unconscious actors and cancels inventory work/grips. [Localized injuries](localized-injuries.md) provide canonical damage and a v2 health snapshot. The [local health display](local-health-panel.md) exposes a scoped, read-only desktop projection. [Finite treatment planning](medical-treatment-planning.md) now produces paired injury and supply candidates; atomic inventory/runtime integration remains required before player treatment. Physiology, finite chemical exposure and binding combat, machine controls, desktop/VR and agents to authoritative bodies remain pending.
