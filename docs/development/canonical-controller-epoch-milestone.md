# FP-01 canonical controller epoch increment

Serialized successor to binding PR #50 at e67145debb4f16e897946805f1a8658d13cc4cdf, based on origin/dev-master e9f4aa5075be02e7bd9a625d2e1358946c6cb27e.

## Owner and API

InventorySimulationSystem remains the canonical owner of body metadata and its sole control_epoch. SharedInventoryCoordinator remains the ledger/equipment/root owner. InventoryControllerOwner is a trusted synchronous interface, implemented by InventoryRuntimeControllerOwner. Its controller_candidate returns a detached body-ID map with body_id, principal_id, body_container_id and control_epoch, derived from actual inventory metadata and validated shared owner roots. The runtime reuses its snapshot decoder to validate identities, body membership and ledger/root agreement before projection. Invalid, foreign or mismatched candidates fail before mutation.

InventoryControllerAuthority.initialize(world, region, owner, provider) replaces the independent body/owner-ID fixture API. No independent canonical epochs exist in binding state. Bindings retain principal/root identity anchors, session, token identity and the token's pinned epoch; that pinned value is only a freshness assertion. Live observations and validation derive epochs from the owner. Initialization validates bounded unique principals/roots and installs at most 32 bindings atomically. It rejects subsequent initialization.

Trusted bind/replace/revoke read the canonical candidate, validate lifecycle/principal/session and exact expected epoch, prepare an ephemeral token candidate, then call owner.commit_control_epoch(expected_body, next_epoch). The runtime compares the complete target body projection, requires exactly one increment and validates exact-integer bounds. Only after successful canonical commit does binding publish the prepared token without another callback or fallible step. Provider callbacks that change the target metadata cannot silently overwrite it. Failed owner commit preserves binding/token state; exhausted transitions preserve the entire canonical snapshot as well.

Pin and validate require live authenticated session grants and current owner principal/body/root agreement. A changed canonical epoch fences old tokens, including ingress pin. A changed identity/root fails closed and requires later owner reconciliation. Replacement/revocation retires object identity; session reuse cannot revive it. The owner/provider are trusted in-process interfaces, not a sandbox for hostile GDScript.

## Cadence, persistence and failure

The API performs synchronous owner work only when explicitly invoked. There is no lifecycle queue or automatic tick lane, production composition, UI, transport or command admission change. A future owner must serialize lifecycle at tick start before commands/jobs. Existing debug and authenticated fixture behavior remains unchanged.

Canonical epoch changes persist in the existing inventory v4 body record; the schema is unchanged. Bindings/tokens/sessions are volatile. The subsequent [controller restore fencing milestone](inventory-controller-restore-fencing-milestone.md) adds same-process volatile fencing and explicit reconciliation. This remains neither snapshot v5 nor startup fencing or a safe live restore rollout. Receipt/high-water transactions, jobs/views/grips invalidation, lifecycle capacity reconciliation, startup rotation and production token gating remain required before production admission.

At epoch exhaustion even revoke rejects without mutation. The current active token is preserved; future admission/execution must suspend unreconciled revocations. No autonomous process, network call, ports or async side effect is added. Fixed counters expose bindings, currently fresh active controllers and a saturating rejection count. Candidate validation reuses a bounded full owner decoder; it is not yet optimized or admitted into the per-command production hot path.

## Verification

The focused inventory_controller_authority_test uses both an injected owner and the actual canonical runtime adapter. It checks shared snapshot/owner/binding epoch agreement, root and principal mismatch, foreign body rejection, replaced and externally advanced epoch token fencing, injected commit failure, freed owner, and exact exhaustion preserving full snapshot and token identity. Existing candidate/session/grant/capacity tests remain. Inventory runtime, spatial and grip tests cover unchanged development behavior.

Use the existing port-free runner:

    ./tools/ci/run-godot-checks.ps1 -Godot <pinned-4.7.2-console> -TestNames inventory_controller_authority_test.gd,inventory_runtime_test.gd,inventory_spatial_test.gd,inventory_grip_runtime_test.gd

CI automatically discovers the test in its Windows/Linux Godot matrix. Actual local and exact-head CI results are reported with the PR; headless checks do not establish graphical/controller/VR acceptance. No configuration examples, shared schema, guide/input scope, dependency, upstream reference or creative assets change. First-party code is MIT. No merge or deployment is authorized.
