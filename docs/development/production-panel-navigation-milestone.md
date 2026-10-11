# Workstation task navigation

The tutorial readiness frame showed that the workstation required scrolling at 1920 x 1080. LocalProductionPanel previously placed maintenance, full resource observations and all actions in one column. A named task chooser now exposes gather/carry, refine/collect/recycle, equipment fabrication/salvage, maintenance, fluids, observed resources/jobs and other workstation controls. Each task uses a 400 px vertical viewport with focus-following scrolling. Action text wraps to the available width. Guide progress, observed job/pending uncertainty, transfer mass and host command feedback stay above the chooser. Gathering shows exact observed finite source mass in mg, reach and carried payload; unknown records remain unavailable. The existing refining focus route exposes the refine task before returning its control.

This is presentation navigation only. Existing controls are reparented, preserving their callbacks, selections and exact host-derived prerequisites. Canonical simulation owners, paid intents, revisions, pending acknowledgement, disconnect uncertainty, persistence, cadence, profiling and all schemas remain unchanged. No UI state grants resources or predicts completed outputs. PlayerInventoryPanel, targeting, bootstrap, input, machinery/wall command behavior and network are outside this change.

## Verification

Windows Godot 4.7.2 bounded runner import/startup, production_panel_navigation_test, equipment_prerequisites_view_test and first_playable_task_guide_test pass (five checks, zero failures). The navigation test uses a detached world with its runner stopped, checks all named groups at a 420 px viewport, visible actions without horizontal overflow, focus scrolling to the lower equipment action, existing refine entry, exact recipe quotes/source mass, stable blueprint IDs, pending feedback and disconnect uncertainty. Navigation/inspection preserve the captured world snapshot. Equipment coverage retains rejection reasons and immutable pre-tick authority. No broader local suites were repeated.

Native ordinary rendering uses the same detached test through the existing bounded runner:

```powershell
./tools/ci/run-first-playable-render-check.ps1 -Godot 'D:/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' -Route production-navigation
```

Native Compatibility rendering passed on Windows; the gather, refine and selected-equipment captures were inspected locally. At a 420 px logical panel width and 920 px outer viewport, gather/load/unload and refine/collect/recycle fit their task area, while the full equipment quote uses its visible scrollbar. Internal captures are 900 x 1000 with matching logical content scale, avoiding project-window stretch. The existing client shell also contains header/theme controls above this panel, so this detached fixture does not establish that the complete Workstation tab fits without outer scrolling.

Initial head 127c1febd3748eb2de1e85b30520c145c5c51493 failed the Windows/Linux recipe workflow's old direct-root adjacency assertion. The selector and quote remain adjacent in their new task group. The existing workstation_resource_view_test now checks common-parent adjacency and that the existing refine entry makes both controls visible; no quote or authority assertion is waived. Bounded import/startup, workstation_resource_view_test and production_panel_navigation_test passed after this fixture correction (four checks). Native/source layout is unchanged from the inspected captures.

Exact feature-head CI is tracked by draft PR #41. This fixture does not instantiate the full authenticated client, bind a port, use physical keyboard/mouse or establish unaided discovery, human tutorial acceptance, controller/VR or Linux graphical acceptance. The full client acceptance chat owns ports 27849/27850; this milestone uses no ports. Tutorial readiness remains open. Next acceptance: inspect these task groups in the integrated actual client, exercise its pointer/keyboard routes and verify host acknowledgements and recovery through the client UI.

First-party code/docs are MIT. Captures use ordinary Godot Compatibility rendering of existing first-party UI, remain ignored/internal under var/ci, and are never added to a gallery, LFS or public upload. No artwork, third-party creative material or generative imagery is added. Feature commits/PR are authorized; merge, deployment and dev-master pushes are excluded.
