# Reserved board replacement work

The prototype maintenance command layer now supports timed replacement of an existing control board with an existing spare. This remains a local-development feature with the same debug-build, configuration grant and server-derived tool checks as other maintenance.

## Parts and planning

New prototype worlds have one installed expanded board (`habitat-board-expanded`, revision 2) and one stock spare (`habitat-board-stock`, revision 1). These are startup fixture parts, not fabrication rewards. The system owns board identity and resolves their definitions from two pinned first-party fixtures. Commands cannot supply new board definitions or create spare parts.

`replace_board` accepts a `target_board_id` from the host's spare tray. The circuit's pure transfer planner validates the complete fit before reserving work. A smaller board cannot silently drop utility modules: remove those modules to the salvage tray first. This slice transfers retained modules to matching slot IDs; explicit relocation parameters remain a future command extension. The underlying board planner already supports relocation.

The active job reserves its target by keeping it in the spare tray and preventing other maintenance from changing topology, parts or power. Existing hardware remains installed until completion. No partially dismantled board state is modeled yet. Board condition is not modeled separately from the host controller; module integrity is preserved.

## Tick ownership and interruptions

`BoardReplacementJob` stores request/job ID, initiating actor ID, target board identity, created/updated ticks, completed work ticks and active/paused status. The authoritative machine-control tick advances at most one unit of work, requiring an intact isolated controller, closed host doors and no active bypass job. Work lasts 180 simulation ticks (three seconds at the current 60 Hz configuration); it never waits on a service or wall clock.

The creation frontier is the access system's last completed tick when the command is applied. The next system tick supplies the first unit of work. Losing a hardware prerequisite pauses without resetting progress. Only the initiating actor may resume or cancel through the local maintenance boundary. Resume rechecks hardware and tools; cancellation can release the reservation even if hardware prerequisites were lost. It leaves both boards and all installed modules unchanged.

While a job exists, other maintenance commands are rejected. Manual door interactions keep their own physical rules and may cause the job to pause. Production actor presence, movement, disconnection, tool durability and inventory reservations are not implemented; these must be added before general player construction.

At completion the circuit revalidates and applies the transfer plan atomically. It retains fitted module IDs, definitions, condition and wire endpoints. The target spare becomes installed, and the old installed board becomes a spare with its existing ID and revision. No board is duplicated or deleted. Power remains isolated; the operator must explicitly restore it after work. A failed final fit pauses at 179 ticks and leaves hardware unchanged.

## Saved state

Machine-control system snapshots now emit **v3**: the existing circuit and module salvage records plus installed board ID, spare board references and nullable board job. Existing circuit, module inspection and job records remain separate v1 contracts. Maintenance intents emit **v2**, adding replacement/resume/cancel while accepting previous v1 operations.

Restore resolves both stock and expanded board revisions from the trusted catalog. It rejects duplicate board identities, overlap with installed/salvaged module IDs, missing target reservations, invalid plans, invalid status and work progress inconsistent with saved ticks. An active saved job must also have compatible isolated access-control state. All system validation happens before live restoration.

Restored jobs retain progress but start paused, requiring a fresh actor/tool check to resume. Older control-system v1/v2 records receive a deterministic legacy installed-board identity, no spare boards and no job. Migration does not spawn upgrade materials. Durable database/file storage remains separate from the existing world snapshot codec.

## Prototype use

1. Close the doors and isolate the controller.
2. Remove the latch module into its salvage tray before selecting the stock board.
3. Select **Fit stock board (timed)** and wait for the progress counter to finish.
4. Select **Fit expanded board (timed)** to exchange the boards again.
5. Reinstall the original latch, reconnect its wire and restore controller power.

The panel also exposes resume/cancel and current board revision. No tests were added or run, and this work has not been executed in Godot.
