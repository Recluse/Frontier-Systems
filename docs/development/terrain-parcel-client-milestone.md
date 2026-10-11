# Authenticated terrain parcel client milestone

## Ownership and transport

`TerrainSimulationSystem` remains the canonical matter/claim owner. `TerrainMaterializeCommand` runs synchronously at the next authoritative fixed tick with the existing 16-attempt shared terrain ingress budget, independent principal claim ordinal (1-128), exact inventory revision and whole escrow transfer. This slice adds no owner transaction, persistence version, asynchronous callback, wear, Production consumer or terrain geometry.

`TerrainTransportCodec` constructs work or materialization commands and their distinct stable IDs. The invite-authenticated host accepts terrain `operation: materialize`, `request_number`, `request_id: terrain-materialize-<ordinal>` and an exact two-field payload: `transfer_id` and `expected_inventory_revision`. It binds the existing principal/session/world/region and grants on the host. A caller cannot provide matter amount, material/definition, provenance, destination or identity. Completions use existing per-principal/per-session pending routes and bounded status acknowledgements; no canonical receipt or other principal history is broadcast.

## Scoped observation and client reconciliation

Terrain observation v2 extends the existing finite cells and own live escrow with `next_materialize_request_number`, `materialize_sequence_exhausted`, `materialize_ready` and `materialize_message`. The next ordinal derives from this principal's retained associations; exhaustion includes the existing 128 lifetime association ceiling. Readiness calls the existing inventory voluntary capability/free-hand gate without terrain reach or a shovel. Capacity/revision checks still occur at command application. Old observation v1 remains decodable for work; it cannot allocate a fresh portable claim. Neither projection is accepted as owner state.

Client journal v2 supports materialization; legacy v1 work journals remain supported. The existing 8 KiB journal and single unresolved terrain intent are shared by work and claims. The original ordinal, operation, transfer and inventory revision are frozen before send; uncertainty prevents replacement by fresh or changed intent. A typed work command cannot masquerade as a claim. Journal versions are retained during reconciliation. Bootstrap already enables the scoped local journal, so no new storage/bootstrap mechanism is required.

The Terrain panel claims the selected whole own escrow using the observed independent ordinal and inventory revision. A pending claim disables fresh work and exposes the existing explicit original-intent retry action. Claim availability is independent of cell reach/shovel work readiness. After acknowledgement the adapter waits for a post-completion observation before fresh allocation. Claim status uses the existing completion signal; own inventory observation exposes the physical parcel.

Exact retry retains the original intent even when reconnect/restart observations show consumed escrow and the next ordinal. The canonical owner authenticates and resolves its retained association without repeating the physical transaction. Foreign claimant, stale/full inventory and changed retained retry reject atomically. Rejection consumes no successful ordinal, escrow permission or inventory revision. Checkpoint durability remains at the existing host checkpoint cadence; the journal is client uncertainty data, not a promise of host durability.

## Verification and limits

Base: merged PR #14 squash `209938740175f9b985742717ee181f8083f5fa6d`. Isolated branch `codex/terrain-parcel-client`; draft PR #18. The primary checkout and its gallery work are preserved.

Windows Godot 4.7.2 passed the focused two-client acceptance (import/startup/suite) and eight regression checks (import/startup plus checkpoint recovery, construction catalog, inventory runtime, terrain cooperative, terrain portable and terrain runtime). Final typed-command/journal changes are checked again by both affected transport suites. Initial failed native-versus-restored number-representation comparisons were diagnosed from bounded before/after evidence and corrected to compare JSON values; they are not passing acceptance evidence.

`terrain_parcel_client_test.gd` uses real loopback sockets, two distinct invite clients, fabricated finite-material shovels, manually advanced authoritative ticks and temporary host/client storage. It verifies scoped escrow, competing same-ordinal claim routing, typed intent denial, direct-host forged matter/identity/destination denials, unchanged foreign/stale/full-capacity failures, the actual Terrain button action, frozen changed-intent rejection, lost acknowledgement after a real commit, disk checkpoint and both-end restart, changed retained retry denial, same-adapter reconnect and one physical parcel per principal. The full-capacity fixture uses a separate restored world and trusted item-count ceiling; no external service or live player participates.

Four affected schema suites pass. The new guard validates five metaschemas, actual v2 observations/journals/claim payloads, explicit v1 work/view compatibility and 20 invalid shapes using a local registry and pinned development `jsonschema==4.23.0`. Existing controls, portable and terrain runtime guards validate their real emitted fixtures too. `git diff --check` passes.

The focused `Terrain parcel client contracts` workflow runs the same bounded runner and four schema guards on Windows and Ubuntu with pinned existing actions/Godot. Complete CI also discovers the new suite. Exact-head remote results are reported with the PR and Coordinator; queued or earlier runs are not final evidence.

Local runner:

    ./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames 'terrain_parcel_client_test.gd','terrain_cooperative_test.gd','terrain_portable_test.gd','terrain_runtime_test.gd','construction_catalog_test.gd','checkpoint_recovery_test.gd','inventory_runtime_test.gd'

Coordinator-reserved acceptance ports are 19241/19242; existing cooperative regression uses separately reserved 27853. Check listeners before binding and never stop another listener. All test storage is temporary and cleaned at suite completion. No graphical acceptance or image is claimed; no gallery/LFS artifact was created. No merge, integration-branch push, game release or deployment is authorized by this slice.
