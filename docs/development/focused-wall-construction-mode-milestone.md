# Focused wall construction mode

## Acceptance

MachineryPanel provides a focused Walls mode using its existing placement picker. Wall selection, owned plate selection, pose, preview, build/remove and exact host feedback stay accessible without unrelated machinery actions. Returning to Machinery preserves the saved draft. Pending commands freeze their original target and keep their feedback visible through mode transitions. Desktop and narrow client shells preserve camera space, wrapping, scrolling and keyboard focus. Missing observations clear stale selection and ghosts.

## Scope and verification

Presentation only: no simulation, schema, transport or inventory panel changes. Extend existing wall input, wall feedback, pointer and integrated layout checks with no sockets. Human usability/tutorial, controller/VR and Linux graphical acceptance remain unverified. No release, deployment or public tutorial media.

## Implementation and local evidence

The existing placement picker is now the first control and offers Machinery / Walls. Walls mode hides machinery crafting, assembly, fitting, wiring, powered batches and autolathe controls. The existing physical-item picker remains shared; non-owned or non-plate entries are disabled in Walls mode and restored in Machinery mode. No client resource grants or canonical command changes occur. New-wall placement remains explicit; mode navigation retains inspected stable IDs and saved draft inputs, hides the volatile ghost, and cannot change pending command mode/target. Neutral preview behavior and missing-observation cleanup stay unchanged.

Exact placement feedback and host outcome remain above the active controls. Submission and completion reveal the applicable feedback through the existing parent scroll container. Keyboard focus, metre labels and coordinate/orientation chain are preserved. There is no new simulation owner, tick cadence, persistence/schema, transport, profiling or configuration contract.

Verified with Windows Godot 4.7.2 and the existing bounded runner:

    ./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames wall_input_usability_test.gd,integrated_panel_layout_test.gd,wall_placement_feedback_test.gd -OutputDirectory var/ci/wall-mode-reveal -TestTimeoutSeconds 120

Import, startup and all three tests passed after the final feedback-reveal change (5 checks, zero failures). Before that change, machinery_placement_feedback_test, machinery_preview_test, spatial_wall_runtime_test and world_pointer_picking_test also passed in var/ci/wall-mode-regressions; these unchanged paths retain their evidence. The extended integrated test uses conserved paid domain data in the real client shell at 1920x1080 and 1100x720, with no sockets. It verifies mode visibility, camera area, wrapping, scrolling, Tab/Shift+Tab, exact retained pending payload and feedback, complete rejection outcome, and canonical snapshot isolation. Wall input checks additionally verify owned-plate-only choices and retained settled inspection/draft through mode roundtrips.

An initial integrated fixture used the wrong tab and failed; a subsequent accidental identifier replacement caused a parse failure. Both were corrected before the successful final runs. No captures are needed to resolve remaining implementation uncertainty: existing real-shell/runtime tests establish the presentation contracts. Human usability/tutorial, controller/VR and Linux graphical acceptance remain unverified. Remote Windows/Linux CI and export evidence are reported separately against the pushed head; local results do not establish CI readiness. The worktree remains attached for Coordinator review; merge is left to the Coordinator.
