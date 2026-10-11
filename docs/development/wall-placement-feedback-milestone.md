# Physical-wall placement feedback milestone

Current draft semantics are refined by [the unsubmitted physical wall draft milestone](physical-wall-draft-preview-milestone.md): neutral geometry-only presentation, millimetre pose, cancel/reset, and stale-plate cleanup. The advice/color and missing-observation behavior below describe the original milestone.

## Scope and ownership

MachineryPanel owns volatile selected plate, target coordinates, orientation and pending wall intent. WallPlacementFeedback derives display-only advice from private inventory and production v7 observations. The existing MachineryPreview decoration renderer shows both machine and wall previews; its selected footprint uses the observed wall orientation independently from a new build target. FirstPlayableBootstrap owns scene binding and disconnect cleanup.

Production and Inventory remain canonical owners. Fixed-tick wall_build / wall_remove validation, inventory ownership and plate material accounting, movement keepouts, persistence, v7 observations and profiling contracts are unchanged. No new item grants, canonical walls, simulation systems, persisted feedback records or external services are introduced. Updates run on UI, observation, visibility and command-result events; cached geometry signatures avoid rebuilding unchanged decorations.

## Player route

1. Produce and materialize a physical plate through the existing finite resource loop. Select it in the module / canister selector.
2. Select **Physical wall placement preview**, enable **Show placement ghost / footprint**, and enter metres relative to the workbench. SpinBoxes retain 0.1 m increments and ±100 m bounds.
3. Choose Wall along X or Wall along Z. A translucent 1 × 2 × 0.1 m panel, correctly oriented footprint and positive XYZ markers use the existing DISPLAY_ORIGIN. Text advises floor Y=0, grid bounds and estimated 1.5 m reach from the latest observed body position. Machine Freeform does not allow floating walls. Colors remain advisory; overlap, ownership, hands and revision are host decisions.
4. Build submits the unchanged authenticated intent. Pending targets retain submitted plate identity, position and quarter turn even if controls change programmatically. All action buttons and target selectors disable while awaiting a result, and duplicate actions are ignored. Success retires the ghost; rejection preserves an enabled preview for correction.
5. Clicking a physical wall or choosing it in the wall selector activates its stable observed selection footprint and removal advice. The footprint follows its recorded orientation. Removal freezes the target wall ID and pose while awaiting the host; success recovers one real owned plate and retires the observed wall.
6. Hidden or retired panels clear decorations. Missing plates/walls and empty observations clear stale feedback. Disconnect fails pending commands through the existing remote runtime, clears selection and observation data, and removes stale settled wall and machinery colliders.

Ghosts, footprints, labels and axes have no CollisionObject3D, picking surface, physics state or shadow. Only settled observed walls retain real static colliders. Client decorations never authorize construction or alter room sealing, topology, inventory, damage, movement or world saves.

## Reproduction and verification

Use the pinned Windows Godot 4.7.2 executable and the existing bounded runner:

~~~powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames wall_placement_feedback_test.gd,machinery_placement_feedback_test.gd,machinery_preview_test.gd,spatial_wall_runtime_test.gd -TestTimeoutSeconds 120 -OutputDirectory var/ci/wall-placement-feedback
~~~

wall_placement_feedback_test.gd inherits the finite conserved spatial-wall fixture. It checks physical plate selection, X/Z geometry and footprints, DISPLAY_ORIGIN/height, no collision/picking/shadow, advisory floor/grid/reach, observed selection pose independent from target controls, frozen pending build/remove targets, duplicate suppression, actual host acceptance/rejection, plate preservation/recovery, snapshot/observation isolation, hiding/retirement and stale observation cleanup. Existing machine and wall regressions remain functional. CI discovers this new native test on Windows and Linux.

The graphical capture requires native rendering and its own free loopback port 27852:

~~~powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path . --xr-mode off --audio-driver Dummy --rendering-method gl_compatibility --script res://tools/godot/capture_wall_placement_feedback.gd
~~~

The capture tool first completes the finite wall/material integration fixture, then authenticates the actual client UI with a temporary local host. It checks floating-wall rejection, one queued build despite duplicate calls, a native ray hitting the settled collider through the decorative footprint, wall input-event selection, removal, exactly one recovered plate, rebuild and disconnection with a pending removal. Transport pauses for a rendered frame to expose genuine pending feedback. It uses no real player saves or external services, never stops another listener, and cleans up its client/host/world.

Captured first-party MIT UI evidence: [X ghost](../../reports/wall-placement-feedback/ghost-x.png), [Z ghost](../../reports/wall-placement-feedback/ghost-z.png), [pending](../../reports/wall-placement-feedback/pending.png), [selected wall](../../reports/wall-placement-feedback/selected.png). The native ray and input-event checks do not establish manual mouse/controller usability.

Final Windows verification passed against integration baseline bef1b39622a6b0fbbc19f1b10f02819f3314d82d: import/startup plus all four focused scripts (six checks, zero failures); serialized first_playable_acceptance.gd with actual authenticated two-client transport and temporary checkpoint storage (36.17 s, import/startup included, three checks and zero failures); and the native graphical route (zero failures and no Godot error diagnostics). All four regenerated captures were inspected for orientation, footprint, pending state and readable selected-wall advice. Final native logs/JUnit are under ignored var/ci/wall-placement-feedback and var/ci/wall-placement-cooperative; graphical.log is under the former. Port 27849 was inspected for unexpected listeners, used only during the Coordinator-granted acceptance window, and released promptly. The graphical host used its separate port 27852. CI must pass on the final pushed head before coordinator merge.

## Limits

Local verification uses Windows, Godot 4.7.2 and Compatibility/OpenGL on an NVIDIA RTX 3080 Ti. Linux execution and the complete CI/export matrix are separate remote gates on the final pushed head. Forward+/D3D12, VR/controller interaction, manual mouse ergonomics and human gameplay acceptance are not established by these captures. No PHP, production/inventory schemas, canonical placement or movement rules, terrain, persistence, staged work, ship attachment or atmosphere topology are changed. This branch is pushed for coordinator review; it does not merge, deploy or push dev-master.
