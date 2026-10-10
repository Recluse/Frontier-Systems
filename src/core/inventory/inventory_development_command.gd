extends SimulationCommand
class_name InventoryDevelopmentCommand

## Closed local fixture command surface; no production session accepts these intents.
var operation: String = ""
var payload: Dictionary = {}


func validate(simulation_context: Node) -> ServiceResult:
	var world := simulation_context as WorldRuntime
	var inventory := world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem
	if inventory == null:
		return ServiceResult.failure(&"inventory_unavailable", "The inventory runtime is unavailable.")
	return inventory.authorize(authenticated_context)


func apply(simulation_context: Node) -> ServiceResult:
	var world := simulation_context as WorldRuntime
	var inventory := world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem
	return inventory.apply_local(authenticated_context, String(command_id), operation, payload.duplicate(true), world.current_tick_number())
