extends RefCounted
class_name AlarmToneSynthesizer

## First-party bounded PCM generation. No samples, files or simulation state.
const MIX_RATE: float = 22050.0
const MAX_FRAMES: int = 1024
const AMPLITUDE: float = 0.12
var _oscillator_phase: float = 0.0
var _pulse_phase: float = 0.0


func reset() -> void:
	_oscillator_phase = 0.0
	_pulse_phase = 0.0


func generate(requested_frames: int, remote_alarm: bool = false) -> PackedVector2Array:
	var count: int = clampi(requested_frames, 0, MAX_FRAMES)
	var frames := PackedVector2Array()
	frames.resize(count)
	var frequency: float = 900.0 if remote_alarm else 600.0
	var period: float = 0.5 if remote_alarm else 1.0
	for index in range(count):
		var sample: float = sin(_oscillator_phase * TAU) * AMPLITUDE if _pulse_phase < 0.25 else 0.0
		frames[index] = Vector2(sample, sample)
		_oscillator_phase = fposmod(_oscillator_phase + frequency / MIX_RATE, 1.0)
		_pulse_phase = fposmod(_pulse_phase + 1.0 / MIX_RATE, period)
	return frames
