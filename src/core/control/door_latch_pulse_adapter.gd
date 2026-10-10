extends RefCounted
class_name DoorLatchPulseAdapter

## Server-commissioned binding to one installed module and one existing actuator.
## Pulse receipts carry no player identity, target selection, or executable payload.
const HANDLER_ID: String = "door.latch.v1"

var _access: AccessControlSystem
var _module_id: String
var _device_id: StringName
var _actuator_id: StringName


func _init(access: AccessControlSystem, module_id: String, device_id: StringName, actuator_id: StringName) -> void:
	_access = access
	_module_id = module_id
	_device_id = device_id
	_actuator_id = actuator_id


## This callable is bound explicitly by trusted host construction code.
func receive_pulse(module_id: String, port_id: String, _sequence: int, tick_number: int) -> ServiceResult:
	if not is_instance_valid(_access) or module_id != _module_id or not ["lock", "unlock"].has(port_id):
		return ServiceResult.failure(&"invalid_latch_binding", "The pulse does not match the commissioned latch binding.")
	return _access.apply_circuit_latch_request(_device_id, _actuator_id, port_id == "lock", tick_number)
