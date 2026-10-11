# Closed inventory durable world recovery acceptance

Tests/docs-only successor to PR #77, based on `9d29fdd6e6252f8ddb226798290ad055fda35f80`. Adds `tests/godot/inventory_closed_durable_checkpoint_test.gd`; no runtime, schema, UI, bootstrap, movement, transport or configuration changes.

## Actual owners and storage

The test inherits the bounded save/readback, queue scheduling, startup, disposal and assertion helpers from `inventory_durable_checkpoint_test.gd`. It composes an actual `WorldRuntime`, inventory/controller authority and one queue (capacity four, one attempt per tick), with an injected authenticated-session provider for the two existing principals. The resource-carrier option selects `data/inventory/shared.production.v1.json` before world initialization. Existing inventory, health, tools, production and terrain owners remain canonical; no fixture candidate is installed and no items, materials or receipts are invented.

Inventory advances exclusively through the queue; the inherited scheduler temporarily unregisters inventory, advances the remaining real systems through `SimulationRunner`, and re-registers inventory before full-world capture. Automatic physics and adapter processing are disabled. Save uses the actual `WorldPersistenceAdapter` worker and native `CheckpointFileIO` in unique temporary directories, a five-second acknowledgement bound, and `LocalWorldSaveStore` checksum/sequence readback. Source worlds/adapters are destroyed before replacement-world loading. All test storage is removed after completion. No loopback ports or external services are used.

Closure upgrades the existing owner/ledger to v2 and inventory system snapshot to v5; world snapshot and disk envelope remain v1. Controller identities, tokens, pending intents and observations remain volatile. Worker callbacks collect acknowledgement evidence only; they never mutate canonical state.

## Acceptance

- Real authenticated queued commands close the existing nested pouch, then its outer backpack. Every item field, owned knowledge and carried mass stays exact. The full v5 world is asynchronously committed and its captured JSON is read back byte-for-byte.
- A replacement world/queue exists before loading, with both old tokens and one volatile search intent. Actual adapter loading restores the saved tick and exact closed owner, revisions and receipts. Restore synchronization discards that intent exactly once without advancing a tick and denies both old tokens.
- An unaffected root search saved at progress 119/120 restores paused. Another 180 ticks leave it paused with exact progress, owner and receipts. Production, terrain and tool records remain exact except expected `last_tick` advancement.
- Trusted reconciliation and fresh binds cannot revive old tokens. Retrying the original outer closure ID with its exact original payload succeeds with an unchanged complete owner, proving retained receipt idempotency and no second shared/ledger revision. Conflicting ID reuse fails. Closed ancestry rejects inner reopening and taking; reopening the outer container leaves the inner pouch closed.
- After both ancestors are legitimately reopened, a queued take reaches progress 179/180 and is durably saved. Another actual replacement loads it paused; 180 ticks cannot complete it. As in the existing paused closure fixture, synchronous authenticated internal dispatch applies closure and reopening at the next fixed boundary without a fresh bind (which would invalidate participating work first). Closure removes the paused job; same-boundary reopening cannot resurrect it or move matter. Sequence 3 durably retains cancellation.
- Seven malformed closure cases are written in valid, checksummed sequence-2 envelopes: numeric/string/null/missing booleans, closed root, system/owner version mismatch, and a saved take crossing a closed ancestor. A genuine older sequence-1 checkpoint also exists. The storage decoder selects the newer envelope, then actual world/domain configure rejects it atomically; it never silently falls back to the older domain-compatible record. Whole live-world JSON, tick, controller restore generation, pending queue counters, valid owned observation and both file slots stay exact. No saved tick is acknowledged and no writer adopts the refused directory.

## Verification and limits

Pinned Godot 4.7.2 on Windows, versioned bounded runner:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' -TestNames inventory_closed_durable_checkpoint_test.gd,inventory_closed_containers_test.gd,inventory_durable_checkpoint_test.gd,inventory_queued_job_lifecycle_test.gd,inventory_controller_lifecycle_test.gd,checkpoint_recovery_test.gd -TestTimeoutSeconds 60 -OutputDirectory var/ci/closed-durable-regressions
```

The focused six-test regression set passed all eight checks (import, startup and six tests), with zero failures; logs/JUnit are in `var/ci/closed-durable-regressions/`. Exact-head CI is reported separately on PR #82. Existing `.github/workflows/ci.yml` automatically discovers the added test and runs it on Windows and Ubuntu; this test change selects the full required CI matrix. CI pending is not a pass.

The existing fixture supplies nonempty component material IDs, definitions, integrity and wear records, finite deposits and real resource-carrier shells. Full item/component records, pinned catalog fingerprints, owned mass and supplied production/terrain payload records are conserved. Production cargo starts empty; loaded resource cargo, generated parcels and active production/terrain work are not exercised. The test adds no production/terrain scenario to manufacture that evidence.

This proves in-process replacement recovery through actual durable storage, rather than direct subsystem JSON restore. It does not prove power-loss/fsync guarantees, process-kill recovery, live authenticated transports, device hardware, graphical play, controller/VR acceptance or local Linux execution. No gameplay screenshots are needed for this tests/docs-only change: meaningful runtime checks establish the covered behavior. No release, deployment or merge is included.
