# FP-01: inventory controller authority design (proposal v1)

## Boundary and evidence

Design-only successor to merged foundational matrix PR #44, inspected at `f43cbaeb3c70a83ddcc8a5f14e8f482ffb40ae67` on 2026-10-11 (America/New_York). Implements the design deliverable proposed as [FP-01](foundational-capability-matrix-milestone.md), covering `foundation.character-control`, `foundation.hand-selection`, `foundation.equipment`, `foundation.storage` and `foundation.world-transfer`. Those capabilities remain planned; this document establishes no verified gameplay or parity claim.

All contracts below marked proposed require a later approved implementation. No runtime, schema, configuration, dependency, artwork or upstream research changes accompany this document. UI, input capture, world picking, movement prediction and active integrated-client work are outside scope. Approval and sequencing remain with Coordinator; this draft authorizes no merge or deployment.

### Current contracts inspected

Paths below are repository-relative and refer to the baseline commit, not a claim that tests ran here.

| Contract | Actual behavior and limit |
| --- | --- |
| `src/core/simulation/authenticated_command_context.gd` | Trusted server-local principal/session/world/region and grants; never accepted as a client record. `is_valid_for` checks identities and region, not live session membership or control epoch. |
| `src/adapters/network/first_playable_host.gd` | Invite slots map to fixture principals; host constructs peer-specific sessions and permits one connected peer per slot. Disconnect removes reply routing, not queued simulation commands. This is an existing development transport, not a production identity service. |
| `src/core/inventory/inventory_development_command.gd` | Validates inventory authorization and delegates application at the world tick. No controller token is pinned by this command. |
| `src/core/inventory/inventory_simulation_system.gd` | `authorize` accepts debug local grants or authenticated `inventory.operate`, then finds a fixture principal/body. `apply_local` requires next tick, derives actor ID and checks logical reach/access/health/grip. Body records contain principal, control/action epochs and integer millimetre position; control epochs initialize to zero. Priority 200. |
| `src/core/inventory/shared_inventory_coordinator.gd` | Owns ledger/equipment/container transactions; `apply_self` and `apply_world` fingerprint intent and replay matching retained IDs before revision comparison. Retains at most 128 receipts. Body IDs here are internal owner inputs, not authentication. |
| `src/core/simulation/simulation_runner.gd` | Bounded queue; commands apply at tick start before system progress. Snapshot rejects pending commands and validates all systems before restoration. Existing defaults: 256 commands per tick, 8192 queued. |
| `src/core/inventory/inventory_simulation_system.gd` snapshot decoder | Emits inventory v4 with grips; reads v1-v4, migrates axis positions and pauses recovered jobs. Existing limits include 32 bodies/jobs and exact epochs up to 9007199254740990. Schema: `docs/schema/inventory-system-state-v4.schema.json`. |
| `docs/architecture/inventory-spatial-state.md`; `docs/architecture/local-character-navigation.md` | Preview capsule is presentation state. Opt-in debug bridge queues logical `move_to`; its sampled preview position is not a production reach authority. |
| `tests/godot/inventory_runtime_test.gd` | Assertions cover interrupted work without receipts, transfer/receipt checkpoint, paused recovery and atomic invalid epoch restore. Static inspection only; no fresh execution. |

Older inventory-runtime/spatial prose describes v3 or debug-only authorization. Current code and v4 schema take precedence for this baseline. That documentation drift must not be used to assert that authenticated fixture access is absent, or that controller binding already exists. FP-01 adds a proposal, not a retrofit of historical verification claims.

## Proposed owner and binding

Add a server-owned `InventoryControllerAuthority` composed into `InventorySimulationSystem`. Keep `SharedInventoryCoordinator` as the sole inventory mutation owner. Authority controls permission to submit an internal owner transaction; it owns no item quantities or equipment copies. A future separate body/identity owner can implement this interface without moving inventory state into UI.

A durable binding contains world/region, stable principal ID, existing body ID, monotonically increasing `control_epoch` and current-epoch terminal command high-water number. Runtime-only state contains the active authenticated session ID and liveness. One active session per body and one inventory body per principal within this region match the present decoder. Multi-body control, spectators and cross-region transfer require separate designs.

The inventory body metadata's existing `control_epoch` is the single epoch value, not a second drifting counter. Authority indexes it; candidate validation requires body/root agreement with the shared owner and exact principal/body/epoch agreement with runtime body metadata. Bind, replace and revoke are trusted lifecycle commands, never player inventory payloads. Each transition increments that body's epoch once, clears its current-epoch high-water, and replaces or removes the active session. At exact-integer exhaustion fail closed without wraparound or partial changes. A principal change requires an explicit trusted reassignment transaction; a client cannot select a foreign actor.

At ingress, derive principal/session/grants from the authenticated connection. Validate world/region, current liveness and permission; pin body and epoch from authority into an immutable server-only command token. Client intent may echo an expected epoch to detect an obsolete view but cannot establish it. Recheck the token, current grant and world/region against live authority at application and before any deferred job completion. Possession of an old `AuthenticatedCommandContext` is insufficient.

Debug local operation uses an explicit fixture binding in debug worlds. The preview pose bridge retains its opt-in debug boundary. Production requests cannot acquire debug grants or route through that bridge.

## Fixed-tick ordering and canonical reach

Lifecycle callbacks enqueue bounded events; they never mutate canonical records. A transport disconnect immediately stops further admission for that connection. At the next tick, process admitted lifecycle revocation/replacement events before inventory intents and job progress, regardless of network callback arrival order within the preceding interval. This requires an explicit bounded lifecycle lane or tick-start phase; ordinary FIFO alone is insufficient. Reserve capacity for revocation; if admission cannot be maintained, suspend inventory execution until reconciliation rather than dropping revocations. A disconnect observed after a tick finishes takes effect at the next boundary and cannot undo committed work.

For a new inventory operation: validate envelope bounds, apply lifecycle changes, authenticate pinned token, check retry state, validate expected inventory revision and capabilities, derive spatial access, then commit the existing owner candidate and authority receipt/high-water together. Failed authorization never calls the owner. Two competing commands with the same revision execute in deterministic admitted order; only the first valid mutation succeeds.

Reach uses canonical body and registered target records at the application tick. Keep current integer millimetres, bounded coordinates and conservative rounded-up distance through `InventorySpatialMath`; current world-container threshold is 1500 mm. A future pose provider must identify body/world/region and a tick-consistent canonical record, validated by the simulation movement owner. Missing or wrong-region pose fails closed. Client camera, screen ray, Node3D transform, claimed distance/access/tool tags and preview collision proxies supply no authority.

Current logical positions provide fixture reach only; this proposal does not establish server collision, occlusion or anatomy. Before enabling physical production pickup, a later spatial owner must define and verify those gates. Self hand selection needs no target pose; owned container ancestry and equipment/grip/health checks remain with existing owners.

On replacement/revocation, invalidate actor jobs and scoped search views using the retired epoch. A paused old job cannot silently rebind to a new controller. An explicit resume under the new binding revalidates all existing job guards and pins the new actor epoch, preserving remaining work and item conservation. Release the retired controller's logical grip reservations through their owner at this boundary; do not delete held items or force a drop. These are required integrations before expanding beyond the first self-operation slice.

## Retry and receipt contract (proposed v1)

Use a bounded positive `command_number` increasing within a controller epoch, alongside stable `request_id`. Permit one outstanding new inventory command per binding in the first implementation; reject gaps as `sequence_gap` without advancing high-water. A retry repeats number, ID and exact normalized intent. Server receipt key is world/region/principal/body/epoch/number; fingerprint additionally covers request ID, operation, exact payload and expected inventory revision. Do not rely on transport reply-route keys as mutation deduplication.

Authenticate the current session/token before reading receipts. Matching retained terminal receipt returns the original outcome and commit tick without reapplying the owner, rechecking current reach or charging work again. Changed intent at a retained key returns `intent_conflict`. Number at or below high-water with evicted detail returns `receipt_expired`; it never executes again. New valid sequence advances high-water for success and authorized terminal domain rejection. Malformed, unauthorized and gap requests do not consume sequence. Saturated counters reject without wraparound. No automatic retry with a fresh number after an uncertain response.

Keep at most 128 terminal receipts region-wide, evict oldest deterministically, and retain high-water per bounded binding. Allocate unique bounded internal owner request IDs from the authority key so identical external IDs from different principals/epochs cannot collide with existing owner-global receipts. Version the encoding and verify its injectivity; do not silently change existing owner fingerprints. Owner candidate, authority receipt and high-water must commit as one prevalidated in-memory transaction and one world checkpoint, with no fallible second mutation after owner commit.

Retired epoch commands return `controller_replaced` or `session_revoked`, including old completed-command retries. A separately scoped status query under a freshly authenticated current binding may disclose retained outcomes for the same principal/body and retired epoch; it cannot execute that intent. Unknown/expired status requires canonical revision reconciliation and explicit user intent, not inferred success or resubmission.

This is bounded deduplication within checkpoint lineage, not crash-proof exactly-once delivery. Acknowledgements distinguish `applied` from `checkpointed`. Loss before a durable checkpoint can roll back applied state and receipts together; reconnect reconciles the restored revision. Durable retry guarantees require the existing persistence adapter's successful checkpoint evidence. Do not promise survival of uncheckpointed effects.

## Persistence and migration proposal

Reserve an inventory snapshot v5 proposal containing nested authority record v1 and authority receipt record v1; do not modify schemas in this PR. Persist binding IDs, existing control epochs, high-water and terminal receipts alongside v4 owner/jobs/storage/grips. Do not persist bearer credentials, live sockets, active session IDs, admission queues, preview pose, views or diagnostic history. Keep authority collections bounded by the existing 32-body and 128-receipt limits. Exact fields, integer bounds, receipt fingerprints, key uniqueness, owner receipt links and body/principal agreement validate before any world mutation.

V1-v4 migration uses existing migrations first, then creates authority records from existing body/principal/control epochs with high-water zero and no authority receipts. Preserve all inventory owner receipts, items, nested provenance and job progress; do not reinterpret legacy owner receipts as authenticated authority outcomes. Worlds lacking inventory remain empty, with no invented bodies/matter. Legacy unfinished jobs remain paused and require explicit fresh authorization to resume.

On startup restore, prepare one candidate that increments every restored body control epoch once and leaves all sessions inactive; reset high-water for the new epoch while retaining historical receipt keys. Validate epoch headroom before committing any system. This startup fence also invalidates previous process tokens even if a peer ID is reused. Snapshot validation alone must not increment epochs; failed restore is unchanged, and successful startup fencing occurs once. Bind fresh sessions only after restore and before accepting gameplay. Repeated restart legitimately advances epochs; exhaustion blocks startup with a repairable error. Older binaries reject v5; rollback requires a saved compatible checkpoint, never stripping authority fields.

## Bounded profiling

Expose fixed numeric gauges for bindings, active controllers, queued lifecycle events, receipt occupancy and paused invalidated jobs. Add saturating exact-integer counters for stale-token, foreign-body, revoked-session, intent-conflict, receipt-replay, receipt-expired, capacity-rejection and restore-fence failures. Reset counters on startup; exclude them from canonical state. No principal/session/request labels, unbounded rejection log or per-tick copied inventory records. Optional traces use a bounded ring and never influence authorization or simulation order.

## Acceptance cases for later implementation

Use temporary snapshots, injected session/lifecycle providers and existing versioned Godot check discovery on Windows/Linux. Every rejection compares owner state, item quantities/provenance and epochs as applicable; counters may change. These are proposed gates, not executed results.

| ID | Concrete setup and expected result |
| --- | --- |
| A01 stale revision | Current binding epoch 7, inventory revision 12; new command expects 11. Terminal stale result, no owner revision or hand change. |
| A02 foreign body/container | Principal A controls human-2; intent injects human-1 actor or its container. Extra actor field fails exact validation; foreign container fails ancestry. No ownership or receipt disclosure. |
| A03 replaced in queue | A/session-old queues select-hand at epoch 7; trusted replacement installs session-new at epoch 8 before drain. Old command rejects; new session's command succeeds once. |
| A04 disconnected completion | Revocation arrives on job's final progress boundary. Lifecycle fence runs first; no transfer/receipt completion and retired view/grip is invalidated without lost items. |
| A05 duplicate | Epoch 7/number 4 succeeds at revision 12 to 13. Identical retry with expected 12 returns original receipt despite changed revision; altered slot at number 4 conflicts. Owner revision remains 13. |
| A06 eviction | Evict number 4 detail after bounded later receipts. Retry 4 returns expired, never a new mutation. Gap or exhausted sequence rejects deterministically. |
| A07 foreign world/session | Valid principal with wrong region, inactive session or different peer session cannot apply or read receipt. Trusted context fields alone do not bypass liveness. |
| A08 preview reach | Canonical target distance is 1501 mm while preview claims contact. World pickup rejects; at canonical 1500 mm with valid access/capabilities it may pass. Missing canonical provider fails closed. |
| A09 recovery | Checkpoint includes one completed mutation/receipt and a paused job. Restore fences 7 to 8 with no session; old retry cannot apply. Fresh status reports retained outcome; explicit resume revalidates, and no duplicate matter appears. |
| A10 invalid migration | Future epoch, duplicate binding, foreign owner link or epoch exhaustion rejects restore atomically. V1-v4 preserve items/receipts and absent-inventory worlds remain empty. |
| A11 rollback boundary | Crash before checkpoint restores earlier owner and receipts together. Outcome is documented as uncertain until reconciliation; no automatic new-ID resend. |
| A12 bounded overload | Fill lifecycle/receipt capacities; revocation cannot be silently lost and execution suspends if required. Counters saturate and traces remain bounded. |

## One next implementation slice

Propose a domain-only `self/select_hand` controller gate using existing two fixture bodies and injected authenticated session lifecycle. Add the authority component/token, bounded sequential receipt/high-water logic, atomic owner commit, proposed v5 migration/fencing and focused A01-A03/A05-A07/A09-A12 tests for this one operation. Reject unsupported session operations until their job/grip integration is implemented; retain debug fixtures explicitly. Pin actual envelope/schema versions and update API/architecture docs in that change.

Do not change the invite transport, UI or pose bridge in this slice. No world pickup, movement, cross-body jobs, equipment dependencies or general production rollout. Coordinator must reconcile transport/controller owners and approve this bounded slice before implementation. Subsequent world interaction work additionally requires A04/A08 and spatial authority acceptance.

## Validation and review status

For this prose-only change, run the existing `tools/ci/check-foundational-capability-matrix.ps1`, verify each local path above, inspect proposal/current-version consistency and run `git diff --check`. Do not rerun broad runtime suites for prose. Report draft PR/head and exact CI status separately; `.github/workflows/ci.yml` triggers on feature pushes and PRs to dev-master. CI on this doc cannot establish authority runtime acceptance. Keep the managed worktree and feature branch for review; no merge or deployment.
