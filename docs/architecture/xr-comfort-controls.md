# XR comfort controls

## Scope and defaults

`XRComfortPolicy` under `src/presentation/xr/` validates local settings and gates discrete input actions. `OptionalXRClient` applies those actions to the tracked origin, not the canonical body, inventory, gravity, grip or motion owners. Simulation stays at 60 Hz. This remains a local PC VR preview; snap turning changes view orientation, not authoritative locomotion.

The default fixture `data/xr/comfort.default.v1.json` matches the policy defaults: 30° snaps, stick engage at 750 permille, release at 250 permille, standing mode and a remembered 600 mm seated offset. Allowed angles are 0 (disabled), 15, 30, 45 or 60°. Height offset is integral 0..1000 mm. Release must be strictly below engage. Schemas codify settings and input observation v1; runtime adds threshold ordering and finite-number checks.

## Quest-compatible controls

| Control | Action |
| --- | --- |
| Right thumbstick horizontal | One configured snap turn; positive input turns right |
| Left X | Toggle standing/seated presentation |
| Right A | Increase remembered seated offset by 50 mm |
| Right B | Decrease remembered seated offset by 50 mm |

These are suggested Oculus Touch bindings; the XR runtime supplies actual controller input according to its action map. The simple-controller fallback has no thumbstick/seated/height bindings. Settings can still be configured in the local JSON preferences file before the next launch. The action generator defines eight actions and twelve Touch bindings, including separate grip and aim poses, with no conflicting duplicate input paths. See [spatial airlock controls](xr-spatial-controls.md) for trigger selection.

Seated mode adds the configured height to `XROrigin3D.position.y`, shifting the headset and both tracked hands together. Standing mode applies no height offset while retaining the remembered setting. A/B adjust the remembered offset in either mode; it becomes visible only when seated mode is enabled. This is a manual view calibration, not a physical player height or body collision adjustment.

## Input gates and transforms

Right-stick input requires focused OpenXR session state and tracked right controller. Left X requires focused session and tracked left controller; height buttons require the right controller. The adapter polls `OpenXRInterface.get_session_state()` so it does not depend on receiving an initial focus signal. Grip/trigger visual feedback also clears while unfocused.

Every input starts unarmed. The stick must pass the release threshold before a deflection reaches the engage threshold. After a turn, holding the stick or crossing directly to the opposite extreme produces no further turn until neutral. Buttons similarly require an observed release before one press action. Focus/tracking loss, invalid observations, recenter and settings replacement reset the relevant gates. Regaining tracking with a held control does not replay an action. Simultaneous A/B press edges cancel the height delta.

Snap rotation uses the current headset world position as its horizontal pivot. It rotates the whole origin about its vertical axis and compensates horizontal origin translation so the camera stays at the same point even when the user is standing away from the room-scale origin. It does not set a tracked camera/controller pose directly or scale the world. This preview assumes an upright origin in its existing habitat frame; moving/rotated assemblies need future frame-aware integration.

`sample_input()` returns v1 action data (`yaw_degrees`, `toggle_seated`, `height_delta_mm`) without file access or world mutation. `consume_comfort_input()` applies the local transforms and optional preference save. `apply_comfort_settings()` validates before replacing settings; persistence failure retains the live setting and reports a warning rather than rolling back the view. These presentation helpers are not network authorization APIs.

## Preference persistence

Settings live at `user://xr-comfort.v1.json`, outside world snapshots. Reads are limited to 4096 bytes and a versioned exact JSON object. Missing files use defaults; unreadable, oversized, malformed or unsupported records report failure and the active XR client uses defaults with status feedback. Input gates and origin transforms are not persisted.

Writes occur only on an actual setting change, not every frame or held button. They use a sibling temporary file, close/flush it and replace the destination through native `DirAccess.rename_absolute()`. Failed replacement reports the save failure and removes the temporary file. Windows replacement of an existing destination is covered by the focused check. This is small synchronous local preference I/O in presentation, not a promise-based persistence service or a durable world transaction. Further VR frame profiling should measure setting-change costs on the user's hardware.

Preference APIs accept only a flat `user://` JSON filename, excluding path separators, traversal and drive syntax. Tests use process-specific temporary filenames and never touch the actual default preferences. No external runtimes, art or dependencies were added; first-party settings/resources remain MIT.

## Verification

Windows import, action-map generation, `xr_comfort_test.gd` and `optional_xr_client_test.gd` passed. Checks cover initial/held/neutral/reversed sticks, direction/angle, focus and tracking regain, button edges, invalid numbers/thresholds/heights, disabled turns, default/missing/bounded preferences, atomic existing-file replacement, JSON recovery, path rejection, a nonzero room-scale camera pivot, seated offsets, non-repeating height changes and canonical/tick-rate isolation. Native Quest controls, stereo rendering, recenter/comfort perception and live frame timing remain unverified. Windows/Ubuntu CI includes the focused scripts; Linux/remote execution has not been verified locally.

Godot APIs are documented in [OpenXRInterface](https://docs.godotengine.org/en/stable/classes/class_openxrinterface.html), [XRController3D](https://docs.godotengine.org/en/stable/classes/class_xrcontroller3d.html) and the [XR action map](https://docs.godotengine.org/en/stable/tutorials/xr/xr_action_map.html).
