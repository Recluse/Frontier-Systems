# Physical floor wall construction

## Playable route

1. Extract and refine iron, run `craft.plate`, then materialize the printed plate into your inventory.
2. Open Construction, select the physical plate in the module/canister selector, enter floor coordinates and choose Wall along X or Wall along Z.
3. Build wall from selected physical plate. The entire owned plate becomes one 1 × 2 × 0.1 m panel at the selected floor position. Coordinates use the existing workbench-relative millimetre frame, snap to 100 mm and stay within ±100 m. Approach within the existing 1.5 m reach before submission.
4. Click the wall or select its stable ID in Construction. Remove selected wall and recover plate returns one physical plate to the acting crew's inventory. Either reachable conscious crew may dismantle shared panels. Recycle the recovered plate through the existing recycler for exactly 1 kg iron.

The current one-kilogram wall bill is prototype tuning inherited from the existing wall recipe, not an engineering density claim. Legacy Build/Deconstruct workstation buttons still control the separate aggregate display row; saved aggregate walls are not silently converted into spatial panels.

## Authority and persistence

Production owns `walls`, an immutable-pose map bounded to 32 panels. `SpatialWallConstruction` validates exact intents and prepares a detached candidate. Inventory consumes/creates the real plate using its existing factory, ownership and prospective capacity checks. These commit synchronously on the fixed-tick command boundary, with current production revision, authenticated world scope, consciousness, available hands and reach. Rejected commands leave all owners unchanged. Retained request receipts acknowledge retries without consuming another plate; competing removals produce one winner.

`wall_build` takes item_id, position, quarter_turn (0 or 1), expected_revision. `wall_remove` takes wall_id, expected_revision. Neither intent accepts material bills, owner identities or scene graphs. Building/removing a panel is manual and does not depend on workstation power. Removal needs an available physical-payload registry entry and carried capacity; a full receiver preserves the wall.

Production snapshots and observations emit v7. V1–v6 snapshots migrate to empty spatial-wall maps, retaining their exact existing material state. Each spatial wall contributes exactly 1,000,000 mg to the closed 25 kg fixture budget, separately from legacy wall mass and physical cargo. Stable IDs, floor coordinates and orientation survive JSON checkpoints. Restore rejects malformed/overlapping poses, missing wall matter and conflicts with registered occupants or fixtures. Older binaries cannot read v7 saves. New v7 system/observation schemas and the existing intent/world envelope schemas document this contract; v6 schemas remain shipped.

Placement rejects intersecting panels, registered bodies, the production workbench/deposits and conservative deployed-machine envelopes. Machine deployment also rejects intersection with existing walls. [Machine placement authority](machine-placement-authority-milestone.md) adds machine/body/fixture rejection and reserves expanded socket envelopes in both new machine and wall commands; trusted old saves retain the established restore checks. Touching panel faces are allowed. These are authoritative prototype keepouts; arbitrary scene geometry, wires, world trays, ship surfaces and terrain have no general placement adapter yet.

Inventory binds one synchronous read-only movement validator to Production's current wall records. Swept, expanded panel boxes reject horizontal/vertical tunnelling through thin walls before changing body positions or action epochs. Capsule-centre network poses use a 0.35 m horizontal / 0.9 m vertical conservative body bound; legacy floor anchors clamp their centre to 0.9 m. Existing client capsule physics and rejection reconciliation remain the presentation adapter. This does not establish general movement authority for the static habitat, machinery or terrain.

`ProceduralProductionPreview` creates one procedural mesh and StaticBody3D per observed panel, reuses unchanged bodies and retires removed colliders. Click selection targets stable IDs. Presentation never owns material or construction state. Production's profiling adds `spatial_walls`; there is no periodic construction work or service wait. Existing command-event logging handles these intents.

## Verification

`spatial_wall_runtime_test.gd` uses finite extracted/refined stock. It exercises exact plate consumption/recovery/recycling, independent orientations, fixture/body/wall/machinery overlap, ownership, out-of-reach and invalid-intent rejection, retained retries, both directions of machine/wall construction, swept collision, shared crew dismantling, v6 migration, forged checkpoint/missing matter rejection, read-only client validation and stable static colliders. CI discovers it on Windows and Linux.

The extended `first_playable_acceptance.gd` uses two real authenticated clients and temporary local save storage. It verifies private physical plate ownership, shared wall replication, disk checkpoint identity, a competing removal race and exactly one recovered plate. The graphical `first_playable_client_render_check.gd -- --walls` route constructs, selects, removes, recovers and rebuilds through the real client UI and checks the matching native physics collider. Its screenshot is [client.png](../../reports/spatial-walls/client.png).

Windows Godot 4.7.2 focused domain, cooperative checkpoint and graphical Forward+/D3D12 routes passed. All 56 final local Godot checks passed (import, startup and 54 discovered scripts), including corrected v1/v2 legacy fixtures. Schema JSON syntax, positive/negative wall-intent schema cases and the PHP Windows runtime policy passed. Remote CI on the pushed revision is the Linux/Windows integration/export gate. No Steam, Discord or Twitch live actions were performed.

## Next dependencies

Add richer placement feedback and collision-topology adapters before broader construction. Room sealing and atmosphere/gravity topology, staged tool work, damage/repair, ceilings/floors/doors, arbitrary surface/ship attachment and terrain excavation remain separate milestones. These panels do not seal or alter the existing pressure volumes.
