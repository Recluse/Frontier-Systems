# World context label readability milestone

## Result and boundary

Based on integration `98b5be2`, refinery/workstation, resource-source, terrain-cell and tray text now uses bounded camera-aware viewport cards. Cards wrap complete observed text, avoid one another and reserve the existing selected-item card. Leaders point at the true display target. Camera movement needs no observation rebuild; hidden, removed, behind-camera and offscreen targets disappear. Crowding/very narrow viewports suppress context rather than truncating instructions; overlays retain the actionable detail. See [presentation contract](../architecture/world-context-labels.md).

This is disposable presentation only: canonical owners, commands, schemas, persistence, bootstrap, native pick areas and item selection card/leader are unchanged. Machinery panel and wall feedback are outside scope.

## Verification

Windows Godot 4.7.2 bounded import/startup and five focused tests passed: `world_context_label_test.gd`, `world_inventory_preview_test.gd`, `player_inventory_feedback_test.gd`, `terrain_runtime_test.gd`, `machinery_runtime_test.gd`. Logs/JUnit: ignored `var/ci/context-final`. After moving source mass onto its own line, import/startup and the two layout/inventory preview tests passed again at exact source `cc3dbc140bee0f6fc718ddf5914f03d7d6db40a1` (`var/ci/context-exact-source`).

Exact-head Ubuntu CI at e2a223f exposed a nested-viewport lifecycle failure in habitat_preview_test.gd: immediate shared-layer creation during _ready attempted to add a child while its viewport was busy. The presentation-only fix defers installation, reuses the named layer across anchors and allocates nothing if an anchor is destroyed before the deferred call. The failing habitat test plus label/inventory preview regressions pass after this fix (var/ci/context-lifecycle-fix).

The graphical `capture_world_context.gd` route passed with **zero failures** at lifecycle-fix source ec0df251d856002b5620b81c39e0c9673c78ddd8, using actual root-window input and D3D12/NVIDIA rendering. Checks cover native canister picking, item card reservation, separated complete context cards and true projected anchors, camera movement, 960x700 root resize, explicit label hiding, accepted pickup/drop, pending-before-ack, stale-revision rejection and socket disconnect. Logs: `var/ci/context-graphical`. Port 27864 was independently prechecked free, used instead of the shared 27849 reservation and confirmed released after exit. Only an ephemeral in-memory world and loopback host/client were used; event URLs/tokens were cleared.

A clean overview was visually inspected and retained as an [internal LFS gallery candidate](../gallery/world-context-labels/README.md); other frames remain ignored test evidence. No external gameplay-image publication.

## Review and limits

Draft [PR #20](https://github.com/Valgorithms/Frontier-Systems/pull/20) targets `dev-master`. Branch `codex/world-context-labels` is isolated in a managed worktree. Primary checkout edits were untouched. Initial connector PR creation failed with 403 and local CLI authentication was invalid; the Coordinator created the draft through its authorized working route. No credential helper probing.

Windows/Ubuntu CI is required for the final pushed head. Local checks do not establish Linux execution. No human input, VR/controller, Linux graphical, real occlusion or authoritative geometry/reach acceptance is claimed. No merge, integration-branch push, release or deployment is authorized or performed.
