extends RefCounted
class_name LocalAlarmPulseAdapter

## Fixed host/module binding. A trigger may raise, never clear, security alarms.
const HANDLER_ID: String = "alarm.local.v1"
var _access: AccessControlSystem
var _module_id: String
var _device_id: StringName


func _init(access: AccessControlSystem, module_id: String, device_id: StringName) -> void:
	_access = access
	_module_id = module_id
	_device_id = device_id


func receive_pulse(module_id: String, port_id: String, _sequence: int, tick_number: int) -> ServiceResult:
	if not is_instance_valid(_access) or module_id != _module_id or port_id != "raise_alarm":
		return ServiceResult.failure(&"invalid_alarm_binding", "The pulse does not match the commissioned alarm input.")
	return _access.apply_circuit_alarm_request(_device_id, tick_number)
