# Atomic linear motion ownership

## Domain responsibility

`LinearMotionOwner` is the sole domain owner of up to 64 registered `LinearMotionState` records and a bounded paired-impulse history. It creates its initial registry from trusted motion records, such as the existing push-off fixture. It is a `RefCounted` domain component, not a registered `SimulationSystem` or a player transport endpoint. No body/assembly registration, retirement, mass changes, frame changes, gravity updates or position integration occur after creation in this version.

`push_off()` accepts a v1 impulse intent, trusted contact record, observation tick and commit tick. A future fixed-tick adapter must authenticate/bind the actor, resolve the target's backing assembly, derive collision contact/duration/normal, consult hand reservations and account for work/stamina/actuator budgets. The domain cannot establish those facts from a tick number alone. It must never receive client-supplied capability/contact authority or an asynchronous callback's stale collision observation.

## Atomic commit and freshness

Intent fields are `schema_version`, `request_id`, actor/target body IDs, expected owner/actor/target revisions and the integer impulse vector. The owner finds both canonical states; it never accepts caller-provided after-records. New effects require distinct registered identities, current revisions, an unexhausted owner revision and an observation tick equal to the commit tick. Commit ticks start at one and cannot decrease relative to committed history. Multiple effects may occur in one tick if they use successive fresh revisions; the future adapter must additionally enforce per-hand contact-duration and resource budgets across them.

The owner asks `PushOffImpulsePlanner` to revalidate the actual current records and trusted contact. It constructs both after-records, the owner revision/tick and a receipt in a detached candidate. Full candidate validation succeeds before one replacement of canonical state. If either body exceeds a momentum/speed/revision limit, or any contact/effort check fails, neither body changes and no successful receipt is retained. Failures may increment only a bounded volatile diagnostic counter.

This is synchronous bounded domain work intended for the simulation command phase. It performs no I/O, waits or external-service calls. External player/script/LLM requests must enter the ordinary queued command/capability path, and the adapter must derive fresh contact when applying that command.

## Retry receipts

The owner retains the latest 128 successful request IDs, SHA-256 intent fingerprints, actor/target IDs, resulting owner/body revisions and commit tick. Fingerprints include owner identity, request ID, both bodies, all expected revisions and normalized impulse components. Contact flags, normals, duration and tick parameters are fresh server observations rather than persistent request intent.

An identical retained request returns the original detached receipt without reapplying momentum, advancing revisions or requiring present contact. A changed request using a retained ID rejects. The hosting adapter must still authenticate every caller, including receipt retries. A receipt acknowledges a historical effect; it grants no fresh contact authority or future movement. An evicted request has no indefinite acknowledgement guarantee, and its old expected revisions prevent replay as a new effect.

## Saved state and validation

Owner v1 contains schema version, owner ID, state revision, last commit tick, motion states and receipts. Body identities are unique. Motion records and all canonical integer/version fields normalize on JSON decoding. Observations are detached, and `state_observation(body_id)` exposes one registered state to a trusted caller without granting access to any network principal.

Restore validates every motion state and receipt before creating the owner. The receipt window must contain exactly `min(owner_revision,128)` entries with consecutive tail owner revisions and nondecreasing ticks. Referenced bodies must exist, remain distinct and share a frame. Retained body revisions advance once per affected impulse and their latest receipts match canonical body revisions. The final receipt matches the owner's revision and last commit tick. Duplicate IDs, malformed fingerprints, missing tail receipts, future body revisions and invalid numeric/count bounds reject. These are structural/history consistency checks, not a cryptographic guarantee against malicious saved-state editing.

`from_record(record, snapshot_tick)` optionally rejects a saved commit ahead of the containing world tick. Hosting snapshot restore must supply that tick. Restore loads the already committed momentum/history; it never replays contact or an impulse. Momentum persists, while old physical contacts do not become fresh observations. The owner is not yet included in `WorldSnapshot`, so this API does not currently change the local character or inventory save format.

The current receipt contract assumes push-off is the only owner mutation. Gravity, collisions, mass transfers and frame/body lifecycle changes require an explicit extension of mutation/receipt contracts rather than editing these records behind the owner.

## Profiling, schemas and verification

`profiling_counters()` reports registered state count, retained receipt count, committed impulse count (owner revision), and bounded volatile rejection/retry acknowledgement counters. Volatile diagnostics reset on recovery and are excluded from canonical saved state. A future simulation wrapper exposes them through existing tick profiling; no runtime wrapper exists yet.

Schemas: `linear-motion-owner-v1.schema.json` and `push-off-motion-intent-v1.schema.json`, composed with the existing motion/contact contracts. Runtime validation adds cross-record and receipt-window invariants beyond JSON Schema.

Windows headless editor import and `linear_motion_owner_test.gd` passed. Checks cover paired commits, independent revision guards, same-tick contact, unchanged state on failure, normalized retained retries, lost contact, JSON recovery without replay, monotonic ticks, detached observations, malformed records, one-sided overflow rejection, bounded eviction and exhausted revisions. Recovery checks repaired schema-version normalization in motion/owner records. The focused script is included in Windows/Ubuntu CI; Linux/remote CI, collision/energy integration, live world registration and player controls remain pending.

## Next integration

1. Add work/stamina accounting and real body/assembly registration with explicit lifecycle and mass/shape ownership.
2. Wrap motion in a fixed-tick simulation system with world snapshot/link validation and authenticated queued intent binding.
3. Derive collision contacts and effective intervals, enforce shared hand/resource budgets, and extend angular momentum for off-center pushes.
4. Feed canonical momentum into body/assembly physics and presentation while preserving drift and equal opposite reaction. Then connect player controls and grip constraints.
