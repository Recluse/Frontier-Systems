extends SceneTree

var _failures: int = 0
var _last_result: ServiceResult


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check(InventorySpatialMath.distance_millimetres([0, 0, 0], [1500, 0, 0]) == 1500, "exact reach boundary must remain reachable")
	_check(InventorySpatialMath.distance_millimetres([0, 0, 0], [1500, 1, 0]) == 1501, "just-outside diagonal must not round down into reach")
	_check(InventorySpatialMath.distance_millimetres([0, 0, 0], [0, 1600, 0]) == 1600, "vertical separation must count")
	_check(InventorySpatialMath.distance_millimetres([-10000000, -10000000, -10000000], [10000000, 10000000, 10000000]) == 34641017, "maximum supported separation must avoid overflow")
	_check(not InventorySpatialMath.is_position([0, 0.5, 0]) and not InventorySpatialMath.is_position([0, 0]) and not InventorySpatialMath.is_position([0, INF, 0]), "invalid position dimensions/quantities must reject")
	var world := WorldRuntime.new()
	root.add_child(world)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: _last_result = result)
	world.start_simulation()
	var runner: SimulationRunner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var actor: AuthenticatedCommandContext = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	_move(world, actor, [0, 1600, 0], "vertical")
	runner._physics_process(1.0 / 60.0)
	_check(_last_result.is_success and inventory.world_inventory_observation(actor).value["containers"].is_empty(), "vertical movement must hide out-of-reach storage")
	_move(world, actor, [1500, 1, 0], "diagonal")
	runner._physics_process(1.0 / 60.0)
	_check(inventory.world_inventory_observation(actor).value["containers"].is_empty(), "diagonal boundary must filter tray observation")
	_move(world, actor, [1500, 0, 0], "boundary")
	runner._physics_process(1.0 / 60.0)
	_check(inventory.world_inventory_observation(actor).value["containers"].size() == 1, "exact boundary must permit observation")
	var saved: String = world.capture_world_snapshot_json().value
	var restored := WorldRuntime.new()
	root.add_child(restored)
	_check(restored.restore_world_snapshot_json(saved).is_success, "v3 spatial records must recover")
	var invalid: Dictionary = JSON.parse_string(saved)
	invalid["systems"]["inventory"]["bodies"][0]["position_millimetres"][2] = 0.5
	var before: String = restored.capture_world_snapshot_json().value
	_check(not restored.restore_world_snapshot_json(JSON.stringify(invalid)).is_success and restored.capture_world_snapshot_json().value == before, "fractional spatial save must reject atomically")
	var legacy: Dictionary = JSON.parse_string(saved)
	legacy["systems"]["inventory"]["schema_version"] = 2
	legacy["systems"]["inventory"].erase("grips")
	for body in legacy["systems"]["inventory"]["bodies"]:
		body["x_millimetres"] = body["position_millimetres"][0]
		body.erase("position_millimetres")
	for storage in legacy["systems"]["inventory"]["world_storage"]:
		storage["x_millimetres"] = storage["position_millimetres"][0]
		storage.erase("position_millimetres")
	var old := WorldRuntime.new()
	root.add_child(old)
	_check(old.restore_world_snapshot_json(JSON.stringify(legacy)).is_success, "v2 axis records must migrate")
	var old_inventory: InventorySimulationSystem = old.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var migrated: Dictionary = old_inventory.capture_snapshot().value
	_check(migrated["schema_version"] == 4 and migrated["world_storage"][0]["position_millimetres"] == [0, 0, 0], "axis migration must emit v4 vectors")
	_check(migrated["owner"]["ledger"]["items"].size() == 3, "spatial migration must preserve matter count")
	world.free()
	restored.free()
	old.free()
	if _failures == 0:
		print("Inventory 3D reach and spatial recovery scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _move(world: WorldRuntime, context: AuthenticatedCommandContext, position: Array, id: String) -> void:
	var command := InventoryDevelopmentCommand.new()
	command.command_id = StringName(id)
	command.authenticated_context = context
	command.operation = "move_to"
	command.payload = {"position_millimetres": position}
	world.enqueue_command(command)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
