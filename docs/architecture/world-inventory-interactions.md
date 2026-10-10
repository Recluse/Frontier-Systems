# World inventory pickup and drop

## Implemented prototype

The local inventory slice can now transfer items between a logical body and registered world storage. Its initial world tray is the existing `world.tray-1` ledger root at x=0 mm, accessible within 1,500 mm. This is a storage-location prototype, not arbitrary terrain/world placement or a physical dropped-item entity.

`SharedInventoryCoordinator.apply_world()` handles atomic pickup/drop. The inventory runtime derives the acting body from its development principal, verifies that the world root is registered/reachable/accessible, and enqueues effects through the existing fixed-tick command path. Other-body inventory cannot be relabeled as world storage.

## Operation rules

The internal intent contains request/body IDs, operation, item ID, world root ID, applicable owned destination/equipment slot and expected shared revision. Runtime payloads omit request/body IDs, which are server-derived.

- **Drop:** resolve the existing item's actual location and require ancestry under the acting body. Move it into the selected world root and clear its equipment binding if fitted. The active-hand selection remains unchanged. No destination or slot override is accepted.
- **Pickup:** require the item directly in the selected world root. Move it into a container under the actor's body. An optional equipment slot requires the direct body root, a free slot and compatible loaded-item dimensions.
- Containers retain their hosted storage links, contents, item condition and stable IDs. Dropping/picking up a bag moves its whole subtree; pickup does not separately mint contents.
- Validate capacities, cycles, loaded equipment fit and all bodies against the candidate before committing ownership, equipment, revisions and receipt together. Failures preserve the original state.

Cross-body, self and world operations now share `_commit_candidate()` for revision advancement, bounded receipt retention, full validation and replacement. World fingerprints use their own domain marker. Identical retained requests return their receipt without another effect; changed intent or stale revision rejects. The runtime still checks current reach/access before delivery to the coordinator, even for an acknowledgement retry.

These immediate prototype commands do not model dropping a sealed suit's physical consequences, throwing, gravity, collision, item stacking or timed manipulation. Operational equipment/survival effects remain separate systems.

## Observation and UI

`world_inventory_observation(context)` reports registered accessible roots within logical reach, their integer distance and direct item instances only. Nested contents and other bodies' storage are not revealed. The client inventory section has a world-root picker/list plus Drop, Pickup and Pickup into chosen equipment slot controls. Actions queue intents; the simulation rechecks reach/location/capacity at application time.

The tray starts empty. Take the fixture crowbar from the other body, then drop it into the tray and pick it up. The chosen equipment slot determines fitted pickup; incompatible/occupied slots reject. The underlying tests also drop and collect the fully loaded backpack, proving subtree conservation.

World views refresh with the existing ten-Hz panel observations. The system uses logical one-dimensional positions, not the walking capsule; occlusion, real item transforms, closed containers and physics-backed player access are future adapters.

## Snapshot v2 and migration

Inventory-system snapshots now emit v2 and persist up to 32 world location records: existing root ID, bounded x coordinate and accessibility flag. Decode requires unique root IDs, actual ledger-root existence, no body-root claims and exact field types. No snapshot location record can create an item/container.

V1 inventory snapshots remain accepted. They receive default location metadata for the pre-existing non-body `world.tray-1` root only if it exists. Migration creates no matter, root or body. Worlds lacking inventory still migrate to an empty v2 system without world locations. V1 schemas remain historical.

Current contracts are `inventory-system-state-v2.schema.json`, `shared-inventory-world-intent-v1.schema.json` and `inventory-world-observation-v2.schema.json`. Observation v2 adds bounded display-position vectors for the [procedural 3D preview](procedural-world-inventory-preview.md); observation v1 remains historical. Physical registration/reach and ledger/equipment invariants remain authoritative code checks beyond schema shape.

## Verification and next steps

Windows Godot 4.7.2 import and `world_inventory_runtime_test.gd` passed. Checks cover loaded equipped bag drop, direct-only world observation, retained retries, competing pickup, subtree mass/ownership/equipment preservation, foreign-root rejection, reach filtering/rejection, JSON restore and v1 migration without spawning. The client panel test covers actual drop/pickup callbacks and fitted pickup. Existing self, runtime, shared-transfer and habitat checks also pass; Windows/Ubuntu CI includes the world suite.

Linux and graphical input behavior remain locally unverified. Next: real 3D body/world item locations and physical access adapters, floor placement/throwing, multi-slot grips and material construction jobs. Production networking/authentication still does not expose these local fixture commands.
