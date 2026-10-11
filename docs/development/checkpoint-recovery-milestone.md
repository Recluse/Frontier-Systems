# Checkpoint recovery milestone

Scope: `src/adapters/persistence`, dedicated Godot recovery tests, and this document. The authoritative world runtime, network acknowledgements, production schemas and v1 snapshot format stay unchanged.

## Contract gaps identified

- Direct slot truncation plus sequence advancement on failed attempts can destroy the last valid checkpoint on a retry.
- The writer accepts invalid snapshot JSON and does not verify the encoded envelope byte bound or read back written bytes before acknowledging success.
- The adapter trusts any successful worker result, lacks explicit sequence exhaustion handling and leaves shutdown completion state pending.

## Acceptance work

Use a staged, flushed, verified checkpoint and preserve the latest valid slot. Commit sequence and saved tick only after a matching worker acknowledgement. Exercise interrupted stages, corrupt slots, injected write/promotion/read failures, stale results, retry and shutdown using disposable storage. No simulation tick performs storage I/O; workers receive detached values and never mutate canonical state.

Validation evidence will be recorded after the bounded repository Godot runner completes. This milestone does not promise per-command durability, device-level power-loss guarantees, multi-process writers or a database/journal implementation.
