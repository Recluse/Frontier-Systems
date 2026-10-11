extends SimulationCommand
class_name TerrainMaterializeCommand

## Server-only typed entry point; no wire/UI endpoint or caller-supplied matter.
var request_number: int = 0
var payload: Dictionary = {}


func validate(simulation_context: Node) -> ServiceResult:
	var world := simulation_context as WorldRuntime
	var terrain := world.get_simulation_system(TerrainSimulationSystem.SYSTEM_ID) as TerrainSimulationSystem
	return terrain.authorize(authenticated_context) if terrain != null else ServiceResult.failure(&"terrain_unavailable", "Terrain is unavailable.")


func apply(simulation_context: Node) -> ServiceResult:
	var world := simulation_context as WorldRuntime
	var terrain := world.get_simulation_system(TerrainSimulationSystem.SYSTEM_ID) as TerrainSimulationSystem
	return terrain.materialize(authenticated_context, String(command_id), request_number, payload.duplicate(true), world.current_tick_number())
