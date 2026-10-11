# FP-01 controller restore fencing

Serialized successor to merged PR #52 (`0633a317475d82331fc0c9fe2e932911da595cc3`), based on current origin/dev-master `1fb749638f707e92ed92079fe32e5d8715570e35`. Implements only the same-process controller restore prerequisite from the [authority design](inventory-authority-design-milestone.md).

## Owner and lifecycle contract

InventorySimulationSystem owns a volatile exact integer restore generation, initially zero. Each successful restore_snapshot_record advances it once after decoding and publishing the complete inventory candidate, including when the restored record is identical. Both direct calls and SimulationRunner's startup-only restore pass through this owner. Failed decode or exhaustion leaves canonical state, generation and token identity unchanged. Generation never comes from snapshot input. It does not replace or advance any body's canonical control_epoch, action_epoch, quantities, receipts or owner revision.

InventoryControllerOwner.controller_restore_generation exposes the trusted synchronous fence; its default zero applies only to non-restoring owners. Every restorable implementation must advance the fence on successful restore. InventoryRuntimeControllerOwner delegates to the actual runtime and fails closed if it is freed. Authority initialization pins that owner's generation. Pin, validate, observation and all lifecycle transitions require generation agreement in addition to existing owner/principal/root/epoch checks. A mismatch denies tokens even when a restored canonical epoch matches the old token. Lifecycle rechecks the fence after the session provider callback, including a callback that also reconciles the authority. Owners/providers are trusted in-process interfaces, not a sandbox against arbitrary script mutation.

The trusted caller must explicitly invoke InventoryControllerAuthority.reconcile_after_restore after a successful restore, outside command execution. It requires an advancing valid generation and validates the complete current owner candidate against the existing 32-binding, unique principal/root bounds. Only then does it atomically replace all volatile bindings with inactive records and pin the new generation. Candidate failure preserves all previous binding/token identities and the old fence; they remain unusable while the owner generation disagrees. Repeated reconciliation without another restore is rejected. Changed body membership, principal or root comes only from the validated canonical restore, never from a client-supplied reconciliation map.

No session is automatically restored or rebound. A fresh explicit bind reads the restored canonical epoch, increments it once through the existing compare/commit API, and issues a new opaque token object. Reusing a session or reaching an earlier token's numerical epoch never reuses retired token identity. A newly created authority has its own object identities as before. Canonical epoch exhaustion continues to reject binding without mutation.

## Cadence, persistence, failure and profiling

All work is synchronous, explicitly invoked and bounded by the existing owner decoder and 32 bindings. There is no tick lane or automatic lifecycle composition; a future production owner must serialize restore/reconciliation before admission and command/job application. Runtime generation, sessions, tokens and bindings are volatile and absent from inventory v4 snapshots. No schema or durable migration changes.

At restore generation 9007199254740990, restore fails closed without wraparound. Snapshot validation also rejects at this limit so SimulationRunner's all-system validation detects exhaustion before any system publishes a restore. Consequently runner checkpoint capture, which reuses the same validation API, is unavailable at this theoretical bound; direct inventory capture remains read-only and available. Existing reconciled tokens remain valid after a rejected restore; this boundary does not silently revoke them or alter quantities. No recovery/reset API is supplied to rewind the fence within a runtime instance.

Authority's fixed profiling map adds reconciled_restore_generation to existing binding/active/rejection counters. An unreconciled owner yields no observations and zero fresh active controllers. Counters are read-only; rejection counts remain saturating. No network, async side effect, process, port, dependency, service, configuration example, external source or creative asset is added. First-party changes are MIT.

This is a same-process prerequisite, not production admission or live restore authorization. Receipt/high-water transactions, command hot-path integration, jobs/views/grips lifecycle invalidation, UI/reconnect, startup rotation and migration rollout remain deferred. Existing debug and authenticated fixture authorization is unchanged. SimulationRunner still prohibits restore after ticks or commands start; no world restore rollback policy changes.

## Verification

Use the versioned port-free runner with pinned Godot 4.7.2:

    ./tools/ci/run-godot-checks.ps1 -Godot <pinned-console> -TestNames inventory_controller_authority_test.gd,inventory_runtime_test.gd,inventory_spatial_test.gd,inventory_grip_runtime_test.gd,checkpoint_recovery_test.gd

The authority test exercises the actual inventory runtime and SimulationRunner restore, identical-epoch and rollback/epoch-reuse fencing, explicit reconciliation and fresh session reuse, blocked ingress/application/lifecycle before reconciliation, invalid restore atomicity, failed reconciliation atomicity, provider callback restore, and exact restore/control epoch exhaustion. Existing inventory and checkpoint checks cover canonical conservation and debug behavior. Windows/Linux CI discovers these tests through .github/workflows/ci.yml. Actual local results and exact-head CI are reported with the PR. Headless verification establishes no graphical, controller, VR or production acceptance. No merge, deployment or media upload is authorized.
