# Consciousness ownership and assessment receipts

## Domain owner

Update: the owner now composes into [world health scheduling](health-runtime.md). Injury/chemical sources and action enforcement remain pending. The [history optimization](../../reports/performance/owner-optimization.md) uses incremental commit construction and disposable indexes; creation/load retain exhaustive checks.

`ConsciousnessOwner` under `src/core/health/` owns one body's validated consciousness record and the last 64 successful assessment receipts. It commits the [pure consciousness policy](consciousness-foundation.md) atomically. New owners start alert and unassessed; body identity is fixed for their lifetime. It is composed inside the registered health system, not exposed as an authenticated player endpoint or a source of injuries/chemicals.

The health system composes one owner per current body. Future physiology/exposure must derive the complete causes, verify body/life applicability and enforce capabilities after transitions. Matching tick/revision values do not prove caller authorization. Players, scripts and LLMs must not call this API with invented causes.

## Atomic assessment

`assess(request, commit_tick)` accepts an exact v1 record: request ID, body ID, expected state revision, observed tick and complete cause set. New effects require current revision and a strictly newer observation tick equal to the commit tick. It validates causes/new policy state, constructs one receipt and bounded tail, then commits state and updates the disposable index. Previously validated history is not decoded again. Failed checks preserve canonical state/receipts. Each assessment advances revision once, even without a consciousness transition.

The SHA-256 fingerprint covers request/body identity, expected revision, observed tick and normalized cause records sorted by ID. Equivalent cause ordering and integer-valued JSON floats produce the same fingerprint. These are idempotency identifiers, not cryptographic signatures or authenticity proofs.

A retained identical request returns its original receipt without requiring the old observation to become fresh again. It does not rewind state, restart recovery, apply suppression again or execute transition consequences. Reusing a retained ID with changed content fails. Callers must distinguish acknowledgement of an old assessment from a new transition by receipt revision and their own consumed-event records; do not trigger grip release or other effects just because `transitioned` is true in a retried historical receipt.

After eviction an old request's old revision/tick reject replay. Request IDs should remain unique for the body/session lifetime; bounded retention does not guarantee detection of all historical ID reuse if a caller deliberately supplies entirely new current content under an evicted ID. Future command wrappers must specify their own identity and receipt scope.

## Persistence validation

The owner v1 record contains schema version, consciousness state and receipts. Each receipt stores request ID, fingerprint, resulting revision, commit tick, resulting consciousness state and transition flag. Restore checks:

- Exactly `min(state_revision, 64)` receipts, with no revision gaps or duplicate request IDs.
- Strictly increasing assessment ticks, valid SHA-256 syntax and bounded fields.
- State transitions consistent with consecutive retained receipts, and the latest receipt matching canonical state/tick.
- Last transition consistent with the visible receipt history; older transitions can precede the retained window.
- The optional snapshot tick is not behind the latest assessment.
- Revision zero means the exact unassessed alert starting state.

Recovery start, causes and transition history survive detached JSON round trips. Restore replays no assessments. Cause/policy consistency is checked by `ConsciousnessState`; receipts are not a full audit log or sufficient evidence to reconstruct past injury/chemical inputs. Health-system world snapshot registration and secure durable persistence remain future work.

## Diagnostics and verification

`profiling_counters()` exposes total committed assessments from the saved state revision, active causes, retained receipt count and volatile rejection/retry/transition counters. Volatile counters reset on load and cap at one billion; they are excluded from canonical snapshots. Queries and receipt returns are detached. No external I/O, ReactPHP service call or promise wait occurs in the owner.

Windows import and `consciousness_owner_test.gd` passed. Checks include atomic knockout, failed mutation isolation, normalized retry content, changed request rejection, body binding, stale revisions/ticks, observation freshness, detached observations, saved recovery completion, historical retry without rewind, corrupt/omitted receipts, snapshot future-state rejection, bounded eviction, transition history and diagnostics. CI includes the owner script on Windows/Linux; Linux execution has not been verified locally.

Next add canonical injury/chemical sources and idempotent capability-transition consequences to the registered health system. Live body control, VR pose suppression, inventory/grip cancellation, sedation and beneficial medicine remain pending.
