# Materials, terrain and reconstruction

## Requirement and implementation status

All player-interactable physical matter must support deconstruction into recoverable components and ultimately raw materials, with construction paths back to functional objects. This includes asteroids, deposits, space debris, ships, stations, machines, tools and planetary terrain. Dirt is transferable material for terrain modification, crafting and hydroponic substrate. Access, tools, time, energy and environmental conditions determine whether a particular operation can presently be performed.

The current implementation provides trusted material definitions, a bounded revision catalog, homogeneous terrain records and pure excavation/fill plans. Fixtures cover dirt and untreated Martian/lunar regolith. It does **not** yet implement inventory transactions, runtime terrain editing, universal object deconstruction, recipes, fabrication or plant growth. The existing procedural habitat geometry is a client preview, not constructed world matter. Current machine-board spares are development fixtures, not material-backed fabrication.

## Matter and component ownership

Every physical entity definition must declare a composition manifest and its construction/deconstruction routes before entering gameplay. Every terrain deposit must declare material identity, quantity and generation provenance. A generic material-bearing component should supply these contracts to entity types rather than requiring a separate mining system for every object.

Keep these concerns separate:

| Contract | Responsibility |
| --- | --- |
| Material definition | Pinned identity, units and allowed material uses |
| Material batch | Owned quantity, composition, condition and provenance |
| Component manifest | Stable installed parts, bulk matter and attached contents |
| Blueprint | Arrangement, connections, part requirements and construction stages |
| Recipe | Explicit material conversion, tools, energy, inputs, outputs and byproducts |
| Capability | What fitted, powered, intact equipment can currently do |
| Work order | Actor, target revisions, reservations, progress and cancellation |

Blueprints must describe physical construction separately from operating requirements. An unpowered door can still contain a recoverable motor and permit mechanical operation. Missing optional equipment reduces capabilities without automatically deleting the remaining object. Material identity alone does not grant an executable handler or permission.

### Dismantling, recycling and rebuilding

1. Dismantling releases stable installed components with their actual condition and contents. It must not mint pristine replacement parts from damaged equipment.
2. Recycling a released component uses an explicit recipe to recover its constituent materials. Recursively dismantle composites until their accounted matter is accessible as parts or raw batches.
3. Refining and combining materials use separate recipes, with all consumed material and produced waste recorded.
4. Fabrication consumes reserved batches to produce parts; assembly connects those parts according to a blueprint. Repair can consume materials while preserving the identity of a salvageable part.

Recovery inefficiency produces accounted waste, slag, dust or other outputs; it does not silently delete mass. Trapped liquids and gases must move into their owning fluid domains or explicit release records. Destruction may change form and condition while keeping matter recoverable where physically appropriate. Terrain and objects need not be recoverable with bare hands or without suitable equipment.

Brains, player identity, lawsets, permissions and stored programs require their own ownership rules. Dismantling a cyborg preserves its brain/data-bearing components through those rules. Recreating its material bill must not duplicate a player identity, authority credentials or program access rights.

## Terrain and dirt

Canonical terrain stores matter independently of mesh or collision representation. Digging transfers material from terrain into an inventory, collection container or accounted loose-material entity. Filling consumes owned material and changes terrain. Clients render derived geometry; editing a mesh never authorizes a terrain change.

The initial cell model is homogeneous and pinned to one material revision. Filling with a different material is rejected. Layered cells, mixtures, compaction, moisture and contamination need explicit future records and conversion operations; do not approximate them by silently relabeling a cell. Dirt can fill terrain, enter defined crafting recipes, or be loaded as hydroponic substrate. Regolith conditioning can produce growing medium through a future recipe with explicit inputs and outputs. The use tag alone does not implement a craft or guarantee crop suitability.

Plant production must account for water, nutrients and other modeled inputs. Substrate is not an unlimited source of crop mass. Soil treatment, moisture, contamination and crop requirements belong in the later growing-medium model.

Asteroids use the same material transfer rules as planetary deposits. Ship hulls and artificial structures use component manifests rather than pretending every structure is terrain. Both feed the same inventory and conversion contracts.

### Implemented API and units

- `MaterialDefinition.from_record()` validates an exact versioned record. `MaterialCatalog` stores detached definitions by ID and revision, rejects duplicates, and holds at most 4,096 revisions.
- `TerrainMaterialState.from_record()` requires a trusted catalog and a material registered for `terrain.fill`.
- `plan_excavation()` and `plan_fill()` return detached `ServiceResult` plans with before/after records, expected source revision, inventory direction and transferred mass. They never mutate terrain or inventory.
- Canonical mass is integer **milligrams**; 1,000,000 mg = 1 kg. Records cap quantities/revisions at 9,007,199,254,740,990 for exact JSON interchange. Fractional mass is rejected. Transfers require positive amounts and reject exhaustion/overflow.
- `volume_m3()` derives volume from mass and the pinned prototype bulk density. Fixture densities are tuning placeholders, not measurements or a geological model. Spatial capacity and shape constraints are not implemented.

The definition, state and transfer-plan schemas are under `docs/schema/`. Schema validation expresses record shape and operation/direction correspondence; trusted code must additionally enforce catalog lookup, mass arithmetic and revision correspondence. Current use IDs are `terrain.fill`, `crafting.feedstock` and `hydroponics.substrate`.

## Authoritative transactions and persistence

The future material/terrain simulation owner must recompute plans from canonical state after validating authenticated intent. A client or LLM submits a target and requested operation/quantity, never an authoritative `after` record, yield or composition manifest.

At a fixed-tick boundary, validate reach, tools, capabilities, permissions, target revisions, destination capacity and reserved inputs. Commit terrain, inventory, component ownership and the request receipt together. A stale source or failed reservation changes none of them. Overlapping excavation requests must not both receive the same source matter. Use idempotent receipts and revision checks across retries and recovery.

Long operations reserve inputs and progress through bounded work orders. Cancellation returns unconsumed reservations; already completed stages retain their real outputs. Atomic checkpoints must include the material owners and work orders together. External persistence acknowledgements use promises and validated later-tick commands; ticks never wait on storage, Discord or LLMs.

Generated matter, admin spawns, imports, exports and disposal need explicit provenance/source/sink records. Unloading a region must retain its depletion and modification records. Regenerating an asteroid from its seed must overlay that ledger rather than replenishing mined deposits. Cleanup of an accessed salvage instance must account for remaining matter and owned objects before deleting its state. Mesh caches may be discarded and rebuilt from canonical data.

The first model conserves transferred bulk mass. Chemical/element balances, gas release, heterogeneous terrain and thermal effects remain future work and need their own documented assumptions.

## Staged implementation tasks

1. **Implemented:** material catalog, dirt/regolith fixtures, terrain state and conservation plans, JSON contracts and focused regression checks.
2. Add material batches, owned inventories, capacities, revisioned terrain storage and atomic transfer commands. Persist receipts and reservations with their affected owners. Verify retry, concurrent dig, cancellation and restart conservation.
3. Add chunked terrain presentation, server-validated tool/reach operations, bounded mesh/collision rebuild jobs and client replication. Profile dirty cells, rebuild time, transferred mass, contention and queue limits.
4. Add composition manifests, blueprint bills of materials and staged construction work orders. Migrate development-only machine spares to audited fixture sources and actual owned parts.
5. Implement recursive dismantling, material recycling, refining and fabrication. Verify damaged salvage, contents, byproducts, partial construction and identity preservation.
6. Add soil conditioning, growing-medium batches, explicit crafting recipes and hydroponic consumption. Then integrate asteroid depletion, salvage-instance cleanup and procedural region recovery.

All stages share the material model and authoritative command path, including automation and LLM-controlled workers. Providers may propose work orders; they cannot create matter or bypass construction requirements.

## Checks

`tests/godot/terrain_material_contracts_test.gd` exercises default fixture import, detached catalog reads, derived volume, excavation/fill conservation, unchanged source state, JSON recovery, unknown/mismatched materials, invalid quantities, overflow and revision exhaustion. Windows Godot 4.7.2 import and the focused script passed locally. Windows/Ubuntu CI includes the script; Linux execution remains unverified locally.
