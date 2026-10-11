# Desktop controls help and panel navigation

The existing six tabs retain their indices: Workstation 0, Inventory 1, Settings 2,
Construction 3, Terrain 4, Guide 5. A compact selector above the native viewport
offers keyboard access to every tab. Controls help expands in a bounded vertical
scroll area and displays the current InputMap labels, including remapped bindings.
Opening help releases capture; closing it restores focus to its toggle. UI cancel
closes help only when focus is inside this helper and rebinding is inactive.

This presentation helper owns no observed world status, history, persistence,
simulation cadence or commands. Existing disconnect clearing remains unchanged.
Guide and Construction descriptions explain existing behavior rather than adding
actions. Native SubViewport picking and movement bindings are unchanged. Settings
binding buttons clip long labels with complete tooltips and its scroll follows focus.

## Acceptance and verification

Port-free tests cover keyboard opening/closing, forward/backward focus traversal,
all six selector destinations, compact sizing, live labels after an in-memory
remap, native unrelated input remaining unhandled, and rebinding isolation.
Use the existing bounded Godot runner; logs stay ignored in var/ci.
Local and exact-head CI results will be recorded before handoff.
No graphical, human, controller or VR acceptance is claimed without captured evidence.
No media upload, release, deployment, merge or integration-branch push is in scope.

## Recorded local verification

Windows Godot 4.7.2 bounded runner passed editor import, startup and
desktop_controls_help_test (including focus-scoped keyboard scrolling).
The same source baseline also passed first_playable_task_guide_test,
habitat_preview_test, wall_input_usability_test and world_inventory_preview_test.
Guide tests include unavailable/partial observations and disconnect clearing.
Those unchanged subsystem tests were not repeated after help-only scrolling edits.

The first click-pass-through assertion failed because Godot's physics-picking
queue marks mouse events handled. The corrected fixture isolates GUI handling
before that queue; this is not actual rendered-world picking evidence.
InputMap remapping stays in memory; no preference save or live connection is used.
No graphical capture, human playthrough, VR/controller or local Linux test was run.
The helper owns no connection-dependent status to retain after disconnect.

CI must be checked on the final PR head; earlier green runs do not certify it.
No fixed ports were acquired, so no port reservation requires release.
