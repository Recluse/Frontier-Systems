extends RefCounted
class_name AccessControllerState

## Security-controller condition owned by AccessControlSystem.

const SCHEMA_VERSION: int = 1
const POWER_STATES := ["powered", "unpowered", "isolated", "faulted"]
const ALARM_STATES := ["quiet", "local", "remote", "disabled", "faulted"]
const CHANNELS := ["credential_reader", "controller_sequence", "motor_command"]

var controller_id: StringName
var power_state: StringName = &"powered"
var integrity: float = 1.0
var access_locked: bool = true
var alarm_state: StringName = &"quiet"
var bypassed_channels: Array[StringName] = []
var fault_ids: Array[StringName] = []


func to_record() -> Dictionary:
	var channel_records: Array[String] = []
	for channel in bypassed_channels:
		channel_records.append(String(channel))
	var faults: Array[String] = []
	for fault_id in fault_ids:
		faults.append(String(fault_id))
	return {
		"schema_version": SCHEMA_VERSION,
		"controller_id": String(controller_id),
		"power_state": String(power_state),
		"integrity": integrity,
		"access_locked": access_locked,
		"alarm_state": String(alarm_state),
		"bypassed_channels": channel_records,
		"fault_ids": faults,
	}


static func from_record(record: Dictionary) -> ServiceResult:
	if typeof(record.get("schema_version")) != TYPE_INT or record["schema_version"] != SCHEMA_VERSION:
		return ServiceResult.failure(&"unsupported_controller_version", "The security-controller record version is not supported.")
	if record.size() != 8:
		return ServiceResult.failure(&"invalid_controller_record", "The security-controller record has missing or unsupported fields.")
	var id_value: Variant = record.get("controller_id")
	var power_value: Variant = record.get("power_state")
	var integrity_value: Variant = record.get("integrity")
	var access_value: Variant = record.get("access_locked")
	var alarm_value: Variant = record.get("alarm_state")
	var channels_value: Variant = record.get("bypassed_channels")
	var faults_value: Variant = record.get("fault_ids")
	if typeof(id_value) != TYPE_STRING or String(id_value).strip_edges().is_empty():
		return ServiceResult.failure(&"invalid_controller_id", "A security controller requires a stable non-empty ID.")
	if typeof(power_value) != TYPE_STRING or not POWER_STATES.has(power_value):
		return ServiceResult.failure(&"invalid_controller_power", "The security-controller power state is not supported.")
	if typeof(integrity_value) != TYPE_INT and typeof(integrity_value) != TYPE_FLOAT:
		return ServiceResult.failure(&"invalid_controller_integrity", "Controller integrity must be numeric.")
	var integrity_number: float = float(integrity_value)
	if not is_finite(integrity_number) or integrity_number < 0.0 or integrity_number > 1.0:
		return ServiceResult.failure(&"invalid_controller_integrity", "Controller integrity must be between zero and one.")
	if typeof(access_value) != TYPE_BOOL:
		return ServiceResult.failure(&"invalid_controller_lock", "Controller lock state must be boolean.")
	if typeof(alarm_value) != TYPE_STRING or not ALARM_STATES.has(alarm_value):
		return ServiceResult.failure(&"invalid_controller_alarm", "The controller alarm state is not supported.")
	if typeof(channels_value) != TYPE_ARRAY or typeof(faults_value) != TYPE_ARRAY or channels_value.size() > 32 or faults_value.size() > 128:
		return ServiceResult.failure(&"invalid_controller_lists", "Bypassed channels and controller faults must be arrays.")
	var controller := AccessControllerState.new()
	controller.controller_id = StringName(id_value)
	controller.power_state = StringName(power_value)
	controller.integrity = integrity_number
	controller.access_locked = access_value
	controller.alarm_state = StringName(alarm_value)
	for channel_value in channels_value:
		if typeof(channel_value) != TYPE_STRING or not CHANNELS.has(channel_value):
			return ServiceResult.failure(&"invalid_controller_channel", "A bypassed controller channel is not supported.")
		var channel := StringName(channel_value)
		if controller.bypassed_channels.has(channel):
			return ServiceResult.failure(&"duplicate_controller_channel", "Controller channels must be unique.")
		controller.bypassed_channels.append(channel)
	for fault_value in faults_value:
		if typeof(fault_value) != TYPE_STRING or String(fault_value).strip_edges().is_empty():
			return ServiceResult.failure(&"invalid_controller_fault", "Controller fault IDs must be non-empty strings.")
		var fault_id := StringName(fault_value)
		if controller.fault_ids.has(fault_id):
			return ServiceResult.failure(&"duplicate_controller_fault", "Controller fault IDs must be unique.")
		controller.fault_ids.append(fault_id)
	return ServiceResult.success(controller)
