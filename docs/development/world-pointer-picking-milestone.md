# World pointer picking milestone

Base: `697584ae09845c450a1bbc38fd70fac351684cb0` (merged PR43). Feature: `world-pointer-picking`, draft PR45 targeting `dev-master`; no merge or deployment.

## Behavior and demonstrated defects

Ordinary world clicks now leave the actual client `SubViewportContainer` unfocused. Previously its default GUI focus captured the first click and made `WorldSelectionInput.gameplay_allowed()` reject native physics picking. The one-line focus policy repair restores native stable item, source, workstation and wall handlers without changing shell layout.

The habitat feedback now clears its local selected ring/card on an unhandled empty-space click and clears obsolete inventory proxy highlighting when another target is picked. `ProceduralWorldInventoryPreview.clear_selection()` resets only disposable presentation state. The ray uses the event's viewport-local position after GUI dispatch; it does not consume the event or replace Godot's native target handler. Canonical simulation state, command validation, persistence and schemas are unchanged. Updates occur on input dispatch and existing presentation frames; no new simulation tick work or profiling counters are added.

## Dedicated verification

`tests/godot/world_pointer_picking_test.gd` extends existing deterministic domain-fixture helpers, substitutes a recording remote whose connect method opens no socket, and instantiates the actual `FirstPlayableBootstrap` shell. It pays for a physical wall through canonical command/tick seams and drops a real fixture backpack before freezing the canonical snapshot. All subsequent picks use injected press/release events through the root Window, actual SubViewportContainer forwarding and native collision-object handlers. The test never calls select-target handlers or emits target/button signals to fake picking.

Assertions cover:

- Exact stable root/item identity, feedback and item card; empty-space clearing and repicking.
- Item-to-source and source-to-source switching, exact deposit IDs and real production picker routing.
- Empty source selection clearing without emitting another target signal.
- Workstation routing into the actual recipes tab.
- Exact stable physical wall ID, real Construction tab, read-only observed pose, hidden draft and disabled build.
- Held-look handler and held Left Alt UI cursor, then right-button release before activating a different GUI control; explicit new-wall button activation by pointer.
- GUI button cursor ownership, coordinate-editor focus preventing world retargeting, and picking restored after focus release.
- Byte-identical canonical world snapshots and no queued commands after every inspection/transition.

The dedicated `tools/test-world-pointer-picking.ps1` wraps the unchanged shared CI runner for import/startup plus `world_pointer_picking_test.gd`, `habitat_target_feedback_test.gd` and `world_inventory_preview_test.gd`. Its optional native subprocess has a 60-second bound and uses Compatibility rendering, recording logs and an internal screenshot. Child processes receive disposable APPDATA/XDG data directories for settings; logs, temporary settings and captures stay under ignored `var/ci/world-pointer-picking`. No ports, host, live services, save loading, media upload or generative art are used. PR38 tests/shared runners, core, schemas, guide helpers and integrated-layout work are untouched.

```powershell
./tools/test-world-pointer-picking.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -Native
```

## Evidence and limits

Local Windows Godot 4.7.2 import/startup, the three focused scripts and native injected dispatch pass. Native capture uses NVIDIA RTX 3080 Ti / Compatibility OpenGL; the wall inspection capture was visually inspected with the actual stable wall ID in the panel and target card. Headless verifies handler routing but cannot establish OS mouse capture, so the captured mouse-mode assertion runs only under a native display driver. Fixtures deliberately aim the inspection camera to each unobstructed target; capture gestures may change that camera, so the fixture restores its sightline before subsequent picking checks.

This is injected automation, not human usability acceptance. Physical mouse ergonomics, interaction while right mouse remains held over a second GUI control, physical controller/XR, default Forward+/D3D12 rendering, Linux graphical behavior and live networking remain unverified. Visual selection does not establish reach, permissions or action success. Exact final head and remote CI status are reported in the task handoff, separately from local evidence.

First-party provenance: independently authored MIT GDScript/PowerShell and documentation using existing first-party procedural meshes and engine rendering. No creative assets or dependencies were added.

The app's managed-worktree creation could not resolve this repository's verified origin ref or SHA; a standard isolated Git worktree was created instead. Its attachment was rejected as unmanaged. It remains active for PR review with the branch pushed and recoverable; the unrelated coordinator edit in the primary checkout was preserved.
