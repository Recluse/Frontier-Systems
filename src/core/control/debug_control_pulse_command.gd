extends SimulationCommand
class_name DebugControlPulseCommand

## Local debug probe, not a transmitter or a production player interaction.
func validate(simulation_context: Node) -> ServiceResult:
	if not OS.is_debug_build() or authenticated_context.origin != AuthenticatedCommandContext.Origin.DEVELOPMENT_LOCAL or not authenticated_context.has_permission("control.debug_pulse"):
		return ServiceResult.failure(&"permission_denied", "The control probe requires a local development grant.")
	var world := simulation_context as WorldRuntime
	if world.get_simulation_system(MachineControlSystem.SYSTEM_ID) == null:
		return ServiceResult.failure(&"control_system_unavailable", "The control system is unavailable.")
	return ServiceResult.success()


func apply(simulation_context: Node) -> ServiceResult:
	var world := simulation_context as WorldRuntime
	var controls := world.get_simulation_system(MachineControlSystem.SYSTEM_ID) as MachineControlSystem
	return controls.request_debug_pulse()
