# Alarm presentation without imported assets

`AlarmStatusIndicator` is a reusable presentation-only panel widget. It observes the prototype controller record, draws a color beacon, displays a text status and provides an opt-in tone checkbox. `AlarmToneSynthesizer` generates bounded first-party stereo PCM; no audio recording, sprite, texture, font file or other third-party creative asset is added.

## Visible and audible states

| Controller alarm | Powered presentation |
| --- | --- |
| Quiet | Steady green; silent. |
| Local | Amber, one blink cycle per second; optional pulsed 600 Hz tone. |
| Remote | Red, two blink cycles per second; optional pulsed 900 Hz tone. |
| Disabled | Gray; silent. |
| Faulted | Purple; silent. |

Unpowered, isolated, missing, malformed or zero-integrity controller records suppress tones and show an offline/unavailable presentation. Text accompanies color, so status does not depend on color alone. Audio is off by default and the checkbox is a local presentation preference, not a game command or lawset change.

The widget is a controller alarm monitor, not the physical siren component. Once a trigger raises a persistent controller alarm, removing that trigger module does not clear it or mute an enabled monitor while the controller still has power. Physical emitters, spatial propagation, suit/vehicle audio routing and independent alarm sources remain future systems. Discord/Social SDK still owns player voice/chat; these synthesized tones are ordinary non-voice game effects.

## Ownership and bounds

The bootstrap passes decoded access-controller snapshots into `observe_controller`. The widget never changes those records, submits device actions or stores presentation clocks in world snapshots. The animation clock, audio phases and mute preference are disposable. Headless world bootstrap does not instantiate the panel or play sound.

The generator uses a 22,050 Hz mix rate, amplitude capped at 0.12, and at most 1,024 frames per generation call. A native `AudioStreamGenerator` queues a short buffer; the player applies an additional -18 dB gain. Silence between pulses limits continuous output. Low client frame rates may cause underruns; presentation must never delay simulation to refill audio. Mode/power/mute changes reset phases and stop old playback, and node teardown stops audio.

## Verification

`tests/godot/alarm_presentation_test.gd` checks frame/work limits, finite amplitude-bounded stereo samples, deterministic reset, distinct pitch modes, gated silence, generator start/stop and state handling. It also verifies observation does not mutate controller records. Run with dummy audio to avoid audible output:

```powershell
& 'D:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe' `
  --headless --audio-driver Dummy --path . --script res://tests/godot/alarm_presentation_test.gd
```

Windows checks passed. Actual speaker output, graphical appearance and Linux CI still require validation. This widget is a possible reusable MIT Godot add-on later; packaging, editor configuration and standalone asset documentation would be separate work.
