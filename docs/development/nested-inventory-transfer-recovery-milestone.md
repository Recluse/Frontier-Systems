# Nested inventory transfer recovery milestone

## Missing acceptance case

The existing paid inventory access fixture creates a physical plate through finite extraction, energy-paid refining and printing, then exercises its nested storage access. The existing closure loopback fixture restores native checkpoints and transfers the development crowbar. Neither covered an admitted but unsettled **paid nested transfer** abandoned across native restore and explicit manual reconnect.

`nested_inventory_transfer_recovery_test.gd` extends the existing closure loopback fixture and reuses the paid recipe from `player_inventory_access_guidance_test.gd`. It adds no runtime behavior, schemas, controls or assets. PR99 machinery Cancel and PR100 extraction recovery remain separate.

## Acceptance and authority

- Produce an actual one-kilogram plate through two finite iron extractions, paid refining, plate crafting and materialization. Verify the remaining deposit/store/tailings budget, physical payload mass and consumed energy; move that stable item into the existing pouch using queued commands.
- Close its backpack ancestor and confirm the complete owner on checksummed native disk through the actual client checkpoint route.
- Explicitly reopen, hold fixture ticks and admit the exact paid Move from the actual inventory button through the production WebSocket. Continuing observations preserve the complete owner and send count; no optimistic movement or repeated submission occurs.
- Disconnect and replace the host/world in-process from that closed checkpoint. Explicit manual reconnect waits for a fresh authenticated observation and sends no abandoned transfer. The transport returns `remote_disconnected`, generic panel feedback retains unknown-outcome/reconnect guidance, no old acknowledgement arrives, and a late old completion cannot settle the request. Generic transfer feedback clears its pending target; this does not claim closure-style retained target feedback.
- Submit a fresh explicit transfer through the adapter despite the closed UI prerequisite. Host validation returns `inventory_container_closed` and conserves the complete owner. Explicitly reopen with the existing control, then submit a fresh paid Move through the actual button.
- Compare the **complete canonical owner** against an independently constructed expected record: only the intended plate location, ledger/shared/acting-body revisions and exact authenticated self receipt change. Every item, container, condition, equipment binding, other body and provenance field remains equal; carried mass stays exact. Compare the whole production record between native checkpoints, allowing only tick advancement. No refund or repeated paid work occurs.
- Confirm the completed transfer on disk, replace again and manually reconnect. The full owner and mass persist without replay.

Canonical state stays with `InventorySimulationSystem` / `SharedInventoryCoordinator` at fixed ticks. Closure upgrades inventory system to v5 and owner/ledger to v2. Temporary `WorldPersistenceAdapter` / `LocalWorldSaveStore` checkpoints retain canonical records; pending client requests and host routing stay volatile. Existing queue rejection/application and persistence status signals provide diagnostics. No callbacks, client observations or test-created records mutate canonical state.

## Verification

Windows Godot `4.7.2.stable.official.ed1daf0bf` passed the versioned runner's import/startup and:

- `nested_inventory_transfer_recovery_test.gd` (final test: 4.05 seconds; logs/JUnit in ignored `var/ci/nested-transfer-recovery-final`).
- `player_inventory_access_guidance_test.gd` (10.87 seconds).
- `inventory_closed_durable_checkpoint_test.gd` (3.11 seconds). Existing fixture logs/JUnit are in ignored `var/ci/nested-transfer-recovery`.

Reproduce with `tools/ci/run-godot-checks.ps1 -Godot <pinned Godot 4.7.2 console executable> -TestNames nested_inventory_transfer_recovery_test.gd,player_inventory_access_guidance_test.gd,inventory_closed_durable_checkpoint_test.gd -TestTimeoutSeconds 120`. Reserve port **27849** with the Coordinator before the socket case. Both initial/replacement hosts and the client use this explicit port; no default/unreserved listener is used. Cleanup reuses the existing fixture, closes only owned nodes and deletes its unique temporary checkpoint directory. Local and remote TCP inspection returned zero records for 27849 after completion, and the lease was released to the Coordinator.

PR checks must be assessed at the final pushed head; local Windows success does not establish Linux CI. Human tutorial remains `awaiting_human`. Input/button signals and deterministic fixture tick holds are synthetic; sockets, authentication, command validation, receipt correlation and disk save/readback are production paths. Replacement is in-process, not a process crash, power-loss or physical disk-failure test. Human, controller/VR, graphical and live-network acceptance remain unverified. Source review and these meaningful runtime regressions resolve the bounded behavior without gameplay captures. No media, publication, merge or deployment is part of this change.
