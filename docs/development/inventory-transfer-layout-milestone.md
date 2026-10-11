# Inventory transfer layout milestone

Base: origin/dev-master 737dcba430736f7c2e2ec337d737ffae74a82bac, after PR59.
Branch: inventory-transfer-layout; draft PR targets dev-master.

## Observed issue and change

At 1920x1080 with a 540 px sidebar and 1100x720 with a 420 px sidebar,
existing wrapped labels and action flows fit the actual FirstPlayableBootstrap
shell. The new baseline fixture failed eight checks: transfer guidance could
not receive keyboard focus, and focused long receipt text could not scroll up
to its beginning. A matching failure can be taller than the visible pane.

Transfer/capacity summaries, tray status and host receipts now accept Tab focus.
Their UI Up/Down and Page Up/Page Down events scroll the existing inventory pane
without leaving guidance focus. Existing follow-focus behavior reveals actions;
long guidance is readable by scrolling rather than requiring simultaneous display.

PlayerInventoryPanel owns this disposable layout/input handling; it changes only
on GUI events, selections and observations. InventorySimulationSystem and
SharedInventoryCoordinator retain canonical state, tick cadence, persistence,
command validation, permissions and profiling. Commands, schemas, controller
authority, action prerequisite/business rules and movement feedback are unchanged.
No configuration variables or example-file updates are needed.

## Verification and limits

Windows Godot 4.7.2 bounded import/startup and the five inventory gates passed:
player_inventory_transfer_layout_test.gd, player_inventory_transfer_preview_test.gd,
player_inventory_handoffs_test.gd, player_inventory_feedback_test.gd and
client_inventory_shell_test.gd. Existing player_inventory_usability_test.gd and
integrated_panel_layout_test.gd cover the affected component focus order separately.
Frozen-head results and remote CI are reported with the PR; dirty iteration runs
are not represented as exact-head CI evidence.

The new fixture uses the actual shell, socket-free recording transport and injected
keyboard events. Detached observations contain 128-character IDs satisfying the
existing ID contract; they are presentation fixtures, not proof of canonical world
validity. It checks complete source/destination/slot and capacity text, retained
wrapped lines and bounded widths, both ends of long guidance through arrow/page
scrolling, enabled move/equip/pickup/drop focus reveal and bidirectional Tab order,
exact self/world pending payload isolation from unrelated receipts, matching long
failure text, removed selections and disconnect uncertainty. Canonical snapshot
and input observations remain unchanged; queued intents are not applied.
The existing four regression gates retain their distinct real-domain coverage.

The focused inventory-transfer-preview.yml runs the new fixture plus all four
current presentation gates with pinned Godot on Windows/Linux. Full CI still applies.
No local Linux, human mouse/keyboard usability, controller, VR, authenticated
network recovery, live multiplayer or packaged-artifact acceptance is claimed.

Native Compatibility captures use ordinary Godot rendering of the same automated
socket-free fixture. They are internal ignored evidence, not art assets, and are
not uploaded. The existing runner isolates a unique user profile, clears telemetry,
refuses an existing override.cfg, restores its temporary override and records the
HEAD/dirty state/renderer in var/ci/inventory-transfer-layout-render/manifest.json.
No fixed port or Coordinator lease is needed because the fixture opens no sockets.

Reproduce from this isolated worktree:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot <verified executable> -TestNames player_inventory_transfer_layout_test.gd,player_inventory_transfer_preview_test.gd,player_inventory_handoffs_test.gd,player_inventory_feedback_test.gd,client_inventory_shell_test.gd -OutputDirectory var/ci/transfer-layout-final
./tools/ci/capture-client-inventory.ps1 -Godot <verified executable> -Fixture player_inventory_transfer_layout_test.gd
```

## Workflow and provenance

Scoped feature commit/push and attached draft PR only. No merge, dev-master push,
release, deployment, external messages or public media. The managed worktree and
ignored native evidence remain retained and recoverable for Coordinator review.
First-party code/tests/docs are MIT; no creative assets or new dependencies.
No human approval blocker was encountered; any future approval routes via Coordinator.