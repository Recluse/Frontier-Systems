# Self inventory actions

## Implemented runtime and UI

The local inventory runtime now supports selecting/switching hands, equipping an owned item, unequipping to owned storage and moving an unequipped item between owned containers. The client demo exposes slot/storage pickers, active-hand controls and authoritative equipment labels. These are still the logical fixture bodies, independent of the walking preview character and production network sessions.

`InventoryDevelopmentCommand` uses operation `self`. Its exact payload contains `operation`, `item_id`, `source_container_id`, `destination_container_id`, `slot_id` and `expected_revision`. The runtime adds request ID and derives body ID from the authenticated local principal; clients cannot supply a different body in this payload.

`SharedInventoryCoordinator.apply_self()` uses the same sole shared owner and retained receipt collection as cross-body operations. It composes the existing `BodyInventoryState` rules over a detached candidate, then validates every body before committing the new shared ledger, equipment/active-hand metadata and receipt together.

## Allowed operation fields

All intents contain the fields below; inapplicable IDs must be empty strings.

| Operation | Required IDs |
| --- | --- |
| `switch_hand` | None |
| `select_hand` | Slot (must be a configured hand) |
| `equip` | Item, source container, destination equipment slot |
| `unequip` | Current slot, destination container |
| `move` | Item, source and destination containers |

Source/destination containers must have the selected body's physical root. Self operations cannot reach another body's storage or a world tray; those need their separate physical interaction rules. Slot compatibility, occupancy, loaded-container mass, aggregate carrying capacity, cycles and revision exhaustion retain the existing validation behavior. An item may occupy one slot in v1; two-handed grips and swapping occupied hands remain pending.

Only the acting body's revision increments, plus the shared owner revision. The embedded ledger revision changes only when the item changes container location. An identical retained request returns its original receipt; it cannot toggle the hand twice. Self fingerprints use a separate domain marker so request IDs cannot collide with a different retained cross-body intent. Original stale revisions reject after receipt eviction.

Self edits are immediate fixed-tick actions in this prototype. They can invalidate an unfinished interaction through its pinned body inventory revision. Timed suit changes, operational capability changes and material-consuming installation work are future systems, not consequences inferred from simply wearing an item.

## Own observation v2

`own_inventory_observation()` now emits version 2, adding body root ID, owned container IDs, configured hand/slot IDs, and all item instances under that body root, including nested storage. It still includes active hand, equipment bindings and derived total carried mass. Other bodies/world storage are excluded, and full shared snapshots, private notes/programs and permission records remain absent.

The prototype treats owned storage as open/accessible. Closure, hidden-item and tool/anatomy access rules need an authoritative access-path adapter before production use. `inventory-own-observation-v1.schema.json` remains the historical direct-root shape; the current response uses `inventory-own-observation-v2.schema.json`. The internal self intent schema is `shared-inventory-self-intent-v1.schema.json`.

## Client walkthrough

1. Use the inventory demo to search the target pouch and take its crowbar.
2. Switch active hand; the status shows the server-selected hand.
3. Choose `hand.right` in the slot picker and Equip selected owned item. The equipment label shows the existing crowbar bound to that slot.
4. Choose an owned storage destination and Unequip chosen slot to storage, or move an unbound item between owned containers.
5. Try a clothing slot with the crowbar: compatibility rejection preserves its actual location and bindings.

Selectors preserve stable IDs across refresh. A pending self command blocks repeated self submissions until its queue acknowledgement. Displayed lists and bindings come from observations; buttons only enqueue intents. The local actor initially has no storage bag, so its root is its only destination until it acquires container equipment. Unassigned root items remain a prototype carrying abstraction, not physical pockets.

## Verification and remaining work

Windows Godot 4.7.2 import, `self_inventory_runtime_test.gd` and the extended client panel test passed locally. Checks cover command-bound hand switching/retry, owned nested equipping, incompatible atomic rejection, stowing without mass loss, foreign-container rejection, own movement, equipment/receipt JSON recovery and actual UI callbacks. Existing inventory runtime, shared transfers and habitat checks also pass. Windows/Ubuntu CI includes the self suite; Linux and graphical input usability remain unverified locally.

[World tray pickup/drop](world-inventory-interactions.md) now supplements self operations through a separate registered physical-access path. Next: real body/physical-access producers and 3D placement, multi-slot grips, production transport and construction/material integration. Native player survival and suit effects still do not use these fixture loadouts.
