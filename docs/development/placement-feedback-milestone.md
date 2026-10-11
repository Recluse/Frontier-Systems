# Modular-machine placement feedback milestone

## Scope and ownership

MachineryPanel owns volatile client intent; MachineryPlacementFeedback derives bounded display data from that intent and scoped observations. MachineryPreview owns decorative geometry. One explicit bootstrap binding connects the panel to its preview. Production/inventory remain the canonical state owners; their command validation, tick cadence, snapshots, schemas and profiling counters are unchanged.

No ghost, footprint, axis or selection record enters inventory, observations or persistence. Decorations contain no collision or picking bodies. Coordinates retain the current millimetre contract and ProceduralWorldInventoryPreview.DISPLAY_ORIGIN; UI values are metres relative to the workbench. Fixed orientation is displayed explicitly because the host does not support machine rotation.

## Player behavior

Select a packed frame, enable **Show placement ghost / footprint**, and edit XYZ coordinates. The ghost shows the existing module envelope and footprint with red +X, green +Y/up and blue +Z markers. Floor placement explains Y=0; Freeform allows existing bounded XYZ translation. Text gives distance from the last observed logical body and an advisory 1.5 m reach estimate. Blue means the displayed position/reach checks pass; orange/red explains an advisory problem. Neither color grants authorization or checks overlap.

Submitting deployment uses the existing authenticated queued command. The ghost turns amber and holds the submitted target while action buttons and coordinate/frame/mode edits are disabled. Host rejection retains the ghost and error for correction. Success retires it; observed deployed frames show a yellow selection footprint and stable ID. World clicks and the frame picker share selection. Hiding/retiring the panel clears decorations; removed frames are never retained as stale selection.

The helper updates only on input, visibility, observation or command-result events. Geometry is cached by feedback signature and remains separate from settled machinery rebuilds. Envelopes are visual approximations of the existing procedural models, not placement collision bounds.

## Verification

Use the repository runner with the executable pinned in FIRST_PLAYABLE_HANDOFF.md:

~~~powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames machinery_placement_feedback_test.gd,machinery_preview_test.gd,machinery_runtime_test.gd -TestTimeoutSeconds 120
~~~

The new focused native test inherits the finite-material workshop integration and exercises real panel commands: rejection of floor Y, frozen pending targets, host-approved freeform placement, snapshot/observation separation, display origin/axes, selection and cleanup. CI discovers the new test automatically on Windows and Linux.

Graphical reproduction (requires a rendering-capable environment):

~~~powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path . --xr-mode off --audio-driver Dummy --rendering-method gl_compatibility --script res://tools/godot/capture_placement_feedback.gd
~~~

The capture tool retains the actual verified workshop and saves ghost, pending and selected views under reports/placement-feedback. It uses local fixture commands and no live services.

## Limits

This milestone does not add placement rules, machine rotation, arbitrary surfaces, overlap authorization, atmospheric rooms, physics authority or ship attachment. Reach uses the last server observation and remains advisory; host ownership, hands, revision and position checks decide the result. Pending commands inherit the existing runtime completion/disconnect behavior. Linux execution, VR/controller usability and human acceptance require their respective environments. No merge, deployment or integration-branch push is authorized by this milestone chat.
