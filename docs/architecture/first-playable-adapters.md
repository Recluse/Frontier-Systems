# First playable transport and checkpoint adapters

## Runtime ownership

`FirstPlayableBootstrap` starts either the host (`-- --host`) or a remote client. The host composes `WorldRuntime`, `WorldPersistenceAdapter` and `FirstPlayableHost`; it restores a valid checkpoint before simulation starts. Clients use `RemoteWorldRuntime` and `RemoteProductionProjection`, which provide disposable observations and submit intents but never create a local canonical simulation runner.

Godot's [WebSocketPeer](https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html) supplies the polled socket interface. The host accepts streams from a loopback `TCPServer`; remote TLS is an operator proxy responsibility. Incoming frames are bounded to 8 KiB, two authenticated slots plus at most four simultaneous connections, four packets per peer per frame and twenty commands per second per authenticated peer. Slow consumers close rather than accumulating unbounded outgoing observations.

## Authentication and messages

The host requires two distinct invite keys of 32–256 characters. Authentication accepts exactly `type: authenticate` and `key`. Trusted host policy grants `inventory.operate` and `terrain.operate` to the two persistent fixture principals. Each accepted peer has a distinct server session. Clients cannot supply a context, actor, session ID, permissions, authoritative output or yield. Only one active connection per invite is allowed.

Command frames contain exactly `type: command`, `request_id`, `system`, `operation` and `payload`; terrain frames additionally require `request_number`. Production/inventory IDs are namespaced by server slot. Terrain work keeps its domain ID `terrain-client-<request_number>` and portable claims use independent `terrain-materialize-<request_number>` IDs; host pending routing uses the authenticated principal, connection session and command ID together, so two crews using ordinal 1 cannot overwrite or receive each other's completion. At most 32 host routes and eight client requests are pending. Disconnect drops routes and targeted events; an already authorized queued command may still settle and requires retained reconciliation. World/region scope comes from the host's authenticated context. Body reach, consciousness, manipulator availability, item ownership, capacities and revisions are rechecked by canonical owners at fixed-tick application.

Inventory movement additionally requires one in-flight move per peer, a maximum 8 m/s step budget with a 0.5-second elapsed cap, and the bounded authored habitat region. This is an accepted-pose prototype, not a complete authoritative physics server. Clients use local capsule collision for responsiveness, publish bounded intents and reconcile rejected positions.

Observations include shared production state, own inventory/cargo/components, own position, visible crew positions, nearby world-tray contents and checkpoint status. They omit other players' private inventory/cargo, source credentials, owner receipts and internal health data. JSON position arrays are normalized to integral coordinates before comparison.

Terrain observations follow `terrain-observation-v2.schema.json`: two stable finite dirt cells with positions, revisions, capacity/mass and advisory work readiness, plus only the requesting principal's live escrow, independent next claim ordinal and advisory claim readiness. Claim readiness checks voluntary consciousness and a free hand; it does not promise inventory capacity or revision success. The decoder verifies bounds, shape, integer normalization, stable fixture identity/positions, provenance and visible mass before publishing a detached copy. It rejects malformed views and clears observations on disconnect. This projection never feeds an owner restore. `TerrainSimulationSystem` remains the sole terrain runtime owner; observation readiness calls the same canonical work gate used by fresh commands.

`RemoteWorldRuntime` allows one unresolved terrain intent per client. It freezes ordinal, operation and original payload before sending and preserves them across uncertain sends/disconnects. Fresh work uses observed `next_request_number`; retries use only the retained original intent, even when observation advances. The optional bounded local journal (`terrain-client-intent-v1.schema.json` for legacy work or v2 for portable claims, 8 KiB maximum) contains world/region/invite slot and intent, without secrets or owner state. Bootstrap enables it under `user://terrain-client-intents`; on client restart the matching scope loads it and the Terrain panel offers explicit reconciliation. A failure to write prevents a send; a failure to clear retains the original intent for safe repeated reconciliation. Exact acknowledged rejection releases the ordinal for corrected fresh work; `request_pending` retains uncertainty. The journal is client data and cannot bypass host authorization or durable receipts.

The Terrain tab displays selected cell position/mass/capacity/revision, own escrow, active held item, inventory/tool revisions and host capability/rejection feedback. Two visual markers are advisory and have no collision or excavation geometry. Work is instantaneous finite escrow transfer. The whole-transfer claim action submits only transfer ID and expected inventory revision through `TerrainMaterializeCommand`. It needs no shovel, terrain reach or caller-supplied matter. Portable payloads retain the canonical terrain owner; Production consumption and sustained wear remain deferred.

Command completions and batch notifications append to a bounded host event queue; `_process` performs network sends. No socket sends or disk writes occur in the simulation completion callbacks. The client resolves its pending command signal when the host acknowledges. Batch notifications are volatile presentation events for the local guide, never durable reward events.

## Physical component transaction

The printer's bulk plate output can become a real `item.plate.prototype` with a stable derived item ID and a conserved 1 kg plate payload. Production prepares the resource debit and inventory factory record together, validates prospective item/body/equipment capacity, and commits both without a callback or await. If inventory adoption fails, production restores the previous record before returning failure.

Physical recycling requires an owned plate, workstation reach, powered recycler, finite energy and receiving capacity. It removes that exact item/payload and returns 1 kg iron atomically. Production v2's payload map covers both canisters and physical plates; cross-system validation requires the matching definition and exactly one kilogram of plate matter for every physical plate. Empty shells and unrelated item mass remain outside the closed mined-resource budget.

## Durable store

`LocalWorldSaveStore` reads two known checkpoint slots at startup and selects the highest valid sequence after checking bounded file size, envelope, checksum and world codec. Each write replaces only the alternate slot, flushes/closes it and reports a result. Truncated slots are skipped without regenerating a world; two invalid slots fail startup.

`WorldPersistenceAdapter` captures only outside ticks and with no queued commands, then passes a detached JSON string to a [Godot worker task](https://docs.godotengine.org/en/stable/classes/class_workerthreadpool.html). One write can be active; snapshots are at most 8 MiB within a 16 MiB envelope bound. The main loop polls completion, joins only a finished task, updates noncanonical status and emits completion. Shutdown joins any outstanding worker before its data is released.

Automatic checkpoints occur every five seconds. The authenticated `world/checkpoint` I/O request is handled outside simulation execution and acknowledged only after disk completion. A busy store or unstable capture returns a failure to retry. No callback changes canonical world state. Durability is at checkpoint granularity; a sudden kill can roll back newer activity.

## Extension points

Replace invite binding with Steam identity behind a session adapter; retain canonical command authorization. Replace local checkpoint storage with an asynchronous PHP repository through the existing versioned world contracts without changing resource ownership. Generalize fixture bodies/scenario metadata, authoritative physics and component factories in later milestones. Do not treat these two-player adapters as an unrestricted production platform API.

## Versioned data contracts

Production intents use production-intent-v1.schema.json; canonical records now use production-system-v6.schema.json (with v1–v5 migration). Read-only scoped projections use production-observation-v6.schema.json and are never valid restore inputs. Local checkpoint envelopes use local-checkpoint-v1.schema.json, with UTF-8 byte bounds and cross-system validation additionally enforced at runtime. These schemas live under docs/schema/.

[Equipment fabrication](equipment-fabrication.md) extends the factory preparation boundary and conserved structural mass. V2 payload-only descriptions above refer to the earlier plate/canister implementation.

Portable machinery construction and grid contracts are documented in [the resource machinery milestone](../development/modular-resource-machinery-milestone.md). Production owns material and machine records; inventory owns physical parentage/world roots. Prepared graph commits include prospective payload masses and trusted world location metadata. Remote machinery views include only owned parts and deployed shared assemblies.

Portable claims share the single unresolved terrain intent journal with work. Fresh claims allocate the observed independent ordinal (1-128); exact original retries may reconcile consumed escrow and an advanced observed ordinal after reconnect or restart. Authentication binds world/region/principal/session before fixed-tick application. A v1 observation supports work but cannot allocate fresh portable claims. Neither observation includes other principals' claim history or owner receipts. Claim acknowledgement carries the existing completion status; updated own inventory provides the physical parcel. No checkpoint, owner or world envelope version changes in this client slice.
