# Owned container wire and durable replacement acceptance

Tests/docs-only successor to the owned closure panel/host route and closed inventory durable recovery milestones. Canonical ownership remains in `InventorySimulationSystem` and `SharedInventoryCoordinator`; the test installs no candidate owner, permissions, item records or receipt data. No runtime, schema, UI or workflow changes.

`player_inventory_closure_loopback_test.gd` inherits the existing movement loopback fixture's traced production remote, shell, bounded waits and assertions. It uses the actual `FirstPlayableBootstrap` inventory panel and its connected button signals, `RemoteWorldRuntime`, invite-authenticated `FirstPlayableHost`, simulation ticks, `WorldPersistenceAdapter` worker/native filesystem and checksum-validated `LocalWorldSaveStore` readback. Source and replacement listeners use 27861 and 27862 serially. Local use requires the coordinator's explicit exclusive lease before running; occupied ports fail rather than replacing another listener. CI executes tests serially on isolated Windows/Linux workers using the unchanged bounded runner.

Acceptance assertions cover:

- Owner-selected backpack ID and exact observed revision; another authenticated principal's closure denial without mutation.
- Held host ticks with continuing real wire observations: no optimistic closure, no resubmission, and picker changes preserving the submitted target/revision.
- Matching acknowledgement/UI receipt feedback, one canonical revision increment and the exact retained canonical receipt.
- Closed ancestor denial for moving the crowbar from the nested pouch, before and after replacement.
- Shell-requested checkpoint confirmed through the real wire acknowledgement, checksum-validated disk readback retaining the complete closed owner, item fields and receipt.
- Real socket disconnect, cleared presentation, native startup restore into a replacement world/host, manual reconnect and fresh authenticated observation without replay or old acknowledgement leakage.
- Explicit panel reopen followed by successful nested transfer; only the intended item's location changes. All remaining item fields/provenance and exact carried mass remain conserved; the original closure receipt stays retained.

The host acknowledgement contains request ID/status/code/message, not a serialized canonical receipt body. The test correlates the client ID with the existing authenticated `net-1-<request>` canonical identity, and verifies the exact receipt separately in canonical state and on disk. It does not claim receipt-body transmission. Existing durable tests retain exact retry/conflict coverage without adding a new runtime retry route.

## Verification and limits

Pinned Windows Godot 4.7.2 (`4.7.2.stable.official.ed1daf0bf`), versioned `tools/ci/run-godot-checks.ps1`, 120-second unchanged test deadlines. Focused checks: `player_inventory_closure_loopback_test.gd`, `player_inventory_closure_test.gd`, `player_inventory_closure_route_test.gd`, `inventory_closed_durable_checkpoint_test.gd`. Import/startup and each focused check passed locally. The final acceptance run uses a unique temporary custom user profile via `override.cfg`; native checkpoint storage is unique and removed by the fixture. Terrain journaling and external event upload are disabled. No real operator invites or saves are used. PR CI supplies separate Windows/Linux evidence at its exact head.

Button signals are synthetic activation of actual connected controls. Host/client sockets are real but share one Godot process. Replacement destroys fixture-owned nodes and reconstructs adapters from disk; it is not process-crash, power-loss, live remote-network, physical input, human tutorial, graphical, controller or VR evidence. No screenshots/videos are required to resolve the transport/durable behavior established by source review and runtime assertions. Human tutorial readiness remains unverified. No release, deployment or public media was produced.
