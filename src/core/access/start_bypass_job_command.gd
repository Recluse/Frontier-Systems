extends SimulationCommand
class_name StartBypassJobCommand

## Requests a tool-gated, staged bypass job on one access-controlled actuator.

var device_id: StringName = &""
var target_id: StringName = &""
var route: StringName = &""


func validate(simulation_context: Node) -> ServiceResult:
	var access_system := _access_system(simulation_context)
	if access_system == null:
		return ServiceResult.failure(&"access_system_unavailable", "The access-control system is unavailable.")
	return access_system.validate_start_bypass(device_id, target_id, route, authenticated_context, command_id)


func apply(simulation_context: Node) -> ServiceResult:
	var access_system := _access_system(simulation_context)
	if access_system == null:
		return ServiceResult.failure(&"access_system_unavailable", "The access-control system is unavailable.")
	return access_system.start_bypass_job(command_id, device_id, target_id, route, authenticated_context)


func _access_system(simulation_context: Node) -> AccessControlSystem:
	var world_runtime := simulation_context as WorldRuntime
	if world_runtime == null:
		return null
	return world_runtime.get_simulation_system(AccessControlSystem.SYSTEM_ID) as AccessControlSystem
