# Scoped inventory searches

## Implemented foundation

`InventorySearchViews` provides bounded, volatile observations from freshly completed `search` jobs. `SharedInventoryCoordinator.direct_container_observation()` supplies an internal direct-content projection after resolving the container to the selected target body's root. Neither method is a public network endpoint; authenticated principal/body binding and physical observations remain server responsibilities.

A grant requires a fresh ready search job, its original policy, matching current actor/target inventory revisions, passing server context and physical conditions, and an authenticated principal ID supplied by the owner. The store captures the exact job targets, action/control epochs, owner instance/identity/revision and expiry. It derives the policy from the job's detached trusted policy record rather than accepting an independent replacement definition.

Views are not in world snapshots and have no restore API. Restarting the store requires new searches. Owner replacement invalidates views even if IDs and revisions match; this prevents an old grant from projecting a replacement ledger. A normal transaction on the same coordinator also invalidates existing views through its revision change.

## Projection and privacy

A v1 observation contains view/body/container IDs, issued/expiry ticks and direct item summaries only: stable item ID, definition ID/revision, condition in permille and whether the item supports storage. It omits the ledger, ownership manifest, nested item contents, private PDA notes, programs, brains and permission records.

For example, searching the prototype backpack shows its pouch, not the crowbar inside that pouch. The pouch needs a separate timed search and physical access path. Knowing its item ID or `has_storage` flag is not an access grant. A search view also grants no item activation, equipment change or transfer capability; those still use their independent timed/command rules.

The schema is `docs/schema/inventory-search-view-v1.schema.json`. Its shape is suitable for a future authenticated observer transport, but no such route or client inventory widget exists yet. Definitions can later provide display names/icons without exposing canonical private metadata.

## Expiry, revocation and retries

The store holds at most 64 views. Lifetime defaults to 300 fixed ticks (5 seconds at the current 60 Hz); its trusted constructor clamps tuning to 1–3,600 ticks. Tick advancement is monotonic and bounded by the exact-JSON integer limit. At `tick >= expires_tick`, views expire. Reads and grant attempts prune expired entries; capacity rejects additional live views without evicting another player's active view.

Every read revalidates:

- The same authenticated principal and exact authoritative owner instance.
- Original actor control epoch, target action epoch and both inventory revisions.
- Current target availability, actor manipulation, reach, movement/resistance and access-path conditions under the original search policy.
- Current canonical owner/body revisions and target-container ancestry.

Wrong-principal reads/close attempts reject without revoking the legitimate principal's view. Changes to authenticated context, physical conditions or canonical state revoke the view. `close()` permits its owner to dismiss it; `revoke_principal()` supports disconnect/control cleanup. The current conservative shared-revision guard revokes on any owner transaction, including unrelated inventory work; more granular container revisions are future work.

An identical retained search delivery can return the current view after revalidation, without extending expiry. A retained job ID cannot be reused for different job state/targets. Expired views cannot be renewed from an old completion tick. These are volatile read grants, not durable transfer receipts. No knowledge already legitimately displayed can be retroactively erased from a player's memory; revocation prevents further authoritative reads.

The store's private epoch/principal/owner bindings are never serialized into the player observation. `diagnostics()` exposes only active-view count and capacity for bounded profiling. The future runtime must invalidate/push close messages to observers, call principal cleanup and apply admission/rate limits; it must not route complete coordinator snapshots to another player.

## Verification and next work

Windows Godot 4.7.2 import and `inventory_search_views_test.gd` passed locally. Checks cover incomplete-job rejection, direct-only projection, detached reads, wrong-principal rejection, retry expiry, exact expiry, no stale renewal, epoch/revision and physical revocation, canonical mutation/owner replacement, principal cleanup, capacity and unchanged inventory state. Existing shared-transfer regression checks also pass. Windows/Ubuntu CI includes the script; Linux execution remains unverified locally.

The [local inventory runtime](inventory-runtime.md) now issues and reads these views through fixture-bound debug contexts and prunes them each tick. Next: target-inventory widgets using customizable overlays, production authenticated search/resist/close intents and scoped observer delivery. Actual closures, visibility/occlusion producers, networked players and observer notifications remain pending.

## Controller lifecycle scope

`revoke_body(body_id)` is a trusted, bounded, infallible invalidation operation on canonical actor/target job IDs. InventorySimulationSystem invokes it only in the successful epoch publication section after all fallible preparation. It removes participating views immediately, including observers of a target whose controller changes, while preserving unrelated bodies' views. Failed lifecycle transitions leave views intact. No UI identity, principal-wide guess, inventory mutation or schema is involved. See [atomic lifecycle contract](../development/inventory-controller-lifecycle-invalidation-milestone.md).
