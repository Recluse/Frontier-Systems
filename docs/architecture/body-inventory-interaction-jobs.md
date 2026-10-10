# Timed body inventory interaction jobs

## Implemented domain state

`BodyInventoryInteractionJob` implements fixed-tick timing and interruption checks for the [other-body inventory design](../design/other-body-inventory-interactions.md). It is a detached `RefCounted` domain object, not yet a registered simulation system or multiplayer command handler. It does not reveal contents, change ownership or equip an item.

The v1 job pins its policy, actor/target body IDs, action, target container and applicable item/slot, actor control epoch, target action epoch, both inventory revisions, last processed tick, progress, state and cancellation code. Search has no item or slot; other actions require an item, and equipment actions additionally require a slot. Bodies must be distinct. IDs, counters and state relationships are validated before accepting records.

The default fixture describes a take attempt against the prototype pouch's crowbar. It is not loaded by bootstrap. Actual source/destination access and the relation of its targets to the bodies must be established by the future authoritative inventory owner.

## Lifecycle

| API | Behavior |
| --- | --- |
| `start(record, policy, observation)` | Accept only an active, zero-progress job and passing physical policy conditions |
| `advance(tick, context, observation)` | Require exactly the next fixed tick and revalidate counters/physical conditions before adding one progress tick |
| `completion_candidate(tick, context, observation)` | Return detached readiness data only in the same tick readiness was reached, after another fresh validation |
| `from_record(record, policy)` | Validate recovery data and pause every unfinished job, including a previously ready one |
| `resume(tick, context, observation)` | Revalidate original counters and physical conditions at the current tick; require a new validated tick before restored readiness |
| `cancel()` | Mark cancellation without overwriting an existing cancellation reason |

States are `active`, `ready`, `paused` and `cancelled`. Cancelled state is terminal and remains cancelled after restore. Duplicate or skipped ticks reject without progress; they never fast-forward using elapsed time. Other failed preconditions cancel the job with a bounded reason code. New jobs cannot start at the exhausted tick bound.

Readiness occurs exactly at the pinned action duration. Restore preserves partial progress and original counters but pauses execution; it awards no offline progress. A previously ready restored job is reduced to duration minus one upon successful resume, requiring one freshly validated tick. Resume must not move the tick backward or replace old epochs/revisions with current values.

## Action epochs and completion ordering

Each advance/completion assessment requires an exact server-created context containing actor control epoch, target action epoch, actor inventory revision and target inventory revision. Any mismatch cancels. This conservatively cancels on any relevant inventory change, rather than trying to continue against a changed container.

The future body/action owner must increment target action epoch for resistance and deliberate movement even if those states are no longer asserted when the interaction system samples them. Actor control epoch identifies changes such as body control/session handoff. These counters are structural inputs here; no body/action epoch producer or authenticated resistance handler exists yet.

Process movement/resistance commands and corresponding epoch updates before job advancement and completion in a tick. Recheck at completion so a same-tick change after readiness invalidates the candidate. An observation of passivity cannot override a changed action epoch. Passing observations must also attest target availability, actor manipulation, reach and accessible path under the existing policy.

## Authority and atomic handoff

A completion candidate is not a reusable access token. It must be consumed by the sole inventory coordinator in that exact tick, after verifying authenticated actor/body binding, target/item/container relations, destination capacity, slot compatibility and any required scoped search observation. The job does not implement these checks or bind network principals itself.

Commit the operation's inventory/equipment/search-view changes together with an idempotent receipt keyed by job/request ID. Remove the ready job from the active collection only as part of that commit. Re-reading a candidate must not cause duplicate transfers or search grants. A later-tick candidate rejects; the owner must discard/cancel such an unconsumed job or use explicit paused recovery rather than pretending the old candidate is current.

The [shared inventory coordinator](shared-inventory-transactions.md) now provides an atomic transfer/equipment/receipt boundary and a completion bridge that matches job targets and actual body revisions. Production ownership must still bound concurrent jobs, reserve conflicting work where appropriate and persist jobs with affected owners. Collection/admission rules and durable receipt persistence remain pending. No service I/O or asynchronous wait appears in this class; external callbacks must enter through validated simulation commands.

## Schema, checks and remaining work

`docs/schema/body-inventory-interaction-job-v1.schema.json` specifies the exact record shape and action-specific identifiers. Policy lookup, distinct bodies, progress/duration/tick agreement and state invariants are checked by GDScript. Public snapshots are detached.

Windows Godot 4.7.2 import, `body_inventory_interaction_job_test.gd` and existing policy checks passed locally. Tests cover exact timing, duplicate/skipped ticks, same-tick interruption, epoch/revision changes, fresh completion, later-tick rejection, ready/partial restore, explicit resume, original-epoch preservation, terminal cancellation, invalid targets/progress/policy and detached records. Windows/Ubuntu CI includes the script; Linux execution is not locally verified.

Next: authoritative body/action registry and bounded job system, typed resistance/start/cancel commands, shared inventory coordinator and atomic completion receipts, then scoped search views and target-body UI. The game still has no runtime pickpocket/search or multi-body transfer feature.
