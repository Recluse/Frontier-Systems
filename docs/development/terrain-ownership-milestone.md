# Finite terrain ownership milestone

## Scope and ownership

TerrainMaterialOwner is the independent canonical owner of commissioned homogeneous cells and the finite loose transfers excavated from them. It composes TerrainMaterialState and reuses its pure excavation/fill plans. It does not register with WorldRuntime or change inventory, production, shared world schemas, mesh/collision caches or streaming.

The trusted caller commissions one bounded owner with create(owner_id, catalog, seeds). Each seed supplies a revision-zero terrain state, finite capacity in integer milligrams, a unique origin ID and a pinned generation revision. The material ID/revision must resolve in the trusted MaterialCatalog for terrain.fill. Empty seeds are permitted. Commissioning is a source event and may occur only once for a new owner: load existing worlds through from_record instead. Origin records retain initial mass even after depletion, and empty cells retain their stable identities. There is no delete, reseed, import or mint operation on a running owner.

IDs for cells, origins and owners are stable nonblank strings up to 128 characters. Request and loose-transfer IDs are derived from a successful owner sequence and are scoped by owner_id; use the pair for any future external reference. A caller cannot supply authoritative output records or yields.

## Commands, cadence and failure

Call plan(intent) for a detached pure preview and commit(intent) synchronously on the authoritative fixed-tick boundary. There is no autonomous tick work, wall-clock dependence, asynchronous callback, I/O or process launch. The caller serializes commands and budgets calls per tick; this owner supplies domain validation rather than player permissions. Commit recomputes the plan from current private state. Altering a returned preview, receipt or checkpoint cannot change the owner.

Intents have exact fields: sequence, request_id, cell_id, expected_cell_revision, operation, amount_milligrams and transfer_id. A new success must use last_sequence + 1 and request_id terrain-request-<sequence>. Rejections do not consume the sequence. Every successful command changes exactly one cell revision, so the sum of cell revisions equals last_sequence.

Excavation requires an empty transfer_id, subtracts available mass and creates terrain-transfer-<sequence> inside this owner. Filling supplies an existing loose transfer ID and consumes positive mass from it, possibly leaving a partial transfer. Full consumption removes the transfer. Fill rejects different material IDs/revisions, insufficient loose matter or commissioned capacity overflow. Capacity is a mass ceiling, not a geometry/compaction model; density remains the existing prototype density contract.

Each cell and transfer partitions mass into positive integer provenance parcels keyed by origin ID. Filling retains origins even across cells. Excavation splits parcels in sorted origin-ID order, independent of dictionary insertion order. Both cell mass and per-origin totals are conserved. Integer milligrams and the complete commissioned total are bounded by 9,007,199,254,740,990 for exact JSON interchange. Zero quantity, fractional quantity, overflow, unknown identity, stale revision, skipped sequence, exhausted revision, absent fill stock and collection backpressure return ServiceResult failure. Failed commands leave all canonical state and receipts unchanged; only optional diagnostic counters change.

Successful sequences serialize overlapping digs. A second dig cannot claim an earlier cell revision. Rejecting a stale intent permits a newly validated intent at the still-unused next sequence; authentication and fair command scheduling belong to the future runtime bridge.

## Retry, persistence and budgets

Snapshot version 1 retains cells, origin budgets, loose transfers, last_sequence and the last 64 complete successful receipts. Exact retained retries return the original detached receipt without changing state or creating matter, even after JSON restart. Changed intent at a retained sequence rejects. A sequence at or below last_sequence outside the retained tail rejects forever. Because request IDs derive from sequence, an expired request ID cannot be reassigned to fresh work. The bridge must preserve the originally allocated sequence across retries; refreshing it after uncertainty would represent a new operation.

Save to_record() as a complete atomic checkpoint. Restore validates exact fields, finite integers, catalog/material identity, stable map/state correspondence, commissioned capacities, generated transfer IDs, per-container parcel sums, per-origin conservation and cell revision totals. It normalizes integer-valued JSON numbers, rewinds the complete ordered retained receipt tail, recomputes every pure terrain plan, then replays commands and compares exact receipts and resulting canonical state. Contradictory receipt outputs or provenance reject. from_record returns a new validated owner; failure never mutates an existing owner. Profiling counters reset on restore.

Checkpoint validation establishes internal consistency, not storage authenticity. The future persistence boundary must supply trusted atomic snapshots and catalog revisions; a rewritten generation budget is not an authorized source event. Recovery does not consult a terrain seed or regenerate mined material. Unloading a future region must preserve this entire owner checkpoint or an equivalent durable depletion ledger.

Bounds are 128 cells, 128 origins, 256 live transfers, 16 provenance parcels per cell/transfer and 64 retained receipts. Origins/cells remain allocated after depletion. A full live-transfer budget rejects further digging; consuming a transfer frees its slot. Filling that would introduce a seventeenth provenance origin rejects without consuming stock. Plan/commit copies only bounded owner records and performs one bounded provenance split; restore additionally validates and replays at most 64 receipts. Saved state contains no unbounded event log or presentation data. Its maximum serialized size depends on the bounded IDs and collections; persistence must also apply an ingress byte/depth limit before JSON decoding.

profiling_signals() exposes saturating commits, retries and rejections, plus cell/transfer/receipt counts and last_sequence. These counters are observational and never drive behavior. Measure tick duration in the calling simulation profiler; no runtime profiling numbers are claimed here.

The versioned JSON contracts are terrain-owner-seed-v1.schema.json, terrain-owner-intent-v1.schema.json and terrain-material-owner-v1.schema.json under docs/schema. They reuse existing material-state/plan schemas. Schema shape checks cannot enforce all arithmetic, replay, catalog or identity relationships; from_record and commit remain authoritative.

## Verification and next dependency

The repository bounded runner passed Windows Godot 4.7.2 import, startup, terrain_material_contracts_test.gd and terrain_material_owner_test.gd. The new focused suite verifies exact pure-plan reuse, detached previews/receipts, finite excavation, partial cross-cell fill, provenance splitting, retained retries, stale/changed/expired commands, unchanged rejections, complete depletion, JSON recovery, reconstruction, corrupted snapshots and bounded receipt/transfer/provenance backpressure.

Run from the worktree with:

    ./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames 'terrain_material_owner_test.gd','terrain_material_contracts_test.gd' -TestTimeoutSeconds 120

CI already discovers the new test on Windows and Ubuntu. Local Linux execution, graphical terrain editing and live player/inventory transfers remain unverified and outside this milestone. No first-party PHP runtime or external service boundary changed.

The next bounded dependency is an atomic live bridge: validated server commands must enforce reach, tools, capabilities and permissions, reserve/check inventory capacity and inputs, and checkpoint terrain, inventory ownership, work orders and request receipts together. It must define sequence allocation/retry behavior and inventory-transfer provenance before moving these loose transfers into another domain. External callbacks submit validated later-tick commands. Sustained digging, cancellation, tool wear, mesh rebuilding and procedural planet unload/recovery need their own contracts and acceptance. Production bulk matter must not be copied into this owner.
