# Player inventory and equipment

## Required gameplay

Every player has an inventory interface. Physical capacity and equipment slots belong to the current body or controlled device, independently of player identity, species name, input source and UI. Humans use two hands with a selectable active hand, wear clothing and carry equipment such as backpacks. Other species may define different limbs, wearables and capacities. Cyborg inventory depends on chassis, manipulators and fitted modules. Station AIs have an inventory view over authorized physical cores, drones and storage rather than invisible pockets.

Human, LLM and scripted controllers submit the same inventory commands and receive the same capability checks. Controlling a remote body does not teleport items from the player's previous body. Death, cloning and brain transfer preserve each body's actual possessions; a replacement body does not duplicate them.

## Implemented foundation

`InventoryEquipmentProfile` under `src/core/inventory/` validates a detached v1 definition with pinned ID/revision, aggregate carried-mass limit, ordered hand-slot IDs and bounded slot rules. Slot rules declare accepted tags and maximum mass/volume for one fitted item. Hand IDs must reference real unique slots. `next_hand()` cycles the configured hands; it only returns a selection and never moves items. `assess_slot()` performs preliminary compatibility and single-slot dimension checks against trusted item data.

Default fixtures under `data/inventory/` include:

| Body | Hands | Other equipment | Prototype carried mass |
| --- | --- | --- | --- |
| Human | Left, right | Uniform, suit, head, feet, gloves, back, belt, PDA | 40 kg |
| Cyborg | Left/right manipulators | Utility module | 80 kg |
| Station AI | None | None on the abstract controller | 0 kg on that controller |

Limits are provisional gameplay tuning. Human back accepts a backpack or tank; separate suit mounts can be added through revised profiles. A backpack is a physical item with its own container, not an automatically granted storage capacity. Species and chassis additions use definitions/composition, not a hierarchy of specialized inventory classes. Profile acceptance alone does not authorize wearing or using an item.

Mass uses integer milligrams, consistent with [terrain/material transfers](materials-terrain-and-reconstruction.md); volume uses integer millilitres. Records bound exact integers to 9,007,199,254,740,990, slots to 64, hands to 16 and accepted tags per slot to 32. The schema describes record shape; code additionally enforces unique slot IDs and valid hand references.

The [ownership ledger](../architecture/inventory-ownership-ledger.md) adds catalog-backed instances, bounded nested containers, derived loads and atomic revision-checked transfers. [Combined body equipment state](../architecture/body-inventory-equipment.md) now adds slot occupancy, saved active-hand state and atomic equipment/ledger operations with loaded-mass validation. These domain objects are not registered with the world runtime yet. Runtime inventory UI, authenticated commands, multi-slot grips and material batches remain pending. The local preview character does not yet have authoritative inventory. Profile fit checks alone do not grant access or validate anatomy.

## Ownership, containers and equipment

[Other-body interactions](other-body-inventory-interactions.md) include timed searching, pickpocketing, insertion and equipping/removing items while the target permits progress through inaction. Deliberate movement or resistance interrupts attempts. Server-owned access paths, scoped observations and atomic multi-body transfers remain required; knowing an item/container ID is insufficient.

The future authoritative inventory system owns stable item instances and material batches, their locations, equipment occupancy and active-hand selection. Each physical item has exactly one location: world placement, container, equipment slot, machine installation or work-order reservation. Equipment is a location relation, not a copied item record. Backpacks, belts, suit storage and machine compartments reuse the same container contracts.

- Count an item's own mass and all descendant contents once toward the carrying body's aggregate load. Moving from hand to backpack does not change total carried mass.
- Enforce per-container mass, volume, entry-count and item-category limits. Reject containment cycles; bound nesting depth and total traversal cost. Do not allow containers to evade capacity through recursion.
- Support bulky and two-handed items with atomic reservations of multiple hand slots. Selecting a hand does not free another occupied hand. Swapping occupied hands must be one validated transaction.
- Derive wearable fit from anatomy, equipment dimensions and configured slot constraints. Future missing/injured limbs and chassis upgrades change available capabilities without deleting contents. Resolve removal safely into another owned location or a world drop.
- Separate a fitted cyborg tool/module from its activation, lawset permission and powered operation. Installing a module uses the construction/maintenance path and updates available capabilities; selecting one must not manufacture a tool.
- Preserve item condition, contents, material provenance, brain identity and stored programs through movement and salvage. Material piles may stack only when their composition and relevant condition are compatible; quantities remain conserved.
- Limit access to worn/closed containers according to explicit rules. Concealment and searches can support roleplay later; visible UI alone never grants access.

The inventory interface for a station AI may list accessible containers and controlled bodies. Server ACLs and physical interaction capabilities govern transfers. Access to a storage device is distinct from possession, and knowledge of a container ID is insufficient to take its contents.

## Commands, persistence and profiling

Commands include pickup/drop, move, equip/unequip, select/swap hand, reserve/consume/return materials and applicable module operations. Resolve the authenticated principal's currently controlled body, permissions, reach, source/destination revisions, occupancy and capabilities at the fixed-tick boundary. Item tags and dimensions come from trusted definitions plus canonical contents, never player-provided claims.

Transfers commit all affected item/container/equipment/terrain/work-order records together. Failed commands leave ownership unchanged. Record idempotent receipts and reject stale revisions to prevent simultaneous pickups or retry duplication. Snapshots must validate unique item locations, containment acyclicity, pinned definitions, capacity rules and reservation ownership before restore. Death/reconnect/control changes and region transfers must preserve this ledger.

The system runs before consumers that require equipped capabilities, with explicit ordering once registered. External storage uses promises and later-tick validated commands. Inventory operations never wait for Discord, an LLM or persistence I/O. Profile command cost, item/container counts, traversed descendants, rejected transfers, reservation counts and transaction contention using bounded counters.

## Implementation stages

1. **Implemented:** body profile validation, hand-selection planning, slot-fit checks, three default configurations and regression checks.
2. **Partially implemented:** trusted item catalog, instance/location records and bounded containers with atomic revision-checked movement. Add material batches, authenticated ownership and retry receipt contracts alongside terrain transactions.
3. **Partially implemented:** combined equipment/active-hand records, carried/loaded mass and atomic equip/unequip/move operations. Add multi-slot grips and authenticated fixed-tick commands with receipts. Cover duplicate pickup, failed swaps, cancellation and runtime save recovery.
4. Add player inventory UI and local interactions over server snapshots, then persistent/networked ownership. Replace synthetic maintenance tool IDs with actual reachable owned tools.
5. Add configurable species/chassis anatomy, clothing/suit storage, cyborg modules and station-AI remote inventory access. Integrate construction reservations, salvage, corpse inventory, cloning and control transfer.

Windows Godot 4.7.2 import and focused profile checks passed locally. Checks cover all three fixtures, hand cycling, slot compatibility and capacity, detached records, invalid hands, duplicate slots and fractional quantities. Windows/Ubuntu CI includes the same script; Linux execution is not locally verified. Full inventory behavior remains a later integration gate.
