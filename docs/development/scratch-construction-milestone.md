# Construction from raw resources: current content coverage

## Playable paths

Every current inventory item has a trusted construction route or a functional fabricated equivalent of its legacy starter definition. This is coverage of the current physical item catalog, not a claim that all planned world systems can already be built.

| Output | Bill | Build and recover |
| --- | --- | --- |
| Resource canister | 1 kg iron | Hand assembly, workbench fabrication, expanded printer/autolathe; salvage shell and cargo |
| Resource extractor | 1.5 kg iron | Same paths; independent frame, head and drive |
| Modular crowbar | 2 kg iron | Same paths; independent 1.2 kg shaft and 0.8 kg prying head |
| Modular shovel | 1.3 kg iron | Same paths; independent 0.4 kg handle and 0.9 kg head |
| Rigid storage backpack | 1 kg iron | Same paths; real portable storage, 15 kg / 18 L / 16 items, wearable on back |
| Rigid tool pouch | 0.5 kg iron | Same paths; real portable storage, 5 kg / 1.5 L / 4 items |
| All 12 machine parts | Catalog iron bill | Hand assembly, printer and autolathe; fit frame/modules/sockets, deploy, wire and recover |
| Plate | 1 kg iron | Existing timed plate recipe, physical materialization and recycling |
| All seven tool-component types | Trusted component mass | Existing part factory, fit/detach/repair/recycle; includes new handle and lever-shaft designs |

The backpack and pouch are prototype rigid metal storage assemblies. This does not introduce a textile chemistry or pretend to simulate fabric manufacture. Crowbars and shovels use the existing capability owner; construction does not add a new excavation or airlock mechanic.

In Construction, select the desired design and **Hand-build selected part / equipment** near the workbench. This debits all trusted raw material requirements without printer energy. Refine those resources first through the existing mining/canister loop. The prototype still supplies workbench/refinery services and starter gear; a zero-equipment survival bootstrap is a separate milestone. No command creates matter for free.

Deployed factories consume canister stock (printer) or solid hopper stock (autolathe), require controller/power/head, adequate grid-buffer energy and an expander for equipment. New designs are populated from server blueprint observations, including their actual material requirements. Printed storage owns a real child container rather than a UI-only capacity value.

Empty constructed storage before salvage. Its empty shell is recycled through equipment salvage; nested items are never deleted or converted into duplicate shell material. Packing machinery preserves nested items and hopper stock. Existing ownership, reach, revisions, retained receipts and inventory capacities apply to every construction path.

## Contracts and compatibility

- Production owns conserved shell bills and cargo; Inventory owns physical items, storage and equipment binding. ToolSimulationSystem owns condition and replaceable tool parts. No additional simulation owner or asynchronous mutation path was introduced.
- Equipment blueprint v1 gains additive definitions; existing definitions and their fingerprints stay unchanged. Factory catalog validation now permits trusted storage definitions because both physical creation paths already construct and validate child storage.
- Tool binding catalog v2 preserves all v1 bindings and introduces fabricated crowbars/shovels. Original snapshot fingerprints are migrated to current bindings on restore. The original v1 file remains shipped. Existing snapshot record shapes are unchanged.
- `data/production/construction-coverage.v1.json` identifies legacy fixture equivalents and the two special item factories. `construction_catalog_test.gd` checks all inventory definitions and component types against the real catalogs. New definitions must have an actual path instead of silently becoming spawn-only items.
- Existing production counters expose equipment count, physical component count and conserved stock; tool counters expose assemblies/parts. Logging uses existing command events and remains outside simulation waits.

## Verification

`construction_catalog_test.gd` checks 25 inventory definitions, legacy storage/volume/capability equivalence and all seven tool-component types. `scratch_construction_runtime_test.gd` uses finite ore to hand-build all six equipment designs with printer power disabled, verifies exact shell mass, real nested storage, rejection of occupied-container salvage, material recovery, tool capabilities, legacy migration and restart. It also constructs a solar-powered printer, prints portable storage and verifies dynamic design UI coverage. Tests use local fixtures and temporary acceptance storage; no live Discord, Twitch or LLM service is required.

## Remaining world construction adapters

| System | Current status | Required next step |
| --- | --- | --- |
| Machines and power grid | Physical constructable frames, modules, sockets, solar, extractor, refinery, printer, autolathe, router and cables | Surface/ship attachment adapters and more generator designs |
| Portable gear | Current item catalog covered | Add clothing/EVA/tanks as real item definitions with recipes and atmosphere ports |
| Walls | Legacy conserved wall mass recipe | Spatial physical blueprint placement, removal and connection to room topology |
| Airlocks, doors, controls | Functional simulation fixtures/contracts | Physical module bills, placeable host identity, construction/disassembly transactions |
| Habitat atmosphere/gravity | Simulation owners/policies | Constructable pressure vessels, pipes, pumps, gravity equipment and owner adapters |
| Terrain/dirt | Material/deconstruction contracts | Editable terrain owner, excavation/deposition and conservation adapters |
| Ships/colonies and biology | Planned extended systems | Build graph/topology, component attachment, occupants and domain-specific recipes |

Implement each adapter through a trusted blueprint and the relevant owner. Do not clone a fixture node and grant its contents as construction. Durable state must preserve installed components, stored matter and partially functional wrecks. Timed fabrication queues require an explicit reservation contract before expanding the current atomic one-command factories.
