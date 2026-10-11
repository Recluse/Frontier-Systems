# Procedural world inventory preview

## Implemented client display

The habitat's client `SubViewport` now displays reachable world storage through `ProceduralWorldInventoryPreview`. The first-party tray/item proxies use native boxes, materials and labels. Backpack, pouch and crowbar definitions have simple distinct placeholder sizes/colors; unknown definitions use a generic cube. No imported models, textures, fonts or new dependencies are required.

The preview observes the actor's existing reachable-storage projection, never a complete world/ledger snapshot. Direct tray contents are shown; nested contents remain hidden. An empty reachable tray remains visible, and trays/items outside the logical actor's reach disappear when the observation changes. The [spatial model](inventory-spatial-state.md) now supports full integer 3D positions and an optional local capsule bridge.

This display is independent of the walking capsule's authority. The development runtime still uses one-dimensional logical body/tray positions. Preview coordinates map the fixture's logical millimetres into a display origin near the habitat at `(-6, 0, 2)` metres. The tray top is displayed 0.7 m above that local origin, and items use deterministic grid positions. These display offsets and placeholder dimensions are not canonical item transforms, physical packing or measured component geometry.

## Contract and allocation

World storage observations emit **v2**, adding a three-element integer `position_millimetres` vector to each visible root. The current simulation now produces full stored 3D vectors. `WorldStorageObservation` validates exact fields, unique container/item IDs, parent correspondence, integral bounded coordinates/metadata, distance bounds and a total of at most 512 items across at most 32 roots. The schema is `inventory-world-observation-v2.schema.json`; v1 remains historical.

`observe()` validates the whole record before replacing display state. Invalid observations preserve existing geometry. Identical container observations do not recreate nodes; changing only the shared inventory revision also avoids rebuilding. Source records are detached.

At most eight direct item proxies are allocated per visible root, for a maximum of 256 item meshes/pick areas across 32 roots. Crowded trays report remaining items through the label and full overlay list. Old proxy trees detach immediately and are freed through the scene lifecycle; stable selection survives only if its item remains displayed. More granular mesh reuse and client profiling remain future optimization work.

## Selection and collection

Ray-pickable `Area3D` proxies use collision layer 4 and mask 0, separate from the capsule's environment collision layer. The client viewport enables physics object picking. A left click highlights/selects a proxy by stable container/item IDs and selects the corresponding overlay row. A double-click requests pickup through the inventory panel.

The preview only emits IDs. The panel refreshes current reachable observations and requires the same container/item pair before queuing an `InventoryDevelopmentCommand`. The simulation then independently checks current registered storage, reach, source location, ownership/capacity and receipt rules. A stale proxy cannot bypass those checks; a pick event for an already removed proxy is ignored locally.

Preview pick areas are disposable interaction surfaces, not dynamic rigid bodies or player collision obstacles. Camera modes and display animation do not move inventory matter. Actual placement, throwing, per-item transforms, occlusion/capsule reach and construction/deconstruction remain authoritative systems to implement separately.

Bootstrap refreshes these observations at most ten times per second. The renderer is absent from headless world-host mode and sends no network/service requests. Current selection is client preference only, never part of world saves.

## Verification and limitations

Windows Godot 4.7.2 import and `world_inventory_preview_test.gd` passed. Checks cover actual v2 projection, direct-only loaded bag display, stable rebuild counts, invalid coordinate/duplicate rejection, read-only selection, queued double-click collection, removed proxy events and per-root allocation limits. Existing habitat/UI/world runtime checks also pass; Windows/Ubuntu CI includes the new script.

Tests invoke the picking signal handler and verify its command bridge headlessly. Native mouse ray picking, graphical composition, lighting/readability and Linux execution remain unverified locally. No claim of authoritative 3D player/item physics is made by this preview.

Next: real body/world spatial records and physical access adapters, item transforms/floor placement and authoritative pickup validation from player geometry, then construction and material transfer jobs.

## Selected proxy screen card

The selected identity uses one inventory-only CanvasLayer card instead of world-space text. It stays within its own viewport at the top right, with an opaque background and item/root/host-observed-distance lines. A camera-updated leader terminates at the actual selected proxy mesh; all card Controls ignore mouse events. This projection does not assert line of sight or authoritative geometry/reach. Native Area3D picking is unchanged.

Selection survives valid rebuilds only while the same displayed IDs remain, rebinding to the replacement mesh. Removed selection, hidden labels, absent camera, offscreen/behind-camera target or a viewport under 180 by 150 logical pixels suppress the card. Long IDs ellipsize; the overlay retains full IDs. The card allocates three text lines once and updates projection per presentation frame; no persisted state or schema changes. See [label milestone evidence](../development/inventory-label-readability-milestone.md).

## Tray context
Tray identity/instructions now use the shared [world context layout](world-context-labels.md). This bounds camera-aware text independently of proxy allocation and reserves the existing selected card. Geometry, native pick areas and the selected-item card remain unchanged.
