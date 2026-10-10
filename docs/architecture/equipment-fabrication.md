# Equipment fabrication and material provenance

## Ownership and composition

EquipmentBlueprintCatalog owns immutable trusted assembly definitions separately from commodity recipes. Each definition names an inventory definition/revision, material requirements, fabrication/salvage energy and a display label. The validator permits at most 32 unique outputs, registered materials and registered zero-base-mass equipment tagged equipment.fabricated. Output definitions currently cannot have inventory child storage; that extension needs container-graph factory transactions.

Production owns construction material records in snapshot v3's structures map. Each stable item ID references blueprint_id, a SHA-256 fingerprint of its normalized specification and its exact bill of materials. Inventory owns location, equipment bindings and condition. Canister contents remain in the separate cargo map. Inventory payload mass is structure plus contents, counted once through the trusted provider. Starter shells retain their original base mass and are outside the closed extracted-material budget.

There is no branch on blueprint name in transaction logic. Factory definitions and resource.carrier/tool.extractor tags establish capabilities. UI names and primitive dimensions are presentation choices. All new art and code are first-party MIT.

## Transactions

fabricate_equipment accepts exactly expected_revision and blueprint_id. At fixed-tick application the owner checks station reach, actor capabilities, printer power, finite energy, trusted materials and the 32-item structural bound. It creates a stable item ID from the retained request ID, debits depot materials, creates the structural record, prepares inventory creation and validates prospective loaded capacities before committing both owners. No await/service callback occurs during this transaction.

salvage_equipment accepts exactly expected_revision and item_id. Only the actual inventory owner can salvage the matched fabricated definition. The recycler requires power/energy and receiving capacity. Contents and bill of materials are returned intact to depot stock, the physical item and structural/cargo records are removed, and any equipment binding is released together. Nested ownership is resolved by the existing ledger. Failure leaves the candidate uncommitted; unexpected adoption failure rolls production back. Spent fabrication/salvage energy is not recoverable material.

Commands have retained principal/intent fingerprints; identical retained retries do not fabricate or salvage twice. Altering an intent under the same retained ID fails. Old receipts are bounded to 64; do not promise unlimited lifetime idempotency. Prototype fabrication and equipment salvage are immediate transactions, while commodity refinement/printing remain timed batches.

## Persistence and observations

Snapshot v3 adds structures to the v2 record; v1/v2 migrate with empty structures. No new physical items are spawned by migration. Cross-system validation requires every structure to match an existing inventory item and definition, every manufactured item to have a structure, each blueprint fingerprint/material bill to match and the closed 25 kg resource budget to include shell matter, cargo, depot/vessel, deposits, walls and reserved batches. An edited pinned definition requires explicit migration for existing manufactured equipment.

The client observation v3 exposes only owned structure/cargo records and shared trusted blueprint metadata. A transferred item therefore changes which player can observe its construction/contents; possession does not reset mass. The read-only projection is not valid restore input. Legacy local inventory observation v2 remains available, with enriched v3 opted into by the network host.

Snapshots use the existing asynchronous checkpoint adapter; Windows needs no process orchestration. Worker callbacks never mutate fabrication or inventory. Checkpoint durability limitations remain unchanged.

## Bounds, cadence and profiling

Commands use the normal production system at priority 300, after inventory priority 200. There are at most 32 structural records and 32 blueprints; material bills have at most 32 entries. Equipment fabrication shares the finite fixture energy budget and printer/recycler flags. The payload provider performs item-key lookups without rebuilding all equipment masses; prospective validation builds a bounded map only for transactions/restores. Production profiling includes fabricated_equipment count alongside batch, stock, energy and receipts.

## Scope

Two default blueprints prove resource-container and tool manufacturing. There is no freeform ship construction, equipment child-storage factory, thermal/chemical realism, arbitrary component demolition, sustained extraction, tool battery or tool-wear model yet. Scaffolded interfaces are not completed versions of those systems. See [milestone evidence](../development/equipment-fabrication-milestone.md).
