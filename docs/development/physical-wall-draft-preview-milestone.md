# Unsubmitted physical wall draft milestone

## Scope and contract

This succeeds movement acceptance PR76 with a narrow MachineryPanel / world presentation change. Existing ordinary Godot BoxMesh, footprints and labels are reused; no assets or generated imagery are added. First-party MIT procedural geometry remains authored in machinery_preview.gd. Production and Inventory retain canonical wall IDs, material accounting, placement validation, persistence and fixed-tick command ownership. No schemas, transport, movement bootstrap or inventory/container UI change.

One selected owned physical plate and the applied metre inputs produce one unsubmitted wall preview. The panel reports the exact converted integer millimetre pose and quarter-turn (0 along X, 1 along Z). Its neutral color and UNSUBMITTED WALL PREVIEW label do not predict reach, collision, capacity or host acceptance. Local input constraints remain Y=0, 100 mm grid and existing bounds. The existing observed-wall inspection advice remains separate.

Cancel hides the preview and retains pose, turn and plate selection. Place a new wall resumes that draft and clears settled-wall inspection. Reset explicitly sets the draft to [0, 0, 0] mm / quarter-turn 0 and opens it, without submitting. Existing Enter, Tab / Shift+Tab and orientation controls remain. Selecting an observed wall hides the draft and inspects its stable ID and observed pose.

Pending build/remove identity and pose remain pinned; cancel/reset and duplicate commands cannot retarget them. Missing observation clears world decoration while pending metadata remains available for honest acknowledgment uncertainty. Missing selected plate in owned inventory hides the draft and clears the selector rather than silently retargeting another part, even when shared production still lists that plate. Existing disconnect cleanup supplies the empty observation. Hidden/retired panels still clear decoration. Neither preview nor control transitions consume plate matter, allocate canonical IDs, add collisions or mutate saves.

Updates occur on existing observation/control/result events, with the existing cached decoration signature. There is no new simulation tick, persistence record or profiling contract.

## Verification

Pinned Windows Godot 4.7.2, existing bounded runner:

    ./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -TestNames wall_input_usability_test.gd,wall_placement_feedback_test.gd,machinery_placement_feedback_test.gd,machinery_preview_test.gd,spatial_wall_runtime_test.gd,world_pointer_picking_test.gd,integrated_panel_layout_test.gd -OutputDirectory var/ci/wall-draft-final -TestTimeoutSeconds 120

The wall tests use real conserved paid plate construction and host acceptance/rejection/removal. They check geometry/rotation, canonical snapshot isolation, pending pose retention, observed selection, missing observations, neutral color, explicit label, cancel/resume/reset and keyboard navigation. Existing pointer and real-shell desktop/narrow layout checks cover unaffected picking and focus/scroll behavior.

Windows/Linux native suites and development exports are required by the existing CI workflow on the pushed head. Local headless tests do not establish physical human, controller/VR, Linux graphical or tutorial readiness. No captures are required: geometry is reused and runtime checks assert dimensions, orientation, labels, colors, no collision/shadow, and layout. Current media remain internal. No release, merge or deployment is authorized by this milestone.

Local results: all nine initial Windows checks passed. After tightening owned-plate cleanup and button wrapping, import/startup plus wall input, wall feedback and integrated layout were rerun and passed (five checks, zero failures). The other four results remain applicable to unchanged code paths. Ignored logs/JUnit are in var/ci/wall-draft-final and var/ci/wall-draft-wrap-final. Exact-head remote CI is reported separately on the PR.
