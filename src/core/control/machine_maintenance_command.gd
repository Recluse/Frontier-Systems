extends SimulationCommand
class_name MachineMaintenanceCommand

## Prototype command boundary; general physical/inventory authority is still pending.
var intent: MachineMaintenanceIntent


func validate(simulation_context: Node) -> ServiceResult:
	var world := simulation_context as WorldRuntime
	var controls := world.get_simulation_system(MachineControlSystem.SYSTEM_ID) as MachineControlSystem
	if controls == null:
		return ServiceResult.failure(&"control_system_unavailable", "Machine controls are unavailable.")
	return controls.validate_maintenance(intent, authenticated_context)


func apply(simulation_context: Node) -> ServiceResult:
	var world := simulation_context as WorldRuntime
	var controls := world.get_simulation_system(MachineControlSystem.SYSTEM_ID) as MachineControlSystem
	return controls.apply_maintenance(intent, authenticated_context, command_id)
