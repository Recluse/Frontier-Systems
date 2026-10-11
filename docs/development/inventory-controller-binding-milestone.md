# FP-01 inventory controller binding increment

Standalone implementation successor to design PR #47 (`9a05be6cdd5bccf80d2312530ad66508c6ce18de`), based on integration head `578a3f559cc86ba0f9ccb1f88aee99b37f3034ad`.

## Status and ownership

**Unintegrated domain component.** `InventoryControllerAuthority` is not instantiated by inventory, transport, UI or simulation admission. It establishes no production gameplay authorization. The future simulation inventory owner must call trusted lifecycle operations in a bounded tick-start lane before intents/jobs. This increment provides synchronous transition primitives, not that lane or its overload reconciliation.

The component validates at most 32 isolated body records against an exact unique owner-body ID set, with one principal per body. It deliberately copies fixture metadata for independent testing. These copies are not canonical inventory metadata. The existing `InventorySimulationSystem` body `control_epoch` remains the sole canonical epoch when integration is implemented: refactor the binding component to index/read that owner's validated candidate and commit lifecycle changes into that same body record. Do not install a second epoch counter. Shared owner body/root agreement must be checked against the actual owner candidate at that integration boundary; supplied IDs here establish identity membership only.

## Domain API v1

- `initialize(world, region, bodies, owner_body_ids, provider)` validates every candidate before installation; subsequent initialization is rejected. Empty regions are supported. Body records have exactly `body_id`, `principal_id`, `control_epoch`; IDs and integer bounds reuse `ControlContractValidation`.
- Trusted `bind`, `replace`, `revoke` require the current principal and exact expected epoch. Bind requires inactive state; replacement requires an active different session; revoke requires active state. Each successful transition increments once, up to 9007199254740990. Failure preserves bindings/token identities; rejection diagnostics may advance. No principal reassignment API is exposed.
- Inject `InventoryControllerSessionProvider` with a synchronous trusted in-memory live-session/grant view. Its default denies. Bind/replace, ingress `pin` and application `validate` query it. No asynchronous external effect belongs in this provider. Revoke does not require a live provider session.
- `pin` returns one opaque `InventoryControllerToken` per active binding. It has no claim fields or serialization. Authority keeps the pinned principal/body/session/epoch internally and requires current object identity plus current authenticated context/grant, world/region and provider permission on application. Fabricating a token, mutating a detached observation or reusing a retired session cannot revive it. Same-process trusted code is the authority boundary; this is not a sandbox against malicious GDScript.
- `validate` requires the server-derived expected body and returns detached body/epoch data. Errors use `stale_or_foreign_token`, `session_denied`, `binding_conflict`, `invalid_lifecycle`, `unknown_body`, `invalid_candidate`, `epoch_exhausted`. Retired tokens are not retained to diagnose replacement versus revocation; both fail closed.

## Cadence, persistence, failure and counters

No autonomous tick/process or callback mutation. Trusted owner operations run synchronously at a future simulation boundary. Epoch exhaustion rejects even revocation atomically; later integration must suspend admission/execution for unreconciled revocation, rather than allow an exhausted active binding to continue. There is no durable snapshot, startup fencing or restore API here. Tokens/sessions remain ephemeral; fresh authority instances reject another issuer's identity. No exported observation can be treated as an inventory snapshot.

Fixed counters expose binding/active-controller gauges and a saturating exact-integer rejection count. Collections are bounded by 32 bodies, with one current token per active body and no retained retired-token list. No trace history, receipt or lifecycle queue is allocated.

## Verification and successor

The focused `tests/godot/inventory_controller_authority_test.gd` checks candidate atomicity, principal/owner identity mismatch, capacity, detached inputs, trusted lifecycle conflicts, current grants/provider liveness, debug and foreign-region rejection, forged/foreign/stale/replaced/revoked tokens, session reuse and final exact epoch/exhaustion without partial mutation. Existing `tools/ci/run-godot-checks.ps1` automatically discovers this check on Windows and Linux in `.github/workflows/ci.yml`; local execution uses pinned Godot 4.7.2 on Windows.

Local verification results and final-head CI are reported with the PR. CI runs the ordinary wider suite; this component test opens no ports and uses no services. No configuration examples change. No upstream research or creative assets were added; first-party code remains MIT.

The serialized successor must integrate the single canonical epoch, actual shared owner body/root validation, lifecycle ordering/capacity reconciliation, jobs/views/grips invalidation and startup fencing. Receipt/high-water atomic transactions and snapshot v5 remain separate required work before production admission. No inventory runtime, shared schemas, transport, UI, input or guide changes accompany this increment. No merge or deployment is authorized.
