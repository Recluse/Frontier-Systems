# Held-look UI activation milestone

Successor to PR45, base `8499e4f9f0b91906c136171748a2b4e4a7a0058e`. Branch `held-look-ui-activation`, draft PR48 targets `dev-master`. One agent; no merge, deployment, dev-master push or media publication.

## Demonstrated behavior and ownership repairs

The actual client's root GUI latched the RMB press to its SubViewportContainer. With RMB still held, exposing the cursor using Left Alt did not allow a left click on another GUI control: the real new-wall button received no GUI input. Godot's [4.7 viewport dispatch](https://github.com/godotengine/godot/blob/4.7-stable/scene/main/viewport.cpp) retains mouse focus across additional held buttons; the [container implementation](https://github.com/godotengine/godot/blob/4.7-stable/scene/gui/subviewport_container.cpp) normally forwards positional events during GUI dispatch. Consulted as dependency behavior documentation; no upstream code copied.

FirstPlayableBootstrap now forwards only the preview's mouse look gesture through the actual SubViewport before root GUI hit-testing can latch it. Hit bounds, visible surface and gameplay/focus eligibility gate the press. A retained viewport routes release over another UI control and Escape even when an editor would consume it; coordinate transforms and stretch shrinking are preserved. Ordinary world selection retains native container/physics picking. PlayerInputSettings now checks root and owner-viewport GUI focus when granting capture or sampling navigation. Releasing Alt with an editor focused keeps the cursor visible and blocks movement/look; releasing Alt without editor focus recaptures the existing held-look owner.

Only volatile presentation/input ownership changes. Canonical world owners, simulation tick cadence, validation, persistence and schemas are unchanged. Dispatch and existing local character physics frames perform the checks; no canonical tick work, dependencies or profiling signals were added. Mode changes, Escape, release, rebinding/suspension and window focus loss retain their existing ownership cancellation contracts.

## Dedicated acceptance fixture

`tests/godot/held_look_ui_activation_test.gd` reuses PR45's domain helpers and socket-free PointerClient/recording adapter in its own scene-tree route. A paid wall and dropped backpack come from existing command/tick fixture seams; the canonical fixture is frozen before all inspection. No target handlers or button signals are invoked as substitutes for input. Actual Window/SubViewport dispatch and native collider picking select the stable wall and activate real UI buttons.

Assertions cover held RMB plus Left Alt and a pointer click on the real new-wall control, both Alt-release paths, unchanged camera pose during UI handoff, focused coordinate editing blocking movement/look/world retargeting, Escape with RMB held and editor focused, RMB release over UI, restored exact wall picking, the actual First person camera button, sampled W, character UI activation, and fresh gesture recovery after window focus loss. Focus loss/return use propagated Window notifications; this is not an OS focus switch. W reaches a habitat collider late in recovery, so recovery asserts W sampling and a reverse step separately to prove real collision-aware motion. Every inspection/handoff group checks byte-identical canonical JSON and zero recorded commands, plus exact counts for unintended item/source/workstation/wall selections.

`tools/test-held-look-ui-activation.ps1` wraps the unchanged shared CI runner for import/startup, this fixture, PR45's pointer regression and local character navigation. Optional native execution uses Compatibility rendering, XR off, a 60-second process bound, ignored internal capture/logs and disposable APPDATA/XDG settings. An ignored manifest records source HEAD, starting dirty state, timestamps and headless/native results. No sockets, hosts, ports, save loading or uploads. PR45 fixture, PR46 integrated script, inventory fixture, core and schemas remain untouched.

```powershell
./tools/test-held-look-ui-activation.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -Native
# Existing socket-free native input regression, no lease required:
./tools/ci/run-tutorial-readiness-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' -InputOnly
```

## Evidence and limits

Local Windows Godot 4.7.2 import/startup and all three focused scripts pass (five headless checks, zero failures). Dedicated native injected acceptance and the existing native input regression pass on RTX 3080 Ti, Compatibility/OpenGL 3.3. Logs/JUnit/manifest/capture stay under ignored `var/ci/held-look-ui-activation`; the regression has its own ignored tutorial-readiness manifest. The inherited pointer re-entry helper can emit a harmless already-exited viewport warning after capture changes; no script/error diagnostics occur. The internal editor-handoff capture is ordinary actual-client rendering, visually inspected separately. Exact final commit and current CI status are supplied in the handoff; iteration results do not establish exact-head CI.

Headless cannot establish native mouse capture or sampled navigation while captured, so those assertions run only with a native display driver and are explicitly reported as not run headlessly. Physical input, OS focus switching, human usability, controller/VR, default Forward+/D3D12, Linux graphical behavior, networking and packaged execution remain unverified. A green injected route does not meet the human tutorial gate.

First-party provenance: independently authored MIT GDScript/PowerShell/docs using existing first-party procedural meshes and ordinary engine rendering. No creative assets, generative imagery or imported dependency code added. The managed worktree remains active and recoverable on its pushed draft branch for review.
