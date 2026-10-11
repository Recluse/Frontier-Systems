extends RefCounted
class_name TerrainTransportCodec

## Only caller intent crosses this boundary; identity and matter remain host-owned.
static func is_terrain(value: SimulationCommand) -> bool:
	return value is TerrainCommand or value is TerrainMaterializeCommand


static func request_id(number: int, operation: String) -> String:
	return "%s-%d" % ["terrain-materialize" if operation == "materialize" else "terrain-client", number]


static func command(number: int, operation: String, payload: Dictionary) -> SimulationCommand:
	var result: SimulationCommand
	if operation == "materialize":
		var claim := TerrainMaterializeCommand.new()
		claim.request_number = number
		claim.payload = payload.duplicate(true)
		result = claim
	else:
		var work := TerrainCommand.new()
		work.request_number = number
		work.operation = operation
		work.payload = payload.duplicate(true)
		result = work
	result.command_id = StringName(request_id(number, operation))
	return result