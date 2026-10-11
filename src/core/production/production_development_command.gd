extends SimulationCommand
class_name ProductionDevelopmentCommand

## Prototype command ingress, including host-bound authenticated first playable sessions.
## Network clients cannot mint contexts or development grants.
var operation: String = ""
var payload: Dictionary = {}


func validate(simulation_context: Node) -> ServiceResult:
	var world := simulation_context as WorldRuntime
	if world == null or authenticated_context == null or not authenticated_context.is_valid_for(world.world_id, world.region_id):
		return ServiceResult.failure(&"production_scope_denied", "Production commands require the current world scope.")
	var production := world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem
	return production.authorize_operation(authenticated_context, operation, payload, String(command_id)) if production != null else ServiceResult.failure(&"production_unavailable", "Production is unavailable.")


func apply(simulation_context: Node) -> ServiceResult:
	var world := simulation_context as WorldRuntime
	var production := world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem
	return production.apply_local(authenticated_context, String(command_id), operation, payload.duplicate(true), world.current_tick_number())
