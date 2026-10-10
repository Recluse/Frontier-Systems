extends RefCounted
class_name SimulationCommand

## Typed external intent accepted by the simulation at a fixed-tick boundary.
## Subclasses validate against authoritative state before applying a change.

var command_id: StringName
var authenticated_context: AuthenticatedCommandContext
var source: StringName


func execute(simulation_context: Node) -> ServiceResult:
	if simulation_context == null:
		return ServiceResult.failure(&"missing_context", "Simulation context is unavailable.")
	var world_runtime := simulation_context as WorldRuntime
	if world_runtime == null:
		return ServiceResult.failure(&"invalid_world_context", "Commands can only execute inside a WorldRuntime.")
	if authenticated_context == null or not authenticated_context.is_valid_for(world_runtime.world_id, world_runtime.region_id):
		return ServiceResult.failure(&"unauthenticated_command", "A server-authenticated principal scoped to this world and region is required.")
	var validation: ServiceResult = validate(simulation_context)
	if not validation.is_success:
		return validation
	return apply(simulation_context)


func validate(_simulation_context: Node) -> ServiceResult:
	return ServiceResult.failure(&"not_implemented", "Command validation is not implemented.")


func apply(_simulation_context: Node) -> ServiceResult:
	return ServiceResult.failure(&"not_implemented", "Command application is not implemented.")
