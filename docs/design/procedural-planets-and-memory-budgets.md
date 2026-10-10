# Procedural planets and bounded world streaming

## Direction and status

A future expansion should support complete explorable procedural planets, with the scale and variety requested by the owner through the No Man's Sky reference. Use independently authored generators, definitions and assets. Mars and the Moon remain the initial destinations; later generated planets, moons, asteroids and orbital salvage regions share the same generation/streaming contracts.

**Planned, not implemented:** current procedural habitat meshes and homogeneous terrain material records do not generate planets, stream terrain or support voxel excavation. A complete planet must be representable without allocating its complete surface, caves, collision or entity population in memory. Larger universe scale increases catalog/storage requirements; resident memory should primarily depend on active regions and configured detail budgets.

## Separate contracts and ownership

Names below describe proposed interfaces/components, not existing runtime classes.

| Contract | Responsibility |
| --- | --- |
| World/planet descriptor | Stable identity, seed, generator version, radius/frame, climate/geology/resource parameters |
| Coordinate/address service | Stable surface/volume chunk addresses, neighboring regions and local frame transforms |
| Generation provider | Pure bounded baseline sampling/generation from descriptor and chunk address |
| Terrain material owner | Canonical terrain quantities, edits, revisions and excavation/fill transactions |
| Region persistence provider | Durable edits, entities, tombstones and versioned checkpoints |
| Region residency manager | Interest sets, dependencies, pins, load/unload lifecycle and priorities |
| Memory admission controller | Shared byte budgets, reservations, peaks, eviction and overload policy |
| Terrain presentation provider | Disposable meshes, textures, LOD and GPU resources |
| Collision/query provider | Authoritative contact geometry and bounded detailed spatial queries |
| Entity population provider | Stable generated spawn identities and promotion into persistent entities |

Compose small providers behind typed contracts. Planet-specific geology or atmosphere changes data/providers, not inventory, blueprints, medical systems or ship logic. Keep baseline generation separate from authoritative mutation, physics and display. PHP catalog/persistence orchestration remains PSR-4/ReactPHP-based; Godot owns fixed-tick interaction and physics. External results use promises and later validated integration, never a blocked tick.

## Deterministic baseline plus durable changes

Use a seed, explicit algorithm/content versions and a stable chunk address to derive baseline content on demand. Do not use language-runtime hash functions or global mutable RNG order as world identity. Separate random streams for terrain, deposits, threats and decoration so adding a visual feature does not reshuffle ore. Specify reproducibility across Windows/Linux through golden fixtures and deliberate numerical rules; do not assume floating-point noise or native physics are automatically bit-identical.

The procedural baseline is a reproducible recipe, not a second mutable copy of the world. Persist player edits, resource depletion, built structures, moved/salvaged entities and deletion tombstones against it. Compact edits into bounded chunk snapshots when sparse deltas become larger, retaining revisions and material accounting. Every interactable generated region must define finite recoverable material quantities through the [terrain/material contract](materials-terrain-and-reconstruction.md).

Excavation, fill and salvage commit atomically with inventory/material owners and retry receipts. Unloading or regenerating a chunk cannot restore mined resources, resurrect a dismantled wreck, duplicate a moved item or remove a player's colony. Render LOD cannot change available resources or collision authority. A generated entity becomes explicitly persistent when modified, claimed, moved or otherwise needed by durable gameplay; its stable ID follows it across regions.

Pin generator/content versions in saves. A changed generator requires retaining the compatible provider or an explicit migration/rebake plan preserving modifications, seams, entity identity and matter. Unknown versions reject/quarantine rather than quietly generate a different occupied planet.

## Coordinates, detail and construction

Use hierarchical planet/local-frame addresses instead of planet-wide floating-point positions for fine interactions. A cube-sphere or equivalent face/quadtree layout is a candidate for surface addressing; volume chunks add depth/cave addresses. Select and codify the layout before saves depend on it. Client floating origins and local physics frames preserve precision; canonical identities and persisted addresses do not change when presentation recenters. Ships, colonies and surface bodies retain explicit frame relationships during travel.

Use a coarse global representation for orbital views and distant horizon detail, with higher-resolution chunks near players. A hybrid surface/volume implementation is a candidate: height-based or simplified meshes for distant representation, volumetric material/occupancy where digging, caves, overhangs and construction require it. The distant layer must derive from the same baseline plus committed edits. Do not constrain future excavation to a heightfield-only canonical model.

Generate shared borders from identical coordinates/rules, including material and collision samples. Neighbor dependencies, halo data and LOD transition geometry need explicit accounting. Define physical terrain resolution and edit bounds; full planetary scope does not imply atomic-scale terrain or a physics node per grain. Buildings and machines compose into terrain/assembly anchors without copying their contents into terrain cells.

## Memory admission and allocation

Define separate **CPU**, **GPU**, **generation temporary**, **physics**, **delta/cache** and **entity** accounting, plus an overall process headroom policy. Platform capability and administrator configuration choose budgets; client and dedicated-server budgets differ. Numeric shipping targets remain to be established on representative lower-memory hardware. The current small-scene benchmark is not evidence that procedural planets fit a given machine.

Each job reserves its estimated peak bytes before allocation, including baseline samples, decompression, neighbor halos, mesh output, collision construction, upload buffers and simultaneous old/new LOD resources. Bound input dimensions and maximum output sizes even after admission. Account shared resources once, while references/pins prevent premature eviction. Measure actual usage and reconcile reservations; estimates are not authoritative readings of total process or GPU memory.

For example, a 32³ sample block at eight bytes per sample is 256 KiB of raw sample data alone. It excludes metadata, language-container overhead, meshes, collision, textures, edit data and temporary copies. Use this kind of byte-based calculation rather than assuming a fixed chunk count implies a fixed memory footprint.

Prefer packed arrays, sparse material palettes, compact occupancy and pooled chunk buffers. Avoid per-cell dictionaries, scene nodes, individual collider objects and full deep copies of immutable generated arrays. Use instancing/batched visuals for decoration, with detailed colliders/entities promoted only where interactions need them. Compression can reduce storage/cache size but also needs bounded decode buffers and CPU work.

Residency uses priority plus LRU/clock-style eviction for disposable data. Active players, interaction jobs, assemblies, unsaved dirty chunks and necessary neighbor/support dependencies pin their authoritative regions. Budget admission must include the union of **all** players' interest sets: spreading players across planets can cost far more than clustering them. Enforce bounded active regions/concurrent jobs per host, with ownership routing between hosts as a later architecture step.

When budgets are tight, cancel speculative prefetch, evict unpinned caches, reduce distant presentation detail and defer new work. Required authoritative physics cannot silently become coarse or disappear beneath a player to meet budget. If minimum active state cannot fit, reject/defer region admission or travel with explicit feedback. Allocate a safety margin; account for resources awaiting GPU retirement rather than treating a queued free as immediately available memory.

## Streaming, asynchronous work and activation

Proposed region lifecycle: requested, admitted, loading/generating, validating, active, checkpointing, evictable and unloaded; cancellation/failure are explicit. Bound queued/in-flight jobs, decoded bytes, result buffers and main-thread activation work. Workers operate on immutable inputs and produce bounded data; scene/physics attachment and canonical owner registration occur through validated integration at safe engine/tick boundaries. Use Windows-compatible native work scheduling and service I/O, not PHP child processes.

Tag requests/results with world identity, generator version, region address, lifecycle generation and expected revision. Reject stale results after cancellation, edits, unload/reload or interest changes. A cancelled worker may still consume memory until it exits; retain its reservation until resources are actually released. Coalesce duplicate requests without letting a cancelled caller invalidate another active caller's work.

Travel, fast vehicles and orbital descent need bounded predictive prefetch and readiness gates. Do not allow an authoritative body to enter missing collision. Connected ships/colonies and cross-border pressure/power networks require dependency pins or an explicit dormant representation. Long-range tools use bounded server queries rather than forcing whole distant regions into full simulation.

## Dormancy, deletion and disk limits

[Seeded away missions](seeded-away-missions.md) are an explicitly disposable exception to persistent-region retention: each has a fresh instance ID, and final departure/completion permanently discards everything not atomically extracted. Player imports and constructions inside such a mission are subject to its declared loss rule. Persistent colony regions retain the durable rules below.

An unloaded region can remain durable while its presentation and detailed physics leave RAM. Choose explicit dormant rules per system: analytical resource/work progression where supported, coarse scheduled events, or paused simulation. Do not simulate millions of missed ticks synchronously on access. Preserve deterministic state, elapsed-time limits and interactions with neighboring active regions. Health, occupied assemblies and volatile pressure conditions need explicit policies before dormancy.

Deleting disposable baseline/cache data is safe when the baseline can regenerate. Deleting a persistent world region is a separate lifecycle operation with reference checks and campaign/admin policy. Unvisited generated regions and explicitly temporary unclaimed salvage instances may retire under their configured rules; claimed/modified regions, bodies, colonies and depletion records cannot vanish merely because no player is nearby. Persist instance retirement/tombstones so a retired salvage site does not respawn its matter accidentally.

Disk space is independently bounded. Durable changes need quotas, compaction, retention policy and capacity feedback; never solve RAM pressure by dropping saved edits. Unpersisted dirty chunks cannot evict. Storage acknowledgement failures/backpressure keep them pinned and may stop admitting new edits/travel. Generation seeds do not make player-created history free to store.

## Profiling and implementation stages

Expose bounded resident/peak bytes by category, pinned/dirty regions, admission failures, cache hit/eviction rates, queued/in-flight work, cancellation lag, generated samples, mesh/collision costs, activation time, seam dependencies, snapshot sizes and durable-storage backlog. Measure before allocation, during jobs and after unload/reload. Test high-water behavior, not just steady-state means.

1. **Descriptors and addresses:** versioned seed/provider contracts, local frames and stable chunk/entity IDs; independently authored golden fixtures on Windows/Linux.
2. **Budget/residency foundation:** byte reservations, bounded queues, priority/pins, cancellation and deterministic overload policy using synthetic chunks. Verify memory remains capped with requests beyond capacity.
3. **Small streamed surface:** one authored Mars/Moon test region with distant LOD, native collision and shared seams. Profile hot/cold generation, activation, traversal and repeated eviction.
4. **Editable volumetric terrain:** integrate material-backed excavation/fill, persistence deltas, construction anchors, mesh/collision updates and atomic cross-border edits. Check exact matter accounting after unload/reload.
5. **Full planetary streaming:** spherical addressing, orbital-to-surface transitions, precision, long-distance travel and bounded multi-player interest sets. Test poles/face seams, fast movement and widely separated players.
6. **Generated worlds and populations:** geology/resources, biomes, threats, caves and salvage with independent content streams and promoted persistent entities. Verify generator-version migration and depletion/tombstones.
7. **Dormancy and universe operations:** bounded catch-up, instance retirement, persistence backpressure and distributed region ownership where justified. Validate occupied ships/colonies cannot lose state or support on eviction.

Acceptance scenarios include deterministic regeneration, constant-budget traversal across a large planet, worst-case temporary allocation, pinned-region exhaustion, dirty-storage failure, cancelled/stale jobs, rapid LOD changes, seams, save upgrades, maximum-delta chunks and extended unload/reload soaks. Document hard limits and degradations for players/admins. All first-party providers remain MIT, and external creative assets must meet the project's existing intake policy.
