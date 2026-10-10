# Modular resource machinery

## Playable loop

The Construction tab adds a second path alongside the bootstrap workbench:

1. Extract ore with a handheld tool into a physical canister, carry it to the workbench, unload it and refine iron.
2. Hand-build a frame, controller, power connector and a work head. These are independently movable physical inventory items with conserved material bills.
3. Fit modules to a frame. Fit canister sockets, then insert canisters. A socket is an independently removable portable container; it can be fitted to any prototype frame regardless of which head is installed.
4. Deploy a frame containing a solar module, controller and power connector. Deploy processing equipment within reach, and connect owned cables directly or through a router frame.
5. Load refinery inputs into fitted canisters. Empty or matching canisters receive outputs; a consumed input canister can receive one of the outputs. Iron refining needs room for both iron and tailings. Regolith separation needs three output materials. No byproduct disappears.
6. Deploy an extractor beside a registered finite source. Run `extract.iron`, `extract.ice` or `extract.regolith` to fill a fitted canister. Remove and carry that canister to a refinery.
7. Fit a printhead to a frame. Printed parts consume refined material directly from fitted canisters and appear as physical output in the machine's storage. Retrieve them with Remove module / printed part. They are **not automatically fitted**.
8. Fit an expander to allow large parts/canisters and increase socket mounting capacity from three to six. Print replacement frames, modules, cables and resource canisters, then assemble further machines by hand.
9. Remove sockets and components, disconnect cables, pack equipment with nested contents, and recycle empty owned parts at the workbench. Manufactured canisters and existing handheld tools retain the existing equipment salvage path. `salvage.plate` also runs on a refinery head for canister-based material recycling.

All fitting and canister controls have independent selectors. Select the frame first, then the part/canister and relevant socket. Coordinates are metres relative to the workbench. Use current player position sets floor coordinates. Both cable endpoints must be within player reach when wiring; move between endpoints if necessary. The default cable length is five metres.

## Ownership and persistence

- `ProductionSimulationSystem` owns the workshop record, finite deposits, canister contents and material provenance. Production snapshots/observations are v6; v1–v5 snapshots migrate to an empty workshop without granting matter.
- `InventorySimulationSystem` owns the physical item/container graph and world root locations. Shell mass comes from production; nested inventory counts descendants once. Socket capacity accepts one resource canister. Full or overloaded assemblies fail before either owner commits.
- `MachineryWorkshop` supplies composition, restored-record validation and deterministic grid traversal. Operational requirements reuse `MachineFunctionRequirement` from the control subsystem. Physical fitting and functional availability are separate: a mixed frame can carry multiple work heads, and missing modules disable only their functions.
- `MachineryConstruction` accepts exact authenticated intents. It prepares a detached candidate graph and material state; commit is synchronous at command ingress with no service waits. Clients cannot submit bills, graph mutations, energy grants or canonical job records.
- `data/machinery/catalog.v1.json` pins prototype iron bills. A SHA-256 catalog fingerprint is saved; changing bills requires a deliberate migration. Bills, dimensions and rates are gameplay tuning values, not validated engineering measurements.
- A batch leaves feedstock in its canisters until completion. Each tick rechecks capabilities, loaded stock, output material/pressure capacity and prospective inventory mass. Missing modules/canisters/power or a full output pauses progress. Completion transfers every input/output in one transaction. Cancel keeps feedstock intact and does not refund spent energy. Restart requires explicit Resume.
- Multiple deployed machines have independent jobs. Command receipts retain the existing bounded retry contract. Processing completions and machinery commands use the existing event outbox; simulation never waits for DiscordPHP.

## Power and placement

Prototype solar exposure is fixed. Each operational solar frame produces 1,000 W into a 20 kJ local buffer, using integer remainder accounting at 60/72/90 Hz. Connected machines charge their own 20 kJ buffers over paths rated at 2,000 W per cable. Per-tick cable budgets are shared across consumers. Only solar frames and routers relay power. Sorting stable IDs makes traversal and allocation deterministic; a loaded grid may starve later IDs, which is a known scheduling limit. Local buffers permit brief work after isolation. Printing consumes buffered energy as an immediate prototype fabrication transaction; other recipes progress over their existing tick durations. Generator exposure, batteries, voltage/current, resistance, fuel and continuous print animation are later engineering improvements.

Settled presentation has one `StaticBody3D` per deployed frame, with module visuals parented to it. Cables are procedural visual meshes with no individual rigid bodies. Carrying a frame moves its nested parts and canisters through inventory as one assembly. Freeform placement supports bounded XYZ translation. Surface placement currently accepts the floor at Y=0. Server reach is enforced, but placement overlap/obstruction, arbitrary surface normals, rotation, ship-relative poses, cooperative live manipulation and rigid-body settling are **not yet implemented**. Do not describe this as completed freeform ship construction. Add those through a placement/assembly adapter without making presentation the canonical owner.

The prototype is bounded to 128 workshop parts, 20 deployed frames, 24 cables, 32 tracked canister payloads and existing inventory graph limits. The small fixture contains 25 kg total raw resources. A large installation must recycle/reuse shells rather than assume infinite resources. Solar energy is exogenous; material mass remains conserved.

## Verification and next work

`machinery_runtime_test.gd` exercises the finite collection/refining bootstrap, hand-built generator/printer/refinery/router/extractor, physical printing/recycling, socket capacity rejection, input removal pause, interrupted-job restore, grid isolation, powered extraction, forged provenance rejection and remote observation validation. It is included in Windows/Linux Godot CI. The extended two-client durable acceptance checks owner-private packed frames, unauthorized recycling rejection, shared deployed generator observation/control and disk checkpoint recovery. The graphical --machinery route builds and deploys a generator through the Construction tab. Profiling reports machine parts, deployed machines, cables and active machine batches.

Next extend graphical placement feedback and collision authority, add a visual guided construction walkthrough, and extend multiplayer acceptance to competing machine users and canister handoffs. Terrain excavation remains later than this Take On Mars style collection/processing loop. Ships, arbitrary hosted attachment, fuel generators and full automation require subsequent milestones.

### Local evidence

On Windows with Godot 4.7.2: all 48 workflow Godot scripts passed; the subsequently expanded two-client acceptance passed again; the graphical `--machinery` route assembled/deployed a generator and saved `reports/machinery/client.png`; and the final machine integration test passed including expansion gating and printing/salvaging a manufactured canister. Screenshot inspection confirmed the Construction tab and procedural settled equipment. Remote Linux/Windows CI must be checked on the pushed revision. No external Discord messages were sent.
