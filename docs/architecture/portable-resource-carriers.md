# Portable resource carriers

## Gameplay

New games launched through `FrontierBootstrap` use `shared.production.v1.json`: a resource canister starts in the local actor's inventory and another is available in the world tray. The original inventory fixture stays available for isolated subsystems. Hosts constructing `WorldRuntime` directly opt in with `resource_carriers_enabled = true` before entering the scene tree.

At an environmental source, select an owned canister and extraction mass, then extract directly into it. At the workstation, **Load selected mass into carried canister** can also collect existing depot stock. Move, equip, drop, collect or transfer that physical item using the existing inventory controls. Its payload follows the same stable item ID. Bring it back and **Unload selected mass to workstation** to use the feedstock in recipes. See [environmental extraction](environmental-extraction.md).

Canisters have a 1 kg shell, 2.5 L external size and at most 2 kg payload. Their internal chemical headspace is 2 L, using the same gas-pressure calculation and 1000 kPa limit as the workstation vessel. Each carrier holds one resource identity at a time. Empty it before changing material. Solids use the prototype mass limit; detailed bulk density and shape packing remain future work. These are resource containers, not wearable breathing tanks.

## Ownership and atomic transfers

Production owns each payload's exact material masses. Inventory owns the physical canister, parent storage, body equipment and movement receipts. These owners share stable item IDs; payloads are not also represented by duplicate inventory stacks. The closed 25 kg resource budget now includes all carrier payloads, including those in world storage or another body's inventory.

`load_cargo` and `unload_cargo` require `carrier_id`, `material`, `amount_milligrams` and `expected_revision`. Production command ingress still requires current world scope, a capable actor, logical workstation reach and an unreserved manipulator. Inventory derives the actor's accessible carriers from its owned containment graph. Another person's carrier, or one lying in the tray, must first be acquired through normal inventory interactions. A client cannot declare ownership.

Transfers prepare a detached production candidate. They reject absent feedstock, underflow, bulk/cargo capacity overflow, mixed material payloads, excess pressure and inventory/equipment overload. A disposable catalog view validates the candidate payload masses against the current complete inventory graph before any commit. The production candidate and its receipt commit together; derived inventory load caches are then refreshed in the same synchronous call, with no callback or await between preparation and commit. Inventory location and its revision do not change during a payload transfer.

The generic `InventoryItemCatalog` payload mass provider resolves mass from the canonical component owner. `InventoryLedger` adds payload mass once to shell mass, propagating it through all ancestor storage and body capacities. Equipment fitting observes that same loaded mass. Prospective views provide supplied masses only to server-side validation; transport clients cannot bind providers or submit these views.

## Observation scope

The production HUD lists only canisters owned by its actor, including while away from the workstation. Production observation removes global cargo records before deep copying and then inserts detached owned payloads. Shared depot/vessel observations remain shared. Other players' payload contents are not exposed through this HUD or inventory searches by this implementation. Inventory observations also reflect carried weight while away from the workstation.

The original inventory transfer logic continues to handle timed searches, resistance and unconscious actors. Moving a loaded canister does not mint resources or reset its contents. These canisters currently use the existing item condition field for presentation; punctures, leaks and pressure damage are not implemented.

## Persistence

Production snapshots are now v2, adding a bounded `cargo` map of at most 32 item IDs to complete material-stock records. Restore validates single-material payloads, charge-free finite quantities, pressure, mass conservation and catalog fingerprint. Cross-system validation then checks that every cargo key references an existing `item.resource-canister.prototype` or `item.plate.prototype` revision 1; plates require exactly 1 kg of plate payload. It also validates prospective body, nesting and equipment capacities against the saved inventory owner.

Production v1 restores migrate to v2 with no payload components. Worlds without production retain the previous finite-fixture migration. Existing inventory snapshots are not modified to spawn new canisters on restart. The production launch fixture only seeds new worlds; loaded physical item IDs and payloads persist exactly.

Resource shell mass remains part of the inventory object's mass model; production's closed resource budget tracks only mined/refined matter. No item or payload is deleted at zero content. General commodity creation/deletion and carrier crafting require a future item/blueprint transaction, so this slice seeds two shells explicitly rather than spawning them during transfers.

## Verification and next work

Windows cooperative acceptance now verifies scoped cargo, extraction capacity, physical plate restoration and active-batch JSON restart. The graphical route exercises component drop; see [acceptance evidence](../development/first-playable-acceptance.md). Broader nested/gas/terrain coverage remains follow-up work.

## Inventory extraction feedback

The inventory panel identifies the selected receiving canister by stable ID and displays scoped observed contents plus shell-inclusive loaded mass where item details are available. Missing fields are unavailable; the current payload observation provides no capacity quote. Missing selected canisters retain their ID without retargeting. Intended selection, pending intent and host-reserved/completed work remain distinct. See [the presentation milestone](../development/canister-extraction-feedback-milestone.md).

## Unloading presentation

The production panel names the scoped world/region production.store used by unloading; receiving station instance identity is unavailable in the existing observation. Intended IDs and milligrams, detached pending payload/revision/store, and exact host receipt remain separate. Removed canister/material selections stay unavailable without retargeting; only scoped existing cargo and stock are displayed. See [resource unloading feedback](../development/resource-unloading-feedback-milestone.md).
