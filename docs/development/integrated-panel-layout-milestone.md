# Integrated client panel layout verification

The real FirstPlayableBootstrap shell now follows workstation keyboard focus through its outer scroll pane and wraps the shell status label. Queued workstation actions and matching host results reveal their complete feedback after container sorting. Inventory matching receipts also reveal their result when the player has scrolled away during a pending action. These fix observed failures in the full shell that detached panel captures could not establish.

The client uses an overridable presentation transport factory whose production default remains RemoteWorldRuntime. The new fixture supplies a recording adapter that opens no sockets. It instantiates the actual tabs, built-in Default theme selector/header, controls help, habitat view, workstation and inventory panes. The test pays for equipment and loose parts with six existing extraction/unload/refining batches, then applies a real paid fit through the canonical world command queue. Terrain is an empty disposable presentation observation; authentication, connection and long workstation rejection are injected, not network acceptance.

Scope is presentation and verification only. ProductionSimulationSystem, InventorySimulationSystem and ToolSimulationSystem retain canonical state, cadence, persistence, revisions, paid commands and profiling. Navigation preserves the canonical snapshot, pending feedback pins exact stable targets and both production/tool revisions, and the actual paid fit is confirmed only by its matching result. No core, schema, network adapter, persistence, guide helper or input binding changes are included.

## Verification

Windows Godot 4.7.2 passed bounded import/startup, integrated_panel_layout_test, player_inventory_feedback_test and player_inventory_usability_test (five checks, zero failures). The affected production_panel_navigation_test also passed in the preceding focused run; production source did not change after that pass. Existing runners and tests were reused; unrelated broad local suites were not repeated.

The socket-free native Compatibility/OpenGL 3.3 run passed on NVIDIA GeForce RTX 3080 Ti. Automated dimensions are 1920x1080 with a 540 px shell pane and 1100x720 with a 420 px pane. Assertions cover complete wrapped label lines, bounded pane widths, all workstation task routes, nested focus reveal, Tab/Shift+Tab inventory order, focused-pane scrolling, stable pending fields, pending feedback at both window sizes, matching accepted receipt reveal after scrolling away, and complete long rejection feedback without shell expansion. The workstation still needs outer scrolling at both sizes; this milestone establishes navigability and receipt visibility, not a no-scroll layout.

Inspected local ordinary engine captures show the actual theme header, focused workstation action, narrow inventory pending/accepted receipt and long rejection with the habitat view retained inside the window. Physical human input, unaided discovery, other themes, Linux native graphics, controller/VR and authenticated network recovery remain unverified. PR38 owns actual-client input/recovery evidence; its acceptance limits are retained and its shared test/runners are untouched. The guide helper belongs to chat01a12984-faf3-7120-9033-957c34fe9229 and is unchanged.

Reproduce from an isolated checkout:

```powershell
./tools/ci/run-godot-checks.ps1 -Godot <verified executable> -TestNames integrated_panel_layout_test.gd,player_inventory_feedback_test.gd,player_inventory_usability_test.gd -OutputDirectory var/ci/integrated-panel-final
./tools/ci/capture-integrated-panels.ps1 -Godot <verified executable>
```

The native runner refuses an existing override.cfg, isolates a unique user profile and telemetry environment, restores its temporary override and records HEAD, dirty state, renderer and profile in ignored var/ci/integrated-panel-render/manifest.json. It binds no ports and requires no Coordinator port lease. Existing CI discovers the new headless fixture on Windows and Linux without workflow edits. Final exact pushed HEAD and CI status are reported with PR43; older/dirty runs are not represented as frozen-head evidence.

## Workflow and provenance

Base: origin/dev-master 4f63d9d2fce2f25c6ba4868820c944e9eb2094e2 (PR41). Draft PR43 targets dev-master from integrated-panel-layout. Feature commits/pushes only; no merge, deployment or dev-master push. Configuration/environment contracts and example files are unchanged.

First-party source/tests/docs are MIT. No creative assets, third-party artwork or generative imagery were added. Captures use ordinary Godot rendering of existing project content and remain ignored/internal; no gallery, LFS or public media upload. Keep the managed worktree, unique profile and local evidence for Coordinator review. No approval blocker or live-service operation was encountered.
