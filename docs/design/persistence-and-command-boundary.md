# Persistence and Command Boundary

## Intent and security boundary

The command wire format represents an untrusted request, not an authenticated actor and not a simulation result. The version 1 contract is [`command-intent-v1.schema.json`](../schema/command-intent-v1.schema.json); matching Godot and PHP decoders reject unknown top-level fields, malformed IDs, oversized payloads, unsupported versions, and non-JSON values.

The request contains a request ID, world and region IDs, a registered command type, optional expected tick, and bounded command-specific payload. It deliberately contains no player ID, Discord ID, Steam ID, roles, permissions, credentials, or requested resulting state. The server obtains the principal and session from its authenticated transport, binds them to an `AuthenticatedCommandRequest`, checks current scope and permissions, resolves the command through a server-owned handler registry, and constructs the typed `SimulationCommand`. The request ID becomes the typed command ID. A model or client cannot supply a trusted command context.

`AuthenticatedCommandContext` is server-local and must never be serialized. The current bootstrap has an explicit local-development context with one airlock permission so the prototype UI can exercise its fixed-tick queue. It is not a multiplayer authentication implementation. Network sessions, role/ACL policy, command handler registration, and durable request receipts remain future work.

An optional expected tick is a stale-state guard for commands that require it. It is not an access check and does not replace validation against current world state. Handlers return reason-coded rejection results for stale state, inaccessible targets, invalid ranges, missing capabilities, or physical interlocks. Accepted commands are applied at the next tick boundary; service responses and model output are never applied directly.

## Idempotency and ordering

Scope command request IDs by authenticated principal, world, and region. Repeating the same request while it is pending must return its pending status; repeating a completed request with the same canonical payload must return its recorded result without applying it again. Reusing an ID with different content is rejected. Clients retry with the same request ID and payload; a changed request receives a new ID. No UI retry creates a fresh ID implicitly.

This project has not implemented a command receipt ledger. Before remote clients are accepted, the authoritative journal must record a command's outcome with the world transition it produced, or define a recoverable pending/unknown result policy that cannot blindly replay physical actions after a restart. The current in-memory fixed-tick queue is not durable and does not provide exactly-once command execution. Reordering is resolved by the server's fixed-tick command order and command-specific precondition checks, not by trusting client timestamps.

## Snapshot persistence contract

Godot's `WorldSnapshot` remains the domain snapshot: schema version, world ID, region ID, simulation tick, and system-owned records. Persistence revision is separate metadata, because a storage write can advance without changing the simulation schema. The PHP PSR-4 `world-contracts` package validates that shared envelope and defines an asynchronous `WorldSnapshotRepositoryInterface`.

Snapshot saves use compare-and-swap revisions. `expectedRevision = 0` creates a world-region record; later writes must name the current revision. A repository commits the new snapshot and request ID atomically, returning the prior result for a retried identical request and rejecting an idempotency key reused for different content. Revision conflicts are explicit promise rejections with expected/current revision values. The repository never overwrites a newer snapshot silently.

The PHP interface returns ReactPHP `PromiseInterface` values. A Godot persistence adapter must return a `GamePromise`/service result and schedule its completion through the bounded continuation dispatcher. Snapshot capture remains outside active ticks and with no pending commands; startup restore completes before the simulation starts. A save or restore error is visible and retryable, and no tick waits on storage. The interface has no database or file adapter yet; do not use synchronous file writes or child processes as a Windows workaround. Choose a genuinely asynchronous storage driver when a deployment consumer is ready.

## Contract map

| Layer | Contract | Status |
|---|---|---|
| Wire request | `command-intent-v1`, no actor identity | Schema and parsers added; no network endpoint |
| Authenticated request | `AuthenticatedCommandRequest` plus server-local `AuthenticatedCommandContext` | Type boundary added; real account/session auth absent |
| Tick command | Typed `SimulationCommand`, current permission and state validation | Fixed-tick queue in place; in-memory demo context only |
| World snapshot | `world-snapshot-v1` | Godot serialization and pre-start restore in place |
| Snapshot storage | PSR-4 async repository, expected revision, request-ID idempotency | Contract added; database/remote adapter and durable recovery absent |
| Command receipts | Durable result/replay journal tied to world transitions | Required before remote command ingress; not implemented |

## Acceptance gate before multiplayer clients

- Actor identity is derived from the authenticated connection; no RPC payload can choose the principal or permissions.
- Only registered command types and exact typed payloads reach command construction; unknown fields/types fail closed.
- Per-principal and per-target rate limits, bounded queues, request IDs, and reason-coded results are enforced.
- Duplicate, concurrent, reordered, stale, and replayed requests are tested against two clients and restart recovery.
- Command outcome durability cannot diverge from the persisted world transition; unresolved pending requests have an explicit operator-visible state.
- Snapshot saves use atomic revision compare-and-swap and idempotent retries, and restore succeeds before ticks begin.
- Provider, persistence, and networking timeouts never stall a Godot tick; supported deployments remain Windows-compatible.

## Retained extraction Resume results

The local production snapshot retains bounded immutable success receipts. For `resume_tool_extract`, fixed-tick validation and application pass the host-bound canonical request ID into authorization. Current actor permission, registered capable body and available unreserved hand are checked first. An exact retained fingerprint (authenticated principal, operation and complete canonical payload, including expected revision) permits returning the prior receipt before mutable job/source-reach checks. Fresh requests still require an existing reserved extraction and source reach; changed intent, foreign principals and invalid command scope reject. Retrieval does not advance the production revision, append a receipt or apply work again. Original receipt tick/revision/fingerprint remain unchanged. This is bounded production idempotency, not a general durable command journal or crash guarantee.

The command envelope accepts finite integer-valued JSON numbers, including integral floats produced by a decoder, for the protocol version and expected tick. The expected tick is normalized to an integer and ranges from 0 through 9,007,199,254,740,990, matching the world snapshot tick bound. Fractional, non-finite and out-of-range values reject before conversion; command-specific payload numbers are preserved for their handler to validate. This narrows the previously unbounded expected-tick contract while making Godot and PHP JSON decoding agree.
