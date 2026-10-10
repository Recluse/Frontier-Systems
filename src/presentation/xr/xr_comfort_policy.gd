extends RefCounted
class_name XRComfortPolicy

## Local presentation settings and neutral-before-action input gates; no world state.
const DEFAULT_PATH: String = "user://xr-comfort.v1.json"
const MAX_BYTES: int = 4096
const DEFAULTS: Dictionary = {"schema_version": 1, "snap_turn_degrees": 30, "turn_engage_permille": 750, "turn_release_permille": 250, "seated_mode": false, "seated_height_offset_mm": 600}
var _settings: Dictionary = DEFAULTS.duplicate(true)
var _turn_armed: bool = false
var _buttons_armed: Dictionary = {}


static func create_default() -> XRComfortPolicy:
	return from_record(DEFAULTS).value


static func from_record(record: Dictionary) -> ServiceResult:
	if not ControlContractValidation.has_exact_fields(record, PackedStringArray(["schema_version", "snap_turn_degrees", "turn_engage_permille", "turn_release_permille", "seated_mode", "seated_height_offset_mm"])) or not ControlContractValidation.is_integer(record.get("schema_version"), 1, 1) or not ControlContractValidation.is_integer(record.get("snap_turn_degrees"), 0, 60) or int(record["snap_turn_degrees"]) not in [0, 15, 30, 45, 60] or typeof(record.get("seated_mode")) != TYPE_BOOL or not ControlContractValidation.is_integer(record.get("seated_height_offset_mm"), 0, 1000):
		return _failure("Complete bounded XR comfort settings are required.")
	if not ControlContractValidation.is_integer(record["turn_engage_permille"], 1, 1000) or not ControlContractValidation.is_integer(record["turn_release_permille"], 0, 999) or int(record["turn_release_permille"]) >= int(record["turn_engage_permille"]):
		return _failure("Turn release threshold must be lower than its engage threshold.")
	var policy := XRComfortPolicy.new()
	policy._settings = record.duplicate(true)
	for field in ["schema_version", "snap_turn_degrees", "turn_engage_permille", "turn_release_permille", "seated_height_offset_mm"]:
		policy._settings[field] = int(policy._settings[field])
	return ServiceResult.success(policy)


func to_record() -> Dictionary:
	return _settings.duplicate(true)


func reset_input() -> void:
	_turn_armed = false
	_buttons_armed.clear()


func sample_input(observation: Dictionary) -> ServiceResult:
	var fields := PackedStringArray(["schema_version", "turn_axis", "session_focused", "left_tracked", "right_tracked", "seated_pressed", "height_up_pressed", "height_down_pressed"])
	if not ControlContractValidation.has_exact_fields(observation, fields) or not ControlContractValidation.is_integer(observation.get("schema_version"), 1, 1) or typeof(observation.get("turn_axis")) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(observation["turn_axis"])) or absf(float(observation["turn_axis"])) > 1.0:
		reset_input()
		return _failure("A finite bounded XR comfort input observation is required.")
	for field in ["session_focused", "left_tracked", "right_tracked", "seated_pressed", "height_up_pressed", "height_down_pressed"]:
		if typeof(observation[field]) != TYPE_BOOL:
			reset_input()
			return _failure("Tracking, focus and button observations must be boolean.")
	var yaw: int = 0
	var axis: float = float(observation["turn_axis"])
	var right_available: bool = observation["session_focused"] and observation["right_tracked"]
	if not right_available or _settings["snap_turn_degrees"] == 0:
		_turn_armed = false
	elif absf(axis) <= float(_settings["turn_release_permille"]) / 1000.0:
		_turn_armed = true
	elif _turn_armed and absf(axis) >= float(_settings["turn_engage_permille"]) / 1000.0:
		_turn_armed = false
		yaw = -int(_settings["snap_turn_degrees"]) if axis > 0.0 else int(_settings["snap_turn_degrees"])
	var seated: bool = _button_edge("seated", observation["seated_pressed"], observation["session_focused"] and observation["left_tracked"])
	var up: bool = _button_edge("up", observation["height_up_pressed"], right_available)
	var down: bool = _button_edge("down", observation["height_down_pressed"], right_available)
	return ServiceResult.success({"schema_version": 1, "yaw_degrees": yaw, "toggle_seated": seated, "height_delta_mm": (50 if up else 0) - (50 if down else 0)})


func _button_edge(id: String, pressed: bool, available: bool) -> bool:
	if not available:
		_buttons_armed[id] = false
		return false
	if not pressed:
		_buttons_armed[id] = true
		return false
	if not _buttons_armed.get(id, false):
		return false
	_buttons_armed[id] = false
	return true


static func load_preferences(path: String = DEFAULT_PATH) -> ServiceResult:
	if not _valid_path(path):
		return _failure("Comfort preferences require a flat local user JSON filename.")
	if not FileAccess.file_exists(path):
		return ServiceResult.success(create_default())
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return _failure("Comfort preferences cannot be read or exceed their byte limit.")
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return _failure("Comfort preferences must contain a JSON object.")
	return from_record(parser.data)


func save_preferences(path: String = DEFAULT_PATH) -> ServiceResult:
	if not _valid_path(path):
		return _failure("Comfort preferences require a flat local user JSON filename.")
	var temporary: String = path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("Comfort preferences could not be written.")
	file.store_string(JSON.stringify(to_record()))
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK or DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("Comfort preference replacement failed; existing settings were retained.")
	return ServiceResult.success()


static func _valid_path(path: String) -> bool:
	if not path.begins_with("user://"):
		return false
	var leaf: String = path.trim_prefix("user://")
	return not leaf.is_empty() and leaf.length() <= 128 and leaf.ends_with(".json") and not leaf.contains("/") and not leaf.contains("\\") and not leaf.contains("..") and not leaf.contains(":")


static func _failure(message: String) -> ServiceResult:
	return ServiceResult.failure(&"invalid_xr_comfort", message)
