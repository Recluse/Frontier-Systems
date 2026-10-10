extends SceneTree

## Deterministic presentation/PCM checks; does not require a physical audio device.
var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var synth := AlarmToneSynthesizer.new()
	_check(synth.generate(-1).is_empty(), "negative audio requests must generate no frames")
	var frames: PackedVector2Array = synth.generate(100000)
	_check(frames.size() == AlarmToneSynthesizer.MAX_FRAMES, "PCM work must be clamped")
	for frame in frames:
		_check(is_finite(frame.x) and frame.x == frame.y and absf(frame.x) <= AlarmToneSynthesizer.AMPLITUDE + 0.000001, "stereo waveform must be finite and amplitude-bounded")
	synth.reset()
	var local: PackedVector2Array = synth.generate(32)
	synth.reset()
	_check(local == synth.generate(32), "reset must reproduce deterministic frames")
	synth.reset()
	_check(local[1] != synth.generate(32, true)[1], "remote mode must use a distinct pitch")
	var silent: int = 0
	synth.reset()
	for _block in range(30):
		for frame in synth.generate(AlarmToneSynthesizer.MAX_FRAMES):
			if frame.x == 0.0:
				silent += 1
	_check(silent > AlarmToneSynthesizer.MAX_FRAMES, "local tone must include silence rather than a continuous siren")
	var indicator := AlarmStatusIndicator.new()
	root.add_child(indicator)
	var state := {"alarm_state": "local", "power_state": "powered", "integrity": 1.0}
	var before: Dictionary = state.duplicate(true)
	indicator.observe_controller(state)
	_check(not indicator.presentation_snapshot()["tone_requested"], "sound must default off")
	indicator.set_sound_enabled(true)
	_check(indicator.presentation_snapshot()["tone_requested"], "opt-in local alarm must request tone")
	indicator._process(1.0 / 60.0)
	_check(indicator._player.playing, "enabled alarm must start generator playback")
	_check(state == before, "observation must not mutate controller records")
	state["power_state"] = "isolated"
	indicator.observe_controller(state)
	_check(not indicator.presentation_snapshot()["tone_requested"], "isolation must suppress tone")
	_check(not indicator._player.playing, "isolation must stop generator playback")
	state["power_state"] = "powered"
	state["alarm_state"] = "remote"
	indicator.observe_controller(state)
	_check(indicator.presentation_snapshot()["alarm_state"] == "remote" and indicator.presentation_snapshot()["tone_requested"], "remote alarms must remain distinct")
	for mode in ["quiet", "disabled", "faulted"]:
		state["alarm_state"] = mode
		indicator.observe_controller(state)
		_check(not indicator.presentation_snapshot()["tone_requested"], "inactive/disabled/faulted modes must not request tone")
	state["alarm_state"] = "local"
	state["integrity"] = 0.0
	indicator.observe_controller(state)
	_check(not indicator.presentation_snapshot()["tone_requested"], "broken controller must suppress tone")
	indicator.observe_controller({"alarm_state": "local", "power_state": "powered", "integrity": NAN})
	_check(indicator.presentation_snapshot()["alarm_state"] == "unavailable", "malformed observations must show unavailable")
	indicator.free()
	# Native audio retirements are released by the mixer after stop/teardown.
	await create_timer(0.15).timeout
	if _failures == 0:
		print("Alarm presentation and bounded synthesis scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
