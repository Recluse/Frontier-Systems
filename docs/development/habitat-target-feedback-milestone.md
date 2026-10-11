# Habitat native target feedback

## Scope and behavior

Base: `227b4bcb2f92dfa2b5e971e3acd1ff87a5120fb0` on `origin/dev-master`. Feature: `codex/habitat-target-feedback`, draft PR targeting `dev-master`; no merge, integration push or deployment.

The procedural habitat now provides a bounded bottom card and projected target/selection rings for existing item, resource source, workstation and wall pick routes. Hints read the current selection binding and distinguish mouse selection/double-click requests from keyboard/controller single-press requests. Wall inspection accurately reports its existing mouse-only route limitation. Collection/extraction are requests, not a guarantee of successful interaction. All command/reach/collision checks remain in their existing owners.

The helper is presentation-only and disposable; it has no save format or authoritative state. Removed/detached/queued-for-deletion/unpickable/disconnected targets clear advice. The existing client disconnect path marks production unavailable; this suppresses all target advice, including retained inventory proxies. UI focus, rebinding and input suspension hide feedback and stop selection input before physics picking. Existing bootstrap, production/inventory panels, network, schemas, persistence and core systems are unchanged.

## Local verification

Windows Godot 4.7.2 bounded import/startup and these checks passed:

- `habitat_target_feedback_test.gd`: real SubViewport keyboard/controller routing with in-memory rebinding; source request semantics; echo/rebinding/UI-focus guards; closest-body occlusion; actual native signal item/source/wall semantics; removed items/walls, unavailable targets/production and disconnected handlers; narrow/tiny viewport bounds.
- `habitat_preview_test.gd`, `world_inventory_preview_test.gd`, `desktop_controls_help_test.gd`: existing habitat snapshot/camera, inventory read-only selection and command bridge, and keyboard help regression checks.

```powershell
./tools/ci/run-godot-checks.ps1 -Godot 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe' -TestNames habitat_target_feedback_test.gd,habitat_preview_test.gd,world_inventory_preview_test.gd,desktop_controls_help_test.gd -TestTimeoutSeconds 120
```

`tools/godot/capture_habitat_target_feedback.gd` passed with native Compatibility/OpenGL rendering on the local NVIDIA RTX 3080 Ti. It pushes mouse events through Godot physics picking (not directly through the handler signal), verifies click/double-click/focus blocking and feedback restoration, and captures `var/ci/habitat-target-feedback/captures/selected-source.png`. The local capture was visually inspected: the selected source ring and bottom card are visible and bounded. PNG/logs stay ignored; no media/LFS upload occurs. No ports are allocated.

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --path . --script tools/godot/capture_habitat_target_feedback.gd --rendering-method gl_compatibility --quit-after 300 --log-file var/ci/habitat-target-feedback-native.log
```

## Focused GUI regression repair

Review identified that the initial `_input` guard could consume the default left mouse selection binding before GUI activation. A regression fixture first reproduced the failure: focus a LineEdit, click another Button using the default mouse binding, and require both activation/focus transfer and unchanged world selection/request counters. The guard now consumes blocked selection only in `_unhandled_input`, after GUI dispatch and before native physics picking. Keyboard/controller routing and rebinding guards remain intact. This matches [Godot's documented Viewport dispatch order](https://docs.godotengine.org/en/stable/classes/class_viewport.html#class-viewport-method-push-input).

The focused headless check verifies controls in the same SubViewport as the habitat guard. The native capture tool verifies actual GUI dispatch in a Window with an instance of the same guard and a GUI Button layered over the world viewport; complete press/release pairs activate that Button without underlying source selection/extraction. Native world picking is checked separately through the habitat SubViewport. Synthetic input explicitly declares mouse entry and uses local handled state so parent-window/OS pointer state does not make the fixture depend on cursor placement. No OS cursor movement, direct Button signal emission or direct target handler invocation is used for these native checks. This is automated engine dispatch, not human acceptance.

## Limits

Headless keyboard/controller fixtures do not establish human ergonomics or physical controller usability. Native graphical coverage uses simulated mouse events and Compatibility rendering; default Forward+/D3D12 appearance, Linux native rendering, every client-panel layout, live-service integration and human acceptance are unverified locally. No visual targeting establishes reach, permission or action success. The existing world selection ray excludes wall bodies for keyboard/controller events; this milestone reports rather than changes that route.

Source/asset provenance: independently authored MIT GDScript controls, rings and engine-native drawing, using existing fonts/materials; ordinary Godot rendering only, no AI image generation or new third-party creative assets. Remote CI must be reported against the exact pushed head; local checks alone do not establish CI success.
