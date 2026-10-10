# Inventory ownership ledger

## Implemented boundary

`InventoryItemCatalog` and `InventoryLedger` under `src/core/inventory/` implement a bounded, detached physical-item ownership graph. They are domain objects, not scene nodes. They are not yet registered with `WorldRuntime` or exposed to clients. The [player inventory design](../design/player-inventory-and-equipment.md) remains the full gameplay contract.

The catalog accepts exact v1 item definitions with pinned identity/revision, tags, intrinsic mass, outer volume and optional storage capacity. It rejects duplicate revisions and holds at most 4,096 definitions. Reads return detached records. These definitions describe inventory dimensions, not material bills, recipes or executable tool behavior.

The ledger's versioned snapshot contains a stable ledger ID, global state revision, containers and item instances. An instance has one stable ID, one pinned definition, condition in integer permille from 0 to 1,000, and exactly one container location. Duplicate instance IDs are rejected. Moving an item preserves its ID, definition and condition.

## Containers and loads

Root containers have empty `owner_item_id`; their limits are trusted host configuration. A hosted container belongs to exactly one storage item and its capacity must equal that item's catalog definition. Every storage item must have its contents container, including when empty. An item without storage cannot host a container.

Capacity records specify contents mass, contents volume, direct item count and accepted tags. At least one accepted tag must match each direct child's trusted item tags. Containers support up to 512 direct entries, subject to lower configured limits. The graph has at most 512 items and 256 containers, and every item ancestry must reach a root within eight containers. Cycles and orphan hosts are rejected.

For each item, its intrinsic mass contributes once to its immediate container and each ancestor. Consequently a root carrying a backpack counts backpack mass plus all descendants; a backpack's contents limit excludes its own mass. No float arithmetic is used for load accumulation, and exact-integer overflow is rejected before addition.

Volume counts direct children's declared outer volume. A rigid container's outer volume already includes its interior, so nested contents do not add another external volume at an ancestor. Flexible/deforming bags are not modeled yet; their definitions currently use fixed prototype outer volumes. Each hosted container still enforces its own internal contents volume. Volume is integer millilitres; mass is integer milligrams.

`container_load(id)` returns detached `mass_milligrams`, `volume_millilitres` and `direct_items` observations. These are derived validation results, not independently writable state.

## Atomic movement and revision checks

`move_item(item_id, source_container_id, destination_container_id, expected_revision)` performs a compare-and-swap over the ledger:

1. Require the current, non-exhausted ledger revision and the item's actual source location.
2. Copy the candidate record and change only the moved item's container ID.
3. Increment the candidate revision and validate its complete ownership graph against the trusted catalog.
4. Replace owned records and derived loads together only after successful validation.

A container item moves its descendant items implicitly through their existing ownership links. Moving into itself or a descendant fails cycle validation. Missing destinations, incompatible tags and exceeded capacities fail without changing either location or the revision. Same-location moves reject as no change. Full validation is bounded by the graph limits and eight ancestor steps per item; expensive mesh, network and storage work is absent.

Successful results identify the item, source, destination and resulting revision. Stale requests reject rather than reapply a move. This is **not** an idempotent receipt ledger: production request IDs and retained retry receipts remain necessary. No additions, deletions, splitting, stacking or material consumption API is exposed by this ledger.

## Authority and recovery gates

`from_record()` imports a complete trusted snapshot; it is not a client command or a safe way to accept client-specified root capacities. The future system owner must validate root capacities against registered body/storage records, ledger scope and existing source provenance. Development fixtures are explicit initial state, not an audited production spawn mechanism.

Inventory mutation must run through that owner's fixed-tick commands after principal/body binding, reach, access policy, tool checks and reservations. The ledger alone grants no permission. [Body equipment state](body-inventory-equipment.md) now composes occupancy and active hands with this ledger; two-handed grips, closed-container access, material batches and machine installation/reservations remain separate integration tasks.

The record schemas are `inventory-item-definition-v1.schema.json` and `inventory-ledger-v1.schema.json`. JSON Schema describes shape and quantity limits. Catalog resolution, hosted-capacity equality, unique locations, graph reachability, overflow and aggregate limits are validated by GDScript. Snapshot restoration reconstructs derived loads; it never trusts saved load counters. Cross-ledger/region transfers require a transaction over both owners and are not implemented.

Once registered, snapshots must include the ledger with affected equipment, terrain and work orders at an atomic checkpoint. Persistence calls must use asynchronous adapters and validated later-tick acknowledgements. Do not let PHP services or LLM callbacks invoke the mutation API directly.

## Defaults and verification

`data/inventory/items.default.v1.json` defines a backpack, pouch and crowbar. `ledger.default.v1.json` places the pouch inside the backpack and the crowbar inside the pouch, with separate body and world-tray roots. The fixture starts at revision zero and totals 3.5 kg. It is not loaded by bootstrap.

Windows Godot 4.7.2 project import, equipment-profile checks and `inventory_ledger_test.gd` passed locally. Ledger checks cover nested mass, fixed outer volume, condition preservation, loaded-container movement, independent child movement, atomic rejection, stale/source conflicts, duplicate IDs, catalog detachment, unknown definitions, altered hosted capacity, capacity/tag limits, eight-container ancestry boundaries, mass overflow, revision exhaustion and JSON recovery. Windows/Ubuntu CI includes these scripts; Linux execution remains unverified locally.

Next: authenticated system registration, retry receipts and material reservations, then client UI and persistent multiplayer integration.
