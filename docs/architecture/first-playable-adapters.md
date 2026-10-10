# First playable transport and checkpoint adapters

## Runtime ownership

`FirstPlayableBootstrap` starts either the host (`-- --host`) or a remote client. The host composes `WorldRuntime`, `WorldPersistenceAdapter` and `FirstPlayableHost`; it restores a valid checkpoint before simulation starts. Clients use `RemoteWorldRuntime` and `RemoteProductionProjection`, which provide disposable observations and submit intents but never create a local canonical simulation runner.

Godot's [WebSocketPeer](https://docs.godotengine.org/en/stable/classes/class_websocketpeer.html) supplies the polled socket interface. The host accepts streams from a loopback `TCPServer`; remote TLS is an operator proxy responsibility. Incoming frames are bounded to 8 KiB, two authenticated slots plus at most four simultaneous connections, four packets per peer per frame and twenty commands per second per authenticated peer. Slow consumers close rather than accumulating unbounded outgoing observations.

## Authentication and messages

The host requires two distinct invite keys of 32–256 characters. Authentication accepts exactly `type: authenticate` and `key`. Keys bind persistent fixture principals to separate authenticated contexts with only `inventory.operate`. Clients cannot supply a context, actor, session ID, permissions, authoritative output or yield. Only one active connection per invite is allowed.

Command frames contain exactly `type: command`, `request_id`, `system`, `operation` and `payload`. IDs are bounded and namespaced by server slot before reaching retained domain receipts. Production and a closed inventory subset are accepted; platform/admin systems are not exposed. World/region scope comes from the host's authenticated context. Body reach, consciousness, manipulator availability, item ownership, capacities and revisions are rechecked by canonical owners at fixed-tick application.

Inventory movement additionally requires one in-flight move per peer, a maximum 8 m/s step budget with a 0.5-second elapsed cap, and the bounded authored habitat region. This is an accepted-pose prototype, not a complete authoritative physics server. Clients use local capsule collision for responsiveness, publish bounded intents and reconcile rejected positions.

Observations include shared production state, own inventory/cargo/components, own position, visible crew positions, nearby world-tray contents and checkpoint status. They omit other players' private inventory/cargo, source credentials, owner receipts and internal health data. JSON position arrays are normalized to integral coordinates before comparison.

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

Production intents use production-intent-v1.schema.json; canonical records use production-system-v2.schema.json. Read-only scoped projections use production-observation-v2.schema.json and are never valid restore inputs. Local checkpoint envelopes use local-checkpoint-v1.schema.json, with UTF-8 byte bounds and cross-system validation additionally enforced at runtime. These schemas live under docs/schema/.
