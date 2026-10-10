# Optional VR: Quest 3 PC testing

## What is implemented

Optional OpenXR client presentation is available through the main bootstrap. It supplies stereo headset rendering, native tracked camera/controllers, first-party procedural habitat geometry, a pressure observation label and an input status board. Grip inputs change controller-proxy color; grip/trigger values appear on the board. Room-scale head movement is tracked by the XR runtime, and a stage recenter event keeps user height while resetting the reference frame.

This feature slice is a **PC VR preview**, not a standalone Quest APK. A debug-build [spatial airlock panel](../architecture/xr-spatial-controls.md) now accepts right-hand pointer/trigger selections through the existing queued airlock commands. Grip objects, logical player movement, inventory manipulation and push-off impulses remain pending. Local snap turning and manual seated-height calibration are available; see [comfort controls](../architecture/xr-comfort-controls.md). Smooth locomotion, wrist/PDA menus, haptics, multiplayer pose replication, tracking-loss gameplay handling and full VR controls remain planned. Existing desktop first/third-person navigation stays available in desktop mode.

## Quest 3 and SteamVR setup

1. Install/open Steam and SteamVR on the Windows PC.
2. Install Steam Link on the Quest 3 and connect it to the PC. Valve lists Quest 3 among supported headsets in its [Steam Link headset guide](https://help.steampowered.com/en/faqs/view/0E2C-406B-9135-38A4).
3. Make SteamVR the active OpenXR runtime in SteamVR's OpenXR settings. Godot's [Windows PCVR guide](https://www.khronos.org/assets/uploads/developers/presentations/Godot_guide_to_OpenXR_for_Windows_PCVR.pdf) describes selecting the desktop runtime. Steam Link routes this test through SteamVR; Meta Quest Link can separately use Meta's desktop OpenXR runtime, but that is not the SteamVR test route.
4. Connect the headset/controllers and launch the project from PowerShell:

```powershell
Set-Location 'D:\GitHub\Frontier Systems'
.\tools\launch-client.ps1 -VR
```

The script uses the currently installed console executable under `D:\Godot_v4.7.2-stable_win64.exe\`. Override it with `-GodotPath 'C:\path\to\godot.exe'` on another machine. Steam platform API initialization is not required to test OpenXR tracking; the existing GodotSteam adapter remains separate.

To inspect arguments without launching or contacting a headset:

```powershell
.\tools\launch-client.ps1 -VR -CheckOnly
```

For ordinary desktop mode:

```powershell
.\tools\launch-client.ps1
```

The VR launch passes `--rendering-method mobile --rendering-driver vulkan --xr-mode on -- --vr`. The project defaults keep OpenXR off; it must be enabled at engine startup so graphics initialization can prepare XR. Godot recommends [Mobile for desktop VR](https://docs.godotengine.org/en/stable/tutorials/xr/setting_up_xr.html) and [Vulkan for Windows Mobile/Forward+ XR](https://godotengine.org/article/godot-xr-update-mar-2026/). Desktop rendering retains the existing Forward+/D3D12 project configuration.

If the engine reaches the bootstrap but OpenXR did not initialize, the client shows the ordinary desktop interface with a fallback explanation. Startup alerts are disabled so a missing headset does not require dismissing a modal before fallback. Graphics-driver failures before application startup cannot be handled by that application fallback.

## Hardware checks to report

| Check | Expected result |
| --- | --- |
| Stereo image | One coherent 3D habitat with correct depth, not a flat desktop screen |
| Head tracking | Looking/leaning changes the view naturally |
| Floor and scale | Habitat floor aligns with the runtime's floor space; controller proxies are roughly hand-sized |
| Left/right poses | Each proxy follows its corresponding controller; untracked controllers are hidden |
| Grip | Each tracked hand changes from teal toward gold; its grip value rises |
| Trigger | Corresponding trigger value rises on the status board |
| Aim pointer | Right-hand beam aligns with pointing; an airlock button turns gold on hover |
| Selection | Release then press right trigger on Equalize: feedback queues/applies and chamber pressure changes on simulation ticks; holding does not repeat |
| Safety checks | Opening the inner door before safe equalization is rejected; after equalization, the existing door checks determine whether opening is allowed |
| Occlusion | Habitat walls block the pointer; removing an obstruction while holding trigger cannot select |
| Recenter | Runtime recenter resets horizontal origin/orientation while retaining height |
| Snap turn | Return right stick to center, then push left/right: one 30° view turn per deflection; holding does not repeat |
| Seated mode | Press left X: toggle a 600 mm origin height offset; right A/B adjust the remembered offset by 50 mm |
| Focus/tracking regain | Held controls do not cause a turn or setting change until released and pressed again |
| Performance | Record headset refresh setting, PC GPU, SteamVR frame timing and visible stutter |
| Desktop | Launching without `-VR` does not require a headset or XR runtime |

Record whether the active runtime is SteamVR, connection method, GPU/driver, headset refresh/resolution and any console errors. Hardware results have **not** been verified by Codex; automated checks establish startup policy, resources, scene structure and headset-free physics/command behavior.

## Architecture and authority

`OptionalXRLaunchPolicy` detects an explicit launch request and rejects headless host presentation. `OptionalXRClient` uses `XROrigin3D`, `XRCamera3D`, two grip-pose `XRController3D` nodes and an additional right aim-pose node in the main graphical viewport. It reuses habitat geometry, disables the legacy inspection/walker cameras/input, keeps the world tick rate at 60 Hz and observes pressure at most 10 Hz. Controller feedback is local presentation. Spatial selection queues development airlock commands; headset rendering never changes canonical simulation cadence.

No desktop screen HUD is automatically drawn into headset space. The status board and airlock panel use native 3D text. Further VR PDA/panels should share the existing command layer. Room-scale tracking is currently unconstrained presentation and does not provide authoritative body collision, reach validation or world traversal. The development panel must be replaced with authenticated session/body validation before production use.

`data/xr/frontier_action_map.tres` is a generated first-party resource with one action set: `hand_pose`, `aim_pose`, analogue `grip`/`trigger`, vector `turn` and boolean seated/height actions. It suggests twelve Oculus Touch-compatible bindings for Quest controllers and six Khronos simple-controller bindings (grip/aim poses and trigger). It does not import vendor controller models or add a paid/plugin dependency. Regenerate it with:

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' --headless --xr-mode off --path . --script res://tools/godot/generate_xr_action_map.gd
```

The resource/API design follows Godot's [OpenXR action-map documentation](https://docs.godotengine.org/en/stable/tutorials/xr/xr_action_map.html). First-party code, generated resources and procedural visuals remain MIT. SteamVR/Meta software is installed externally by the player; no additional runtime or creative assets are bundled by this change.

## Verification and next stages

The [simulation-rate benchmark matrix](simulation-rate-benchmark-matrix.md) includes 60, 72 and 90 Hz candidates. Headset refresh is a separate variable; the saved gameplay default remains 60 Hz until rate comparisons, physical VR interactions and timebase migration are validated.

Windows headless editor import, action-map generation and `optional_xr_client_test.gd` passed. The focused test covers default-off/explicit/headless policy, action/profile resources, native rig structure, inactive untracked proxies, disabled desktop walker, idempotent scene construction, unchanged 60 Hz ticks and canonical world isolation. Launcher argument checks passed for desktop and VR profiles. Habitat/camera regressions are included in local checks; Windows/Ubuntu CI includes the XR structural script without activating hardware.

Spatial selection checks cover native ray hits, occlusion, held/focus/stale gates and queued pressure rejection. CI includes the focused spatial script. Next validate Quest 3 stereo/tracking/input, aim alignment, comfort controls and frame timing on the user's hardware. Broader tracking lifecycle and common authenticated interaction intents with server-validated poses/reach remain pending. Physical grip, push-off and inventory actions must retain the existing hand, capability, motion-revision and resource contracts. A native Quest export is a separate future deployment target and requires its own runtime/dependency/export validation.
