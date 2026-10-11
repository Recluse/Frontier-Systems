extends Node
class_name PlayerInputSettings

## Local preferences and cursor ownership only; never grants simulation authority.
signal bindings_changed
const PATH: String = "user://player-controls.v1.json"
const ACTIONS: Dictionary = {
	"move_forward": ["Move forward", KEY_W], "move_back": ["Move backward", KEY_S],
	"move_left": ["Move left", KEY_A], "move_right": ["Move right", KEY_D],
	"jump": ["Jump", KEY_SPACE], "sprint": ["Sprint", KEY_SHIFT],
	"fly_down": ["Free camera descend", KEY_Q], "fly_up": ["Free camera ascend", KEY_E],
	"look": ["Hold to look / navigate", -MOUSE_BUTTON_RIGHT],
	"ui_cursor": ["Hold to interact with UI", KEY_ALT],
	"release_cursor": ["Release camera capture", KEY_ESCAPE],
	"world_select": ["Select world object (double-click to use)", -MOUSE_BUTTON_LEFT],
	"zoom_in": ["Overview zoom in", -MOUSE_BUTTON_WHEEL_UP],
	"zoom_out": ["Overview zoom out", -MOUSE_BUTTON_WHEEL_DOWN],
	"inventory": ["Toggle inventory", KEY_I], "settings": ["Open controls settings", KEY_F10],
	"switch_hand": ["Switch active hand", KEY_X], "use_tool": ["Use active tool", KEY_F],
	"camera_first": ["First person", KEY_F1], "camera_third": ["Third person", KEY_F2],
	"camera_overview": ["Overview", KEY_F3],
	"ui_accept": ["UI confirm", KEY_ENTER], "ui_cancel": ["UI cancel", KEY_ESCAPE],
	"ui_left": ["UI left", KEY_LEFT], "ui_right": ["UI right", KEY_RIGHT],
	"ui_up": ["UI up", KEY_UP], "ui_down": ["UI down", KEY_DOWN],
	"ui_focus_next": ["UI next control", KEY_TAB], "ui_focus_prev": ["UI previous control (default Shift+Tab)", KEY_TAB]
}
var sensitivity: float = 0.003
var rebinding: bool = false
var _owner: Node
var _suspended: bool = false


static func instance() -> PlayerInputSettings:
	return (Engine.get_main_loop() as SceneTree).root.get_node("PlayerControls") as PlayerInputSettings


func _ready() -> void:
	_reset_map()
	if not FileAccess.file_exists(PATH):
		return
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null or file.get_length() > 32768:
		return
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return
	var value: Dictionary = parser.data
	if value.get("schema_version") != 1 or typeof(value.get("bindings")) != TYPE_DICTIONARY:
		return
	for action in ACTIONS:
		var event: InputEvent = _decode(value["bindings"].get(action, {}))
		if event != null:
			_set_binding(action, event)
	var saved: Variant = value.get("sensitivity")
	if (typeof(saved) == TYPE_FLOAT or typeof(saved) == TYPE_INT) and is_finite(float(saved)) and float(saved) >= 0.0005 and float(saved) <= 0.01:
		sensitivity = float(saved)


func _reset_map() -> void:
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var code: int = ACTIONS[action][1]
		var event: InputEvent
		if code < 0:
			var mouse := InputEventMouseButton.new()
			mouse.button_index = -code
			event = mouse
		else:
			var key := InputEventKey.new()
			key.physical_keycode = code
			if action == "ui_cursor":
				key.location = KEY_LOCATION_LEFT
			if action == "ui_focus_prev":
				key.shift_pressed = true
			event = key
		_set_binding(action, event)


func bind_action(action: String, event: InputEvent) -> ServiceResult:
	if not ACTIONS.has(action) or _decode(_encode(event)) == null:
		return ServiceResult.failure(&"invalid_binding", "Choose a keyboard key, mouse button, or controller button/axis.")
	release_all()
	_set_binding(action, _decode(_encode(event)))
	bindings_changed.emit()
	return save()


func restore_defaults() -> ServiceResult:
	release_all()
	_reset_map()
	sensitivity = 0.003
	bindings_changed.emit()
	return save()


func save() -> ServiceResult:
	var bindings: Dictionary = {}
	for action in ACTIONS:
		bindings[action] = _encode(InputMap.action_get_events(action)[0])
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		return ServiceResult.failure(&"controls_save", "Controls applied, but preferences could not be saved.")
	file.store_string(JSON.stringify({"schema_version": 1, "bindings": bindings, "sensitivity": sensitivity}))
	file.flush()
	return ServiceResult.success() if file.get_error() == OK else ServiceResult.failure(&"controls_save", "Controls applied, but writing preferences failed.")


func binding_label(action: String) -> String:
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	return events[0].as_text() if not events.is_empty() else "Unbound"


func conflicts(action: String, event: InputEvent) -> PackedStringArray:
	var result := PackedStringArray()
	var encoded: Dictionary = _encode(event)
	for other in ACTIONS:
		if other != action and _encode(InputMap.action_get_events(other)[0]) == encoded:
			result.append(ACTIONS[other][0])
	return result


func request_capture(owner: Node) -> void:
	if rebinding or _suspended or Input.is_action_pressed("ui_cursor") or _gui_has_focus(owner):
		return
	_owner = owner
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func can_navigate(owner: Node) -> bool:
	return is_instance_valid(_owner) and _owner == owner and not rebinding and not _suspended and not Input.is_action_pressed("ui_cursor") and not _gui_has_focus(owner) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


func _gui_has_focus(owner: Node) -> bool:
	return get_tree().root.gui_get_focus_owner() != null or (is_instance_valid(owner) and owner.get_viewport().gui_get_focus_owner() != null)


func accepts_gameplay_input() -> bool:
	return not rebinding and not _suspended


func release_capture(owner: Node) -> void:
	if _owner == owner:
		release_all()


func release_all() -> void:
	_owner = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func suspend_navigation(value: bool) -> void:
	_suspended = value
	if value:
		release_all()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("release_cursor") or event.is_action_released("look"):
		release_all()
	if event.is_action_pressed("ui_cursor"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_released("ui_cursor"):
		if is_instance_valid(_owner) and Input.is_action_pressed("look") and not rebinding and not _suspended:
			request_capture(_owner)
		else:
			release_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()


static func _set_binding(action: String, event: InputEvent) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)


static func _encode(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var code: int = int(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
		return {"kind": "key", "code": code, "location": int(event.location), "shift": event.shift_pressed and code != KEY_SHIFT, "ctrl": event.ctrl_pressed and code != KEY_CTRL, "alt": event.alt_pressed and code != KEY_ALT, "meta": event.meta_pressed and code != KEY_META}
	if event is InputEventMouseButton:
		return {"kind": "mouse", "code": int(event.button_index)}
	if event is InputEventJoypadButton:
		return {"kind": "button", "code": int(event.button_index)}
	if event is InputEventJoypadMotion:
		return {"kind": "axis", "code": int(event.axis), "direction": -1 if event.axis_value < 0 else 1}
	return {}


static func _decode(value: Variant) -> InputEvent:
	if typeof(value) != TYPE_DICTIONARY or not ControlContractValidation.is_integer(value.get("code"), 0, 4195000):
		return null
	var event: InputEvent
	match value.get("kind"):
		"key":
			if not ControlContractValidation.has_exact_fields(value, PackedStringArray(["kind", "code", "location", "shift", "ctrl", "alt", "meta"])) or not ControlContractValidation.is_integer(value.get("location"), 0, 2) or int(value["code"]) == 0:
				return null
			for modifier in ["shift", "ctrl", "alt", "meta"]:
				if typeof(value[modifier]) != TYPE_BOOL:
					return null
			var key := InputEventKey.new()
			key.physical_keycode = int(value["code"])
			key.location = int(value["location"]) as KeyLocation
			key.shift_pressed = value["shift"]
			key.ctrl_pressed = value["ctrl"]
			key.alt_pressed = value["alt"]
			key.meta_pressed = value["meta"]
			event = key
		"mouse":
			if value.size() != 2 or int(value["code"]) not in range(1, 10): return null
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(value["code"]) as MouseButton
			event = mouse
		"button":
			if value.size() != 2 or int(value["code"]) > 20: return null
			var button := InputEventJoypadButton.new()
			button.button_index = int(value["code"]) as JoyButton
			event = button
		"axis":
			if not ControlContractValidation.has_exact_fields(value, PackedStringArray(["kind", "code", "direction"])) or int(value["code"]) > 5 or not ControlContractValidation.is_integer(value.get("direction"), -1, 1) or int(value["direction"]) == 0: return null
			var axis := InputEventJoypadMotion.new()
			axis.axis = int(value["code"]) as JoyAxis
			axis.axis_value = float(value["direction"])
			event = axis
	return event
