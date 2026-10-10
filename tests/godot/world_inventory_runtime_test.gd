extends SceneTree

var _failures: int = 0
var _last_result: ServiceResult


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: _last_result = result)
	world.start_simulation()
	var runner: SimulationRunner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var target: AuthenticatedCommandContext = _context(world, "local-inventory-target")
	var actor: AuthenticatedCommandContext = _context(world, "local-inventory-actor")
	var drop := {"operation": "drop", "item_id": "backpack-1", "world_container_id": "world.tray-1", "destination_container_id": "", "slot_id": "", "expected_revision": 0}
	_enqueue(world, target, "world", drop, "drop-bag")
	runner._physics_process(1.0 / 60.0)
	_check(_last_result.is_success, "loaded equipped bag must drop through command queue")
	_check(inventory.own_inventory_observation(target).value["items"].is_empty(), "dropped bag must remove all descendants from owned observation")
	var observed: Dictionary = inventory.world_inventory_observation(actor).value
	_check(observed["containers"][0]["items"].size() == 1 and observed["containers"][0]["items"][0]["item_id"] == "backpack-1", "world view must reveal direct bag only")
	_enqueue(world, target, "world", drop, "drop-bag")
	runner._physics_process(1.0 / 60.0)
	_check(_last_result.is_success and inventory.local_observation(actor).value["inventory_revision"] == 1, "retained drop retry must not increment revision")
	var pickup := {"operation": "pickup", "item_id": "backpack-1", "world_container_id": "world.tray-1", "destination_container_id": "body.human-2", "slot_id": "back", "expected_revision": 1}
	_enqueue(world, actor, "world", pickup, "pickup-bag")
	var competing: Dictionary = pickup.duplicate(true)
	competing["destination_container_id"] = "body.human-1"
	_enqueue(world, target, "world", competing, "competing-bag")
	runner._physics_process(1.0 / 60.0)
	_check(not _last_result.is_success, "second competing pickup must reject stale revision")
	var own: Dictionary = inventory.own_inventory_observation(actor).value
	_check(own["items"].size() == 3 and own["mass_milligrams"] == 3500000 and own["equipped"][0]["slot_id"] == "back", "pickup must preserve loaded subtree and fit it atomically")
	_check(own["items"][0]["condition_permille"] == 850, "world round trip must preserve damaged bag condition")
	var invalid: Dictionary = pickup.duplicate(true)
	invalid["world_container_id"] = "body.human-1"
	invalid["expected_revision"] = 2
	_enqueue(world, actor, "world", invalid, "foreign-world")
	runner._physics_process(1.0 / 60.0)
	_check(not _last_result.is_success, "body root cannot be addressed as world storage")
	_enqueue(world, actor, "move", {"x_millimetres": 10000}, "walk-away")
	runner._physics_process(1.0 / 60.0)
	_check(inventory.world_inventory_observation(actor).value["containers"].is_empty(), "out-of-reach tray must not be observed")
	var distant_drop: Dictionary = drop.duplicate(true)
	distant_drop["expected_revision"] = 2
	_enqueue(world, actor, "world", distant_drop, "drop-distant")
	runner._physics_process(1.0 / 60.0)
	_check(not _last_result.is_success and inventory.own_inventory_observation(actor).value["items"].size() == 3, "out-of-reach drop must preserve possessions")
	var saved: String = world.capture_world_snapshot_json().value
	var restored := WorldRuntime.new()
	root.add_child(restored)
	_check(restored.restore_world_snapshot_json(saved).is_success, "world locations and transferred bag must restore")
	var legacy: Dictionary = JSON.parse_string(saved)
	legacy["systems"]["inventory"]["schema_version"] = 1
	legacy["systems"]["inventory"].erase("grips")
	legacy["systems"]["inventory"].erase("world_storage")
	for body in legacy["systems"]["inventory"]["bodies"]:
		body["x_millimetres"] = body["position_millimetres"][0]
		body.erase("position_millimetres")
	var migrated := WorldRuntime.new()
	root.add_child(migrated)
	_check(migrated.restore_world_snapshot_json(JSON.stringify(legacy)).is_success, "v1 inventory snapshot must migrate existing tray metadata")
	var migrated_inventory: InventorySimulationSystem = migrated.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	_check(migrated_inventory.capture_snapshot().value["world_storage"].size() == 1 and migrated_inventory.capture_snapshot().value["owner"]["ledger"]["items"].size() == 3, "migration must add metadata without spawning matter")
	world.free()
	restored.free()
	migrated.free()
	if _failures == 0:
		print("World inventory pickup/drop and migration scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _context(world: WorldRuntime, principal: String) -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.for_local_development(StringName(principal), world.world_id, world.region_id)


func _enqueue(world: WorldRuntime, context: AuthenticatedCommandContext, operation: String, payload: Dictionary, id: String) -> void:
	var command := InventoryDevelopmentCommand.new()
	command.authenticated_context = context
	command.command_id = StringName(id)
	command.operation = operation
	command.payload = payload.duplicate(true)
	_check(world.enqueue_command(command).is_success, "world inventory command must enqueue")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
