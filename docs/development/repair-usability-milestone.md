# Tool repair usability milestone

## Scope

Presentation-only first Moonbase Alpha-inspired repair slice. LocalProductionPanel consumes existing scoped tool v2 and production observations and submits the existing repair_tool_component command. ToolMaintenanceView formats observations without catalogs, plan preparation, persisted state or canonical mutations.

Select a component explicitly in the workstation panel. Integrity, material, stable ID and installed assembly action availability/missing functions remain visible. The preview describes full maintenance, power/reach/voluntary-action/ownership/revision/energy prerequisites; queued, accepted, rejected and unavailable states are separate. Missing selected IDs never silently retarget. Host disconnect clears observation data and disables submission.

## Current contract gaps

Tool observation v2 exposes integrity_ppm, assembly actions and missing_functions but no per-component operational flag/threshold, cause, maintenance tool requirement, repair quote or repair duration. Production exposes can_operate, powered.construction and energy_joules, but no prospective maintenance cost or specific can_operate failure reason. Therefore the panel labels energy quote unavailable and shows station reserve, reports assembly action blockers without attributing them to a specific part, and leaves energy settlement/revalidation to the existing command owner. No matter repair cost, fault injection, isolation/restart action, predicted recovery, transaction authority or cooperative reservation is invented.

This is tool-component maintenance, not new machinery repair authority. ToolSimulationSystem owns condition; ProductionSimulationSystem atomically settles station energy at the authoritative tick. Existing tool-system v1 / tool observation v2 / production v4 remain unchanged; profiling remains existing owner counters. UI polls at the existing 0.1 s cadence; the helper has bounded scoped-observation traversal and no persistence.

## Verification

The focused repair_usability_test.gd covers healthy/degraded/disabled observations, real stale-revision rejection, paid maintenance acceptance, command double-click guard, retained selected identity, disappearance/reappearance and remote disconnect signals without sockets. Damaged snapshots are test fixtures only. Optional --capture-maintenance writes ignored local PNG evidence under var/ci/repair-usability; headless results do not establish readability.

Verification results and exact CI head are recorded in the PR. No images are published, no deployment or merge is authorized. Multi-client repair logistics and faults remain a separate authority milestone.

Local Windows evidence: Godot 4.7.2 import/startup and repair_usability_test.gd/tool_runtime_test.gd passed. Native OpenGL graphical captures passed at 420 x 760 with a 330 px panel; healthy, degraded, queued, rejected, accepted, disabled, stale-selection and disconnected states were inspected locally. Capture tooling uses no sockets, writes ignored var/ci evidence and bounds the process to 60 seconds. This proves the focused section's layout and local-world command path; it does not establish full-panel scrolling, human play, controller/VR acceptance or two-client repair transactions.
