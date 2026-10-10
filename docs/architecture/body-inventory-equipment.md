# Body inventory and equipment transactions

## Implemented foundation

`BodyInventoryState` combines a physical ownership ledger, a trusted body equipment profile, slot bindings and active-hand selection into one detached domain transaction boundary. It is not yet registered with `WorldRuntime`, network sessions or the client UI. The local preview character still has no authoritative inventory.

The v1 record contains body ID, state revision, pinned profile ID/revision, body root container ID, active-hand slot ID, equipment bindings and the complete ledger. `data/inventory/body.default.v1.json` supplies a human with the existing loaded backpack equipped on its back and the left hand selected. This is an explicit development fixture, not production spawning.

An equipped item remains at exactly one ledger location: directly inside the body's root. A slot binding annotates that possession; it does not create another item or add mass. Contents stay in their existing hosted containers. Carried but unassigned root items are supported by this foundation; future gameplay must define physical access and storage rules for them rather than treating the root as invisible pockets.

## Validation

`from_record(record, profile, catalog)` validates the complete combined state before construction:

- Resolve the pinned profile against the supplied trusted definition, with exact bounded revisions and stable IDs.
- Require a configured active hand, or an empty active-hand ID for a body with no hands.
- Validate the complete ownership ledger and require the body container to be a root whose mass capacity exactly matches the profile's carried-mass limit.
- Require unique slot IDs and unique equipped item IDs. Every binding must resolve to an existing directly carried item and a compatible configured slot.
- Check slot tags, outer volume and **loaded mass**, including all descendants for containers. Filling an equipped backpack must still satisfy its slot and aggregate carried-mass limits.

`InventoryLedger.item_observation()` returns a detached instance, trusted tags, loaded mass and fixed outer volume. Loaded mass is derived from the validated graph and checked for exact-integer overflow. It grants no access or tool capability.

The body snapshot schema is `docs/schema/body-inventory-state-v1.schema.json`, referencing the existing ledger schema. Catalog/profile resolution, unique bindings, direct possession and loaded-fit checks are code invariants beyond JSON Schema.

## Operations and atomicity

All mutations take the expected **body state revision**. They operate on detached candidates and replace ledger/equipment together only after complete validation. A failed slot fit, occupied slot, stale revision, source conflict or capacity violation leaves both parts unchanged.

| API | Behavior |
| --- | --- |
| `select_hand(slot_id, revision)` | Select a configured hand without moving its item |
| `switch_hand(revision)` | Cycle configured hands; reject handless bodies |
| `equip_item(item_id, source, slot_id, revision)` | Move an item to the body root when needed and bind it to a free compatible slot |
| `unequip_item(slot_id, destination, revision)` | Remove the binding and move the same item to the destination, or leave it directly carried if destination is the body root |
| `move_item(item_id, source, destination, revision)` | Move an unequipped item and revalidate every loaded equipment binding afterward |

Reassigning an equipped item to another free slot replaces its old binding atomically. Occupied destinations require explicit unequipping; swapping occupied hands is not implemented. Ordinary transfers reject equipped items, requiring the equipment operation. Same-location ordinary transfers reject.

Each successful operation increments the body revision once. The embedded ledger revision increments only when a physical container location changes. Changing active hand or reassigning an already carried item changes only the body revision. Both revisions reject exhaustion at the shared exact-JSON integer bound.

State records, profile copies and observations are detached. The wrapper never exposes its owned ledger for independent mutation. A production system must be the sole owner of the combined record. Do not give multiple players independent mutable copies of a shared ledger; shared storage and multiple bodies need a region-owned transaction coordinator. Cross-ledger transfers remain pending.

## Authority and remaining integration

[Other-body physical interactions](../design/other-body-inventory-interactions.md) can authorize searching, taking, inserting and equipment changes through timed attempts while the target remains passive. Resistance/movement interrupts them. These require shared-region coordination and server-computed physical access, beyond this single-body record API.

These are domain APIs, not authenticated commands. The server must still bind principal to body, verify reach, source/destination access, tool/function eligibility, reservation ownership and request receipts before calling them at a fixed tick. Root volume/count/tag limits and non-body roots remain trusted host configuration. Snapshot imports are not client requests.

Equipping damaged hardware does not repair it or grant its operational capability. Two-handed/multi-slot grips, anatomy changes, cyborg module installation jobs, lawset permissions, closed-container access, material batches, crafting reservations, durable persistence and authenticated inventory UI remain later work.

The next integration step is a registered inventory system with server-owned body/root mappings, bounded typed commands and retry receipts, followed by inventory observations/widgets. Until those gates exist, maintenance tools stay development fixtures rather than possessions validated by this state.

## Verification

Windows Godot 4.7.2 import and `body_inventory_state_test.gd` passed locally. Checks cover the loaded human fixture, hand cycling without physical transfer, nested-tool equipping/unequipping, occupied/incompatible slot rejection, atomic failure, hand reassignment, stale selection, duplicate slot/item bindings, invalid equipped locations, inflated body capacity, loaded backpack limits, failed backpack filling, detached/JSON recovery, handless AI state and revision exhaustion.

Existing ledger checks also run after the new observation API. Windows/Ubuntu CI includes the body script; Linux execution and runtime/network integration remain unverified locally.
