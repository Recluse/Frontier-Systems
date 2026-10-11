# Local extraction guide and movement binding

The desktop prototype now guides the first playable resource route: collect 2 kg iron ore into an owned canister, unload it, complete two iron-refining batches, print a plate, collect it as a physical item, recycle it, and print again (seven stages). Readable recipe labels show the input/output relationships.

## Guide ownership

`LocalProductionGuide` is disposable session-only presentation. It observes successful commands submitted through its own production panel and local authoritative batch-completion notifications. Accepting a recipe does not complete a refining/crafting step. The production system emits `batch_completed(recipe_id, tick)` only after committing outputs and clearing its reserved batch. Cancelling a batch clears the guide's watched recipe without advancing completion.

The guide does not grant resources, permissions, achievements or research. It does not save into world snapshots or restore completion after restart. It displays confirmed session activity; it is not proof of material provenance or unique throughput. Resource mass remains owned by production and inventory. Multiple players may supply the same shared depot without changing those owners' conservation rules.

Completion signals are volatile local presentation notifications, not durable integration events. Persistence, external services, progression and rewards must use their own validated durable contracts. The HUD callback performs only bounded flag/counter updates; normal 10 Hz polling updates labels.

## Desktop position binding

`FrontierBootstrap` enables the existing local inventory/body bridge by default and requests position observation even when the character is not in walking camera mode. An initial sample queues the current capsule position. This avoids retaining the synthetic inventory origin while the player uses the overview camera. Movement updates continue through the normal fixed-tick command queue, with one pending acknowledgement and unchanged position suppression.

The bridge's standalone defaults remain disabled and require active navigation. Its optional fourth configuration argument enables inactive-character observation for the desktop bootstrap only. The development checkbox can disable/re-enable the bridge for debugging. Source and workstation reach continue to use the latest committed logical position, not a UI-provided reach flag. There may be one pending tick/sample delay before a movement observation is applied.

The above describes the legacy local lab. In the cooperative scene, FirstPlayableBootstrap instead sends bounded movement intents to an authenticated host and reads scoped observations. Detailed collision authority remains future work. The legacy bridge remains a development-only adapter. It does not supply network-authoritative movement, seated/headset body binding or collision-authoritative remote player replication. First/third-person capsule physics remains local presentation, and health currently gates the logical interaction commands rather than all capsule movement.

## Verification scope

The cooperative graphical check completes all seven guide stages using local character physics and authenticated host commands, on both Forward+/D3D12 and Compatibility/OpenGL. See [acceptance evidence](../development/first-playable-acceptance.md). Human usability, cancellation and guide-reset review remain separate follow-up checks.

## Current workstation recipe requirements

`WorkstationResourceView` uses only validated host `recipe_requirements` from production observation v8. It never loads the client catalog as authority. Each recipe exposes inputs in milligrams, energy in joules and its station; duration, output capacity and execution availability are not quoted. Shared stock pays recipe inputs; owned cargo must first be unloaded. The older seven-stage session guide and first-playable task route still describe the default scenario; they are not alternate-catalog recipe quotes.

Production owns catalog identity and initializes it once from the validated catalog. Observations are detached read-only copies, produced at the existing observation cadence (the panel polls at 10 Hz). The simulation's priority-300 tick, command validation, receipts, failure behavior, persistence v7 and existing profiling signals remain unchanged. There are no asynchronous callbacks or new tick-time I/O. Invalid observations display unavailable information and cannot enable commands.

Observation v8 requires at most 32 recipe entries whose keys exactly match the recipe ID list. Every entry has exactly `station`, `inputs` and `energy_joules`. Inputs contain 1–32 registered materials with positive integer milligrams, at most 100,000,000 mg total; energy is an integer from 1–100,000 J. Stations use the existing seven station IDs. Runtime additionally checks dynamic recipe-key equality and total input mass, which JSON Schema cannot express. The catalog revision is 1 and its identity is a lowercase 64-character SHA-256 fingerprint of the complete host catalog, not of this reduced projection.

A remote connection pins the first valid catalog identity and v8 requirements. Changed identity, changed requirements, unknown fields, missing entries, unknown materials/stations, non-integral/negative/unbounded amounts and v8-to-v7 downgrade are rejected. Disconnect clears the projection and identity so a new connection can accept another validated catalog. The fingerprint identifies the authenticated host catalog; the reduced projection does not independently reconstruct or authenticate that full catalog.

New clients accept exact legacy v7 observations and explicitly report recipe requirements unavailable without fixture assumptions. Persistence and restore remain v7, and an observation cannot be restored as a canonical record. Old clients that only accept v7 cannot consume v8; use matching host/client builds. There is no protocol negotiation or new authorization boundary.
