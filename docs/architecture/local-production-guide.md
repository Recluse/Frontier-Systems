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
