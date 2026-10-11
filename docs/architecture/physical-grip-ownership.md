# Physical grip ownership

## Responsibility and boundary

`PhysicalGripOwner` is the domain owner for sustained grip intents and exclusive hand reservations. It composes `PhysicalInteractionPolicy`; it does not implement physics, authentication, construction detachment, inventory transitions or a registered `SimulationSystem`. Push-off is an impulse action and does not create a sustained grip session through this owner.

The future fixed-tick adapter must bind request bodies to authenticated controllers, derive actual target/contact/loadout observations and validate explicit consent for each joining body. It must recheck all participant authorization before recovery resume. These are trusted adapter obligations, not claims accepted from a player. No external service wait is required.

## Commands and atomic ownership

`join(request, observation)`, `release(request)` and `resume(request, observation)` take exact request fields: `request_id`, `session_id`, `body_id`, `expected_revision`. Requests use a stable request ID and compare-and-swap owner revision. New sessions start with one joining body; subsequent joins add only that body and preserve all prior participants and their ordered hand IDs. A target has one session, preventing competing owners from claiming it. A body can use distinct hands on distinct targets, but each hand has one reservation across the owner.

Join/resume accept insufficient force as a waiting condition; other capability, contact, target and grip-strength failures reject. `assess_session()` uses a complete fresh observation matching the registered target/action/participants/hands and returns unavailable while the group lacks force or the session is paused. A registry membership is not permission to move an object. Reassess immediately before force application each tick. Contact loss blocks assessment; automatic participant removal and disconnected-controller cleanup belong to the future runtime adapter. They are not implemented here.

For this owner's observation, `free_hand_ids` means the hands available **for this session**: genuinely unused joining hands, or existing hands already reserved by this same session. An adapter must reject occupied inventory hands, disabled hands and reservations held by other sessions. Observation force is the trusted aligned total for each body's listed hands. Existing participants cannot be replaced or given different hands by another member's join.

Release removes only the request body's participation and hand reservations; it does not require contact, strength or a breathable environment. Last release removes the target session. A candidate record validates completely before replacing state, so failed joins/releases cannot partially reserve hands or advance revisions. Domain methods return detached receipts rather than mutable internal records.

Successful receipts retain the last 128 request IDs, intent fingerprints and committed revisions. Same retained intent acknowledges without another mutation; changed intent rejects. Fingerprints include owner, operation, request/session/body IDs and original revision; join additionally includes target/action/ordered joining hands. Live contact/force values are observations rather than persistent request intent. Retry acknowledgement never applies force or renews an interaction. Evicted receipts offer no indefinite retry guarantee; stale revisions still reject.

## Persistence and recovery

The v1 owner record contains `schema_version`, `owner_id`, `state_revision`, `sessions` and `receipts`. Sessions contain `session_id`, `target_id`, `action`, `paused` and participants with `body_id`/`hand_ids`. Force budgets, contact flags and physics constraints are not persisted by this owner. Limits are 32 sessions, 16 participants/session, eight reserved hands/participant and 128 receipts. Traversal (`grab`/`pull_along`) remains a single-body session; `move_world_object` permits cooperation.

`from_record()` validates identities, duplicate targets/bodies/hands, ordered receipt revisions, fingerprint format, counts and exact integer bounds. JSON integer-valued floats normalize for revisions. Restore defaults to pausing every session while retaining reservations, preventing inventory use from silently occupying saved grip hands. A member may release without resume. Explicit resume needs fresh full-session observations and adapter authorization. An old retained resume receipt can be acknowledged after another restore but leaves the restored session paused; a new request/revision is required to resume it again. The `pause_on_restore: false` option is for trusted construction/commit validation, not public snapshot restore.

World/body physics owners remain responsible for object identity, contents and canonical motion. Grip records reference targets without cloning them into inventory. The [local inventory grip runtime](inventory-grip-runtime.md) now saves this owner in inventory-system snapshot v4 and arbitrates equipment slots through queued development commands. Its logical fixture targets do not yet have rigid bodies; real-object pickup/grip release coordination and authenticated production controls remain pending.

## Profiling and verification

`profiling_counters()` reports bounded session, participant, reserved-hand, paused-session and retained-receipt counts without mutating behavior. A future simulation wrapper can expose these through existing tick profiling.

Windows headless import and `physical_grip_owner_test.gd` cover cooperative waiting/joining, exclusive reservations, changed/stale retry rejection, fresh contact assessment, paused JSON recovery/resume, participant-only release, final target cleanup, malformed snapshots, detached records, bounded receipt eviction and revision exhaustion. The focused script is included in Windows/Ubuntu CI. Linux execution, remote CI, authenticated runtime commands and physical forces remain pending.

## Trusted controller lifecycle preparation

`prepare_controller_invalidation(body_id)` returns a detached validated grip owner for the canonical runtime's synchronous epoch transaction. It does not publish, invoke callbacks or create player receipts. It removes only the named body's participants/hand reservations, removes empty sessions, preserves surviving paused flags and other bodies, and increments the owner revision once if membership changed. Required revision exhaustion rejects without mutation. A caller must install the candidate only after its canonical comparison and all validation succeed. The inventory runtime owns this bounded multi-owner composition; no player or UI supplies the body identity or candidate. Physical targets and inventory matter are never changed by grip invalidation. See [controller lifecycle invalidation](../development/inventory-controller-lifecycle-invalidation-milestone.md).
