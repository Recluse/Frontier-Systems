# Inventory 3D spatial state and local capsule bridge

## Implemented development model

Logical inventory bodies and registered world storage now use bounded three-dimensional integer millimetre positions. Body-to-body interaction policy and world storage visibility/pickup/drop share `InventorySpatialMath`. This replaces the earlier x-axis-only reach calculations without changing material/item ownership.

Each position has exactly three integral coordinates within ±10,000,000 mm per axis. Normalization accepts integral JSON floats but stores integers. Squared distance is summed in int64, with a maximum of 1,200,000,000,000,000 inside the supported region bounds. Euclidean distance rounds **up** to the next integer millimetre; an actual separation just greater than 1,500 mm cannot be accepted by rounding down. This avoids canonical reach calculations in Godot `Vector3` float32 space.

Coordinates currently represent a body reference point and storage reference point, not anatomy-specific hands, collision surfaces or swept motion. World storage still requires its registered accessibility flag. Walls/occlusion, container closures, floor placement, dynamic bodies and real reach capabilities remain separate authoritative work.

## Commands and recovery

Local development `move_to` accepts an exact `position_millimetres` array. It validates bounds, changes the logical body position and increments the action epoch, preserving resistance/interaction cancellation rules. The existing `move` command remains compatible: its bounded x coordinate changes only x and preserves current y/z.

Inventory snapshots now emit **v3**, persisting position vectors on logical bodies and world location records. V1/v2 snapshots remain accepted: x-only coordinates migrate to `[x, 0, 0]`, preserving IDs, quantities, equipment, receipts, original job counters and paused recovery. Worlds missing inventory still migrate to an empty v3 system. Migration creates no new matter. The current schema is `inventory-system-state-v3.schema.json`; prior schemas remain historical.

World observation v2 already carries position vectors, so it now emits the full stored 3D position rather than synthesizing y/z zero. Preview geometry keeps its existing display-origin mapping and disposable placeholder offsets.

## Opt-in local walker bridge

The client inventory panel now offers **Link inventory actor to walker (local development)**. It defaults off and is not saved as a world setting. `LocalInventoryBodyAdapter` samples an active local capsule at most ten times per second, transforms its position relative to the world-preview display origin, rounds to millimetres and queues a development `move_to` command for the bound fixture actor.

The adapter admits one outstanding pose and records its last accepted position only after command acknowledgement. Stationary poses enqueue nothing, avoiding invented action epochs. Nonfinite/out-of-region poses reject. Switching to inspection mode stops samples; disabling the link stops new commands. An already queued update may still apply at the next tick. The logical body retains its last accepted position when the link stops; restarting the client does not restore the local capsule from that saved pose.

The adapter never writes canonical body records from frame callbacks. While disabled, camera/character movement remains read-only with respect to world snapshots. When enabled, capsule pose is an explicit development input; it is **not** authoritative networked movement, collision verification, anti-cheat or a server physics system. Existing debug pose controls can still change the logical body; a fresh capsule pose sample can change it again.

Manual use: choose first- or third-person navigation, enable the checkbox, and walk toward/away from the tray. Reachable world storage and scoped interactions now respond to all three position axes at subsequent fixed ticks. The target fixture body remains logically positioned independently until given its own server-owned adapter.

## Verification and next work

Windows Godot 4.7.2 import, `inventory_spatial_test.gd` and `local_inventory_body_adapter_test.gd` passed. Spatial checks cover exact/diagonal reach boundaries, vertical separation, maximum-coordinate arithmetic, invalid vectors, observation filtering, atomic invalid-save rejection and v2 migration. Bridge checks cover disabled/inactive gating, one pending command, fixed-tick pose updates, stationary suppression, 3D access loss and disabling. Existing world inventory, inventory runtime and habitat tests pass; Windows/Ubuntu CI includes both suites.

Linux and native graphical/input behavior remain unverified locally. Next: server-owned body physics and movement/control-session contracts, occlusion/access-path validation and actual item placements. The current capsule is still a client preview with an optional debug bridge; native survival and network player authority are not implemented.
