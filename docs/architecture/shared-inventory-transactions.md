# Shared inventory transactions

## Implemented boundary

`SharedInventoryCoordinator` is the sole domain owner of one physical ledger, metadata/equipment for up to 32 bodies, and up to 128 retained transfer receipts. It prevents the independent mutable-ledger copies warned about in the [single-body foundation](body-inventory-equipment.md). It is not yet registered with `WorldRuntime` or network sessions.

The v1 snapshot stores the ledger once. Body records contain the existing body-state metadata without their own ledger. Restore validates unique body IDs and root claims, trusted pinned profiles, every body's active hand/equipment against the same ledger, and exact receipt shape/order. Caller-supplied trusted profile revisions are keyed by `JSON.stringify([profile_id, revision])`; the coordinator keeps detached copies of used profiles.

`data/inventory/shared.default.v1.json` contains two human bodies sharing the original backpack/pouch/crowbar fixture and a separate world tray. It is development initial state and is not loaded by bootstrap. Non-body roots and body root volume/count/tag limits remain trusted host configuration.

## Atomic transfer intent

`transact()` accepts an exact internal intent with request ID, action, actor/target body IDs, item ID, source/destination containers, applicable slot and expected shared revision. Both bodies must be distinct and registered. Physical ancestry resolves source/destination to their required body roots:

| Action | Source | Destination | Equipment effect |
| --- | --- | --- | --- |
| `take` | Target's root or nested storage | Actor's root or nested storage | Equipped target items require `unequip` instead |
| `insert` | Actor's root or nested storage | Target's root or nested storage | Releases actor's binding if the actor relinquishes an equipped item |
| `equip` | Actor's root or nested storage | Target's direct root | Releases actor binding and fits the existing item into a free compatible target slot |
| `unequip` | Target's currently fitted item/slot | Actor's root or nested storage | Releases target binding |

The owner copies a candidate, applies one ledger move, updates affected equipment and increments both body revisions and the shared revision. It then validates **all** registered bodies against the candidate ledger before replacing canonical records and adding the receipt together. A full container, invalid slot, overloaded fitted storage, wrong source/root, exhausted revision or failed restore validation changes nothing. Loaded storage transfers its descendant ownership links and mass with the same stable item IDs and condition.

Active-hand selection stays unchanged. Taking into an actor root does not automatically equip into an occupied hand or invent a pocket; explicit receiving-hand/storage behavior belongs in future command/UI rules. Search, item activation, material splitting/consumption and cross-owner transfers are not implemented by this API.

## Receipts and retries

Successful receipts contain request ID, an SHA-256 intent fingerprint and resulting shared revision. The fingerprint covers owner scope and ordered request fields, normalizing the expected revision to an integer for JSON retry compatibility. It identifies an intent; it is not a signature or access token.

An identical retained request returns its detached original receipt before revision checks, without another transfer. Reusing a retained ID with different intent rejects. Receipts persist with ownership and equipment, are unique/increasing in snapshots, and retain the latest 128 successful operations. After eviction, the original stale revision still rejects; receipt retention does not promise indefinite acknowledgement or prohibit deliberate reuse with a newly constructed intent. Production request/job IDs must not be reused, and durable receipt retention/recovery policy remains an integration gate.

Global compare-and-swap deliberately serializes this small prototype owner. Production region partitioning and request-rate/admission limits must be measured before increasing bounds. Full-body validation is bounded, but currently repeats ledger validation for each body; representative profiling and a shared validation context are future optimization work.

## Timed job completion bridge

`complete_job()` accepts a trusted [timed job](body-inventory-interaction-jobs.md), current tick, server observations/context and the exact transfer intent saved by the future job owner. Job ID must equal request ID; action, bodies, item and slot must match. The selected target container must match the source for take/unequip or destination for insert/equip.

For new completion, the job must be freshly ready in this tick with passing epochs/physical policy, and both inventory revisions must still match the coordinator's actual body metadata. Only then does `transact()` commit effects and a receipt. An already retained identical completion returns its receipt without repeating effects, including on a later delivery retry. The external job collection must remove/acknowledge the job through its eventual checkpoint protocol; it must not duplicate this coordinator or bypass receipts.

This bridge does not produce body action/control epochs or authenticate a principal. `transact()` is a trusted lower-level mutation method, not a public command. The server must bind actor/body and owner scope, enforce reachable/visible access paths and policy, rate-limit intents, and save immutable source/destination intent with the job. Do not accept actor IDs, passivity observations or root capacity records as client attestations.

[Scoped search views](scoped-inventory-searches.md) now provide volatile principal-bound direct-content projections. Their transport/UI integration, closure/lock state, reaction command ordering, bounded job ownership and atomic world/persistence checkpoints remain pending. The existing local preview has no other-player inventory access yet.

## Verification

Windows Godot 4.7.2 import and `shared_inventory_coordinator_test.gd` passed. Checks cover nested take, target equip/unequip, condition/identity preservation, both-body revision changes, incompatible/capacity/root rejection, loaded bag subtree transfer, identical JSON retries, altered request reuse, stale requests, receipt churn/retention, shared JSON recovery, duplicate root/receipt rejection and timed completion/retry. Windows/Ubuntu CI includes the script; Linux and production runtime/network integration remain unverified locally.

State and internal intent schemas are `shared-inventory-state-v1.schema.json` and `shared-inventory-transfer-intent-v1.schema.json`. The internal intent's v1 is defined by its schema/adapter, rather than a new public command envelope. Catalog resolution, graph/slot validation, body-root uniqueness and receipt ordering remain code invariants beyond schema shape.
