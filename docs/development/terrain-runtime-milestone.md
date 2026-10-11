# Terrain runtime milestone

## Owner and finite commissioning

`TerrainSimulationSystem` registers as `terrain` in `WorldRuntime`, composing the existing canonical `TerrainMaterialOwner`. The bridge owns request allocation and permission metadata; it never duplicates matter into inventory or production. Its pinned dirt catalog fingerprint and fixture identities are validated on recovery.

New worlds commission **2,000,000 mg (2 kg)** of `material.dirt` revision 1, generation revision 1, in `terrain.dirt.source`. `terrain.dirt.fill` starts empty. Both cells have a 2 kg ceiling; their stable millimetre positions are `[0,0,1000]` and `[500,0,1000]`. Origins are the cell IDs plus `.generation`. This is an independent explicit generation budget, outside Production's closed 25 kg fixture. Excavation creates terrain-owned transfer escrow, never a physical inventory item. Filling consumes only this owner's escrow and retains provenance.

A legacy v1 world envelope without `systems.terrain` migrates to the same identities/positions with **zero initial mass and zero capacity**. Present terrain records must validate; corruption does not reset or recommission cells. Depleted cells and their original source budgets persist. Loading always restores the owner record, and never consults a seed for replacement matter.

## Commands and capabilities

`TerrainCommand` is a typed `SimulationCommand` executed by the existing bounded server queue at tick start. The server binds `AuthenticatedCommandContext`; clients cannot supply authoritative records, principals, grants, tool IDs, positions, output yields or owner sequence numbers. No network/UI endpoint is added in this slice. A grant named `terrain.operate`, the correct world/region and an existing inventory principal binding are required, including for observations and retries. Session authentication remains the hosting adapter's responsibility.

New excavation/fill work requires logical inventory reach (the existing 1.5 m integer spatial contract), voluntary consciousness, an active unreserved hand holding an actual `tool.shovel` item, operational mounted components from `ToolSimulationSystem`, and a free unreserved supporting hand. Declared context tool tags alone do not satisfy the gate. Inventory, component ledger and target cell revisions must be current. Positive integer amounts are bounded to 1,000,000 mg per command. Fill additionally requires the same principal's live escrow claim; unknown, consumed or foreign transfers reject. The domain owner independently enforces source mass, fill capacity, material/provenance compatibility, revisions and collection bounds.

The runtime accepts at most 16 validated terrain ingress attempts per fixed tick, within the runner's independent global queue budget. `simulate_tick` only advances the saved tick; there is no autonomous excavation, wear, I/O, wall-clock state or process invocation. Tick priority is 350, after inventory, health, tools and production. These one-shot commands do not model sustained digging work or charge wear; that requires a later work-order contract.

## Atomic requests, claims and recovery

A principal supplies a persistent monotonic `request_number`; `command_id` must equal `terrain-client-<request_number>`. The first new success uses 1; later successes require that principal's high-water mark plus one. Rejections consume neither ordinal nor owner sequence. The bridge allocates the domain owner's next successful sequence, preserving the exact original intent, principal ordinal and owner sequence in the same retained tail as the owner's last 64 receipts.

Exact retained retries are authenticated **read-only reconciliation**: they return the original receipt without repeating reach/tool/health work or requiring old revisions to become current. Changed retained intent rejects. An expired or skipped ordinal rejects permanently, including after restart. The caller must preserve its pending ordinal and original payload across uncertainty; observation's next ordinal is for new work, never a way to refresh a retry. The bridge's 16 principal high-water marks are never evicted or reassigned; registry exhaustion fails closed. Owner sequence and principal ordinal exhaustion also reject.

A synchronous successful commit is followed only by infallible bounded metadata updates: the principal high-water mark, request mapping and new/consumed escrow claimant settle before any command-completion callback. Live partial transfers retain their claimant even after their creation receipt expires. Full fill erases both transfer and claim. No checkpoint or asynchronous callback can observe half of that transaction. Metadata is permission state, not a second mass ledger.

`systems.terrain` emits schema v1 within the unchanged v1 world envelope. It atomically saves the owner, catalog fingerprint, stable positions, last tick, bounded principal map, request tail and live transfer claims. Validation uses the domain's conservation/replay decoder, verifies the exact commissioning budget, positions and capacities, matches every retained mapping to its owner receipt, checks contiguous principal ordinals/high-water totals, and rewinds claimant permissions through the retained tail. World link validation requires claimant principals to remain registered inventory bodies. All world systems validate before restoration mutates any system. JSON integer normalization uses the existing world envelope decoder.

The new contracts are `terrain-command-v1.schema.json` and `terrain-system-v1.schema.json`; `world-snapshot-v1.schema.json` adds an optional terrain reference so legacy envelopes remain valid. Shape validation cannot prove conservation, sequencing, permission history or storage authenticity. Trusted atomic persistence remains necessary. This slice reuses the local adapter byte limits (16 MiB envelope and 8 MiB snapshot) and adds no general-purpose JSON depth pre-parser. This milestone adds no client-controlled owner import.

`profiling_counters()` exposes owner counts/signals plus bounded runtime commits/retries/rejections and registered principal count. Counters reset on recovery and never drive matter state. The normal simulation profiler measures command and system time; no performance benchmark is claimed.

## Verification

The focused runtime suite fabricates a real shovel from three finite ore extraction/refining batches through authenticated production commands, equips it through inventory commands, and then tests the server terrain command queue. It covers unauthenticated scope/grant denial, spoofed/unheld/broken tools, occupied hands, reach, unconsciousness, stale inventory/tool/cell revisions, bounded amounts, foreign claims, exact partial/cross-cell fill, consumed claims, retained/changed/expired requests, per-tick backpressure, corruption rejection, JSON restart, depletion and zero-budget legacy migration. Terrain totals remain exactly 2 kg; inventory/production retain their own existing conservation validation.

The initial focused runtime run failed on a missing detailed inventory observation revision and reached its 120-second deadline. The corrected focused run passed import, startup and `terrain_runtime_test.gd` (2.36 seconds). After fixing an indentation error in the expanded retry-budget test, the final code was rebased onto `bef1b39622a6b0fbbc19f1b10f02819f3314d82d`. The final Windows bounded run on implementation commit `cf67f7be23c04be1e56c3b7ce887b01ac230aa20` passed **59/59 checks**: import, startup and all 57 selected headless scripts. The terrain runtime suite passed in 2.24 seconds. Both schema suites then passed (three runtime/world metaschemas and nine invalid shapes; five domain metaschemas and eight invalid shapes). `git diff --check` passed. Subsequent changes only record this verification and PR metadata; final-head CI remains the coordinator merge gate.

Run with the pinned Windows executable:

    ./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames 'terrain_runtime_test.gd','terrain_material_owner_test.gd','terrain_material_contracts_test.gd' -TestTimeoutSeconds 120

`tests/schema/terrain_runtime_schema_test.py` checks the actual emitted runtime checkpoint and retained command intents, the legacy world envelope, three draft-2020-12 metaschemas and nine invalid shapes. It uses a local-only registry and development `jsonschema==4.23.0` installed under ignored `var/ci/schema-python`. Run with a verified full Python path and `PYTHONPATH` set to that absolute directory. No production dependency or CI configuration changes.

The existing Windows/Ubuntu CI discovery automatically includes `terrain_runtime_test.gd`. Local Linux, graphical/VR terrain behavior and external live services are outside this verification. Local broad runs exclude `first_playable_acceptance.gd` to avoid concurrent use of cooperative port 27849; graphical and receiver-dependent scripts retain the runner's documented exclusions. CI is the remaining cross-platform and packaged-host gate.

## Remaining bounded work

Physical pickup and inventory/production transfers, shared payload aggregation, sustained digging/cancellation/wear, mesh/collision edits, streaming and arbitrary planets remain separate milestones. Future transfer integration must reserve capacity and atomically checkpoint both mass owners and receipts; it must not install a second independent inventory mass provider. UI/network terrain commands require a separate authenticated adapter and observations contract.

The subsequent [cooperative terrain controls milestone](terrain-controls-milestone.md) adds that authenticated adapter and projection without adding physical transfers. It also normalizes validated wire intent integers before retaining allocations, so JSON transport commits match durable receipt decoding.
