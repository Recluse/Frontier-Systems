# Target feedback readability

Base: `54a90a11b603f87cffccded44f5aeb5701f50611` (`origin/dev-master`). Feature branch: `target-feedback-readability`; draft PR targets `dev-master`. No merge, integration push or deployment is authorized by this milestone.

## Behavior and ownership

The previous 540-pixel, 90-pixel card ellipsized essential authority advice even at 1920x1080, and selection replaced that advice. HabitatTargetFeedback now wraps four independent rows: hover identity, current binding/action request, selected identity, and reach/permission/resources revalidation with explicit uncertainty about success. The card uses at most 720 pixels of width, 12-pixel viewport margins, content-driven height and 12-point text below 480 pixels of card width (16 otherwise). Complete advice hides if its required height cannot fit; no row truncates. Viewports below 240x180 remain suppressed.

The helper owns disposable local presentation sampled each physics frame. Existing production/inventory handlers and simulation tick validation own commands, reach, permission and resources. No persistence/schema, authority, input routing, profiling, geometry, bootstrap or service boundary changes. Mouse-ignore, focus/rebinding guards and marker drawing remain in place. Different hover/selected identities are labelled separately; selected state never removes the warning. Existing wall mouse-only limitations remain explicit.

## Verification

Windows Godot 4.7.2 import/startup plus habitat_target_feedback_test, habitat_preview_test, world_inventory_preview_test and desktop_controls_help_test passed using the versioned bounded runner. Focused regressions cover complete wrapped rows/card bounds at 1920x1080, 640x480 and 360x640, long and differing identities, unbound input, no ellipsis, and retained mouse-ignore. Existing native route/occlusion/removal/disconnect/focus/rebinding tests remain enabled.

The ordinary Compatibility/OpenGL capture tool on NVIDIA RTX 3080 Ti checks native mouse selection/double-click requests and GUI focus blocking before capturing those three exact texture sizes. Screenshot hover rows use an explicit local presentation fixture after sampling is paused, because SubViewport.get_mouse_position follows the physical OS cursor rather than synthetic push_input motion. This is graphical layout evidence, not native OS hover ergonomics. Selected rings come from real native selection; no command route is bypassed for native input checks. PNGs are visually inspected and retained only in ignored var/ci/habitat-target-feedback/captures; logs/JUnit are in var/ci/target-readability and var/ci/target-readability-native.log.

No ports, sockets, credentials, media/LFS/public uploads or generated imagery are used. Provenance: independently authored MIT GDScript controls and engine-native drawing, existing engine fonts/materials; ordinary Godot rendering only, no new third-party assets.

## Limits

No human, physical controller, VR, integrated-client-panel, live-service, default Forward+/D3D12 or Linux native graphical acceptance is claimed. Long records may consume substantial vertical space; complete card suppression on insufficient height is preferable to a partial authority warning. Remote CI is separately checked against the pushed head. This milestone does not authorize merge or deployment.
