extends VBoxContainer
class_name PlayerControlsPanel

## Keyboard/mouse/controller rebinding is a local preference, not world state.
var _binding: String = ""
var _labels: Dictionary = {}
var _status := Label.new()
var _sensitivity := HSlider.new()
var _cancel_button: Button
var _modifier_candidate: InputEventKey


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	var heading := Label.new()
	heading.text = "Controls · click a binding, then press a key or button"
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(heading)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	var cancel := Button.new()
	_cancel_button = cancel
	cancel.text = "Cancel rebinding"
	cancel.pressed.connect(_cancel)
	add_child(cancel)
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	for action in PlayerInputSettings.ACTIONS:
		var label := Label.new()
		label.text = PlayerInputSettings.ACTIONS[action][0]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(label)
		var button := Button.new()
		button.text = PlayerInputSettings.instance().binding_label(action)
		button.pressed.connect(_begin.bind(action))
		grid.add_child(button)
		_labels[action] = button
	var sensitivity_label := Label.new()
	sensitivity_label.text = "Mouse look sensitivity"
	add_child(sensitivity_label)
	_sensitivity.min_value = 0.0005
	_sensitivity.max_value = 0.01
	_sensitivity.step = 0.0001
	_sensitivity.value = PlayerInputSettings.instance().sensitivity
	_sensitivity.value_changed.connect(func(value: float) -> void:
		PlayerInputSettings.instance().sensitivity = value
		var saved: ServiceResult = PlayerInputSettings.instance().save()
		_status.text = "Sensitivity saved." if saved.is_success else saved.message
	)
	add_child(_sensitivity)
	var defaults := Button.new()
	defaults.text = "Restore default controls"
	defaults.pressed.connect(func() -> void:
		_cancel()
		var restored: ServiceResult = PlayerInputSettings.instance().restore_defaults()
		_sensitivity.set_value_no_signal(PlayerInputSettings.instance().sensitivity)
		_status.text = "Defaults restored." if restored.is_success else restored.message
	)
	add_child(defaults)
	PlayerInputSettings.instance().bindings_changed.connect(_refresh)
	visibility_changed.connect(_visibility_changed)
	_visibility_changed()


func _begin(action: String) -> void:
	_binding = action
	_modifier_candidate = null
	PlayerInputSettings.instance().rebinding = true
	PlayerInputSettings.instance().release_all()
	_status.text = "Press a single key, mouse button, controller button or move a controller axis for: %s" % PlayerInputSettings.ACTIONS[action][0]


func _input(event: InputEvent) -> void:
	if _binding.is_empty() or not is_visible_in_tree():
		return
	if event is InputEventMouseButton and _cancel_button.get_global_rect().has_point(get_global_mouse_position()):
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]:
		_modifier_candidate = event.duplicate() as InputEventKey
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and not event.pressed and _modifier_candidate != null and event.physical_keycode == _modifier_candidate.physical_keycode:
		event = _modifier_candidate
	var accepted: bool = (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed) or (event is InputEventJoypadButton and event.pressed) or (event is InputEventJoypadMotion and absf(event.axis_value) >= 0.75)
	if not accepted:
		return
	var duplicates: PackedStringArray = PlayerInputSettings.instance().conflicts(_binding, event)
	var result: ServiceResult = PlayerInputSettings.instance().bind_action(_binding, event)
	_status.text = "Binding saved." if result.is_success else result.message
	if not duplicates.is_empty():
		_status.text += " Shared binding: " + ", ".join(duplicates)
	_binding = ""
	_modifier_candidate = null
	PlayerInputSettings.instance().rebinding = false
	get_viewport().set_input_as_handled()


func _cancel() -> void:
	_binding = ""
	_modifier_candidate = null
	PlayerInputSettings.instance().rebinding = false
	_status.text = ""


func _refresh() -> void:
	for action in _labels:
		_labels[action].text = PlayerInputSettings.instance().binding_label(action)


func _visibility_changed() -> void:
	_cancel()
	PlayerInputSettings.instance().suspend_navigation(is_visible_in_tree())


func _exit_tree() -> void:
	PlayerInputSettings.instance().rebinding = false
	PlayerInputSettings.instance().suspend_navigation(false)
