extends HBoxContainer
class_name AlarmStatusIndicator

## Controller-state observer. Display clocks/audio are disposable presentation state.
var _alarm_state: String = "quiet"
var _powered: bool = false
var _sound_enabled: bool = false
var _blink_elapsed: float = 0.0
var _lamp: ColorRect
var _label: Label
var _player: AudioStreamPlayer
var _sound_checkbox: CheckButton
var _synth := AlarmToneSynthesizer.new()


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	_lamp = ColorRect.new()
	_lamp.custom_minimum_size = Vector2(24.0, 24.0)
	_lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_lamp)
	_label = Label.new()
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_label)
	_sound_checkbox = CheckButton.new()
	_sound_checkbox.text = "Alarm tone"
	_sound_checkbox.tooltip_text = "Enable this prototype panel's synthesized alarm tone."
	_sound_checkbox.set_pressed_no_signal(_sound_enabled)
	_sound_checkbox.toggled.connect(set_sound_enabled)
	add_child(_sound_checkbox)
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = AlarmToneSynthesizer.MIX_RATE
	stream.buffer_length = 0.1
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.volume_db = -18.0
	add_child(_player)
	_update_presentation()


## Reads already-decoded controller snapshots; no device commands are generated.
func observe_controller(controller: Dictionary) -> void:
	var alarm: Variant = controller.get("alarm_state")
	var power: Variant = controller.get("power_state")
	var integrity: Variant = controller.get("integrity")
	var valid: bool = typeof(alarm) == TYPE_STRING and AccessControllerState.ALARM_STATES.has(alarm)
	valid = valid and typeof(power) == TYPE_STRING and AccessControllerState.POWER_STATES.has(power)
	valid = valid and (typeof(integrity) == TYPE_INT or typeof(integrity) == TYPE_FLOAT)
	valid = valid and is_finite(float(integrity)) and float(integrity) >= 0.0 and float(integrity) <= 1.0
	var next_state: String = String(alarm) if valid else "unavailable"
	var next_power: bool = valid and power == "powered" and float(integrity) > 0.0
	if next_state == _alarm_state and next_power == _powered:
		return
	_alarm_state = next_state
	_powered = next_power
	_blink_elapsed = 0.0
	_synth.reset()
	_stop_audio()
	_update_presentation()


func set_sound_enabled(enabled: bool) -> void:
	_sound_enabled = enabled
	if is_instance_valid(_sound_checkbox):
		_sound_checkbox.set_pressed_no_signal(enabled)
	_synth.reset()
	_stop_audio()
	_update_presentation()


func presentation_snapshot() -> Dictionary:
	return {"alarm_state": _alarm_state, "powered": _powered, "sound_enabled": _sound_enabled,
		"tone_requested": _active() and _sound_enabled}


func _active() -> bool:
	return _powered and _alarm_state in ["local", "remote"]


func _process(delta: float) -> void:
	_blink_elapsed = fposmod(_blink_elapsed + delta, 1.0)
	_update_presentation()
	if not _active() or not _sound_enabled:
		return
	if not _player.playing:
		_player.play()
	var playback := _player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback != null:
		var count: int = mini(playback.get_frames_available(), AlarmToneSynthesizer.MAX_FRAMES)
		if count > 0:
			playback.push_buffer(_synth.generate(count, _alarm_state == "remote"))


func _update_presentation() -> void:
	if _lamp == null or _label == null:
		return
	set_process(_active())
	_label.text = "Alarm: %s%s" % [_alarm_state, " (controller offline)" if not _powered else ""]
	var color := Color("#65717b")
	if _powered:
		match _alarm_state:
			"quiet": color = Color("#52b788")
			"local": color = Color("#ffb703")
			"remote": color = Color("#ef476f")
			"faulted": color = Color("#b784e8")
	if _active():
		var period: float = 0.5 if _alarm_state == "remote" else 1.0
		if fposmod(_blink_elapsed, period) >= period / 2.0:
			color = color.darkened(0.7)
	_lamp.color = color


func _stop_audio() -> void:
	if is_instance_valid(_player):
		_player.stop()


func _exit_tree() -> void:
	_stop_audio()
