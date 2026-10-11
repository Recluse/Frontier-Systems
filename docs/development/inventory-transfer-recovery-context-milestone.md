# Inventory transfer recovery context milestone

## Behavior and boundaries

A disconnected generic Move now retains its exact request ID, item ID, source container, destination container and submitted revision as historical display text. It explicitly reports an unknown outcome, manual reconnect/refresh guidance and no automatic retry. Fresh observations and picker changes do not prove that the lost request succeeded and do not replace this context. Repeated disconnects preserve it.

The live pending ID and payload are cleared on disconnect. The retained value is a string only: no command, request or replayable payload is retained. A late completion is ignored by the existing pending-ID fence. An explicit new action reaching the shared submission path clears the historical context, including a new action rejected during enqueue. Prerequisite-only attempts are not submissions. Ordinary acknowledgements continue to use existing host result feedback.

Canonical owner, tick cadence, persistence versions, command validation and profiling remain unchanged: InventorySimulationSystem / SharedInventoryCoordinator own state at simulation ticks. This change is limited to PlayerInventoryPanel feedback, tests and this milestone document. No authority, schema, refinery or extraction changes.

## Verification

The successor reuses PR101's genuine finite-extraction, paid refining/printing plate fixture in nested_inventory_transfer_recovery_test.gd. It checks exact abandoned Move context after native restore and manual reconnect, cleared live payload, late-success fencing, and replacement only after a new explicit closure submission. Its existing complete-owner/receipt/provenance and production-budget assertions continue to establish conservation.

player_inventory_transfer_layout_test.gd adds both remote completion-before-disconnect and disconnect-before-completion ordering, repeated disconnect preservation, fresh-observation/selection persistence, fresh request identity and long-ID wrapping/focus/scroll checks in the actual shell. These layout observations and key events are synthetic, with no sockets or canonical mutation.

Local results and final-head CI are recorded below after verification. Socket checks require the Coordinator's exclusive 27849 lease, queued behind refinery and extraction retry. Use the existing tools/ci/run-godot-checks.ps1 runner and pinned Godot 4.7.2 console executable.

Human tutorial remains awaiting_human. Headless layout and loopback tests do not establish human, graphical, controller/VR, live-network, process-crash, power-loss or physical-disk-failure acceptance. Gameplay capture is unnecessary if source review and focused runtime regressions resolve this bounded presentation behavior. No public media or deployment; Coordinator owns merge.
