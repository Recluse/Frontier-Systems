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
	var context: AuthenticatedCommandContext = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	var own: Dictionary = inventory.own_inventory_observation(context).value
	_check(own["schema_version"] == 2 and own["items"].size() == 3, "own v2 view must include nested possessions")
	_check(own["container_ids"].has("storage.pouch-1") and not own["container_ids"].has("body.human-2"), "own destinations must exclude another body's containers")
	var request: Dictionary = _intent("switch_hand", 0)
	_enqueue(world, context, request, "self-switch")
	runner._physics_process(1.0 / 60.0)
	_check(_last_result.is_success and inventory.own_inventory_observation(context).value["active_hand_slot_id"] == "hand.right", "queued switch must select the other hand")
	var before: String = world.capture_world_snapshot_json().value
	_enqueue(world, context, request, "self-switch")
	runner._physics_process(1.0 / 60.0)
	_check(_last_result.is_success and inventory.own_inventory_observation(context).value["active_hand_slot_id"] == "hand.right", "identical receipt retry must not switch twice")
	request = _intent("equip", 1)
	request["item_id"] = "crowbar-1"
	request["source_container_id"] = "storage.pouch-1"
	request["slot_id"] = "hand.right"
	_enqueue(world, context, request, "self-equip")
	runner._physics_process(1.0 / 60.0)
	_check(_last_result.is_success, "owned nested tool must equip into a free hand")
	before = JSON.stringify(inventory.capture_snapshot().value["owner"])
	var incompatible: Dictionary = request.duplicate(true)
	incompatible["slot_id"] = "clothing.uniform"
	incompatible["source_container_id"] = "body.human-1"
	incompatible["expected_revision"] = 2
	_enqueue(world, context, incompatible, "self-incompatible")
	runner._physics_process(1.0 / 60.0)
	_check(not _last_result.is_success and JSON.stringify(inventory.capture_snapshot().value["owner"]) == before, "incompatible self equipment must reject atomically")
	request = _intent("unequip", 2)
	request["slot_id"] = "hand.right"
	request["destination_container_id"] = "storage.pouch-1"
	_enqueue(world, context, request, "self-stow")
	runner._physics_process(1.0 / 60.0)
	_check(_last_result.is_success, "tool must unequip into owned nested storage")
	own = inventory.own_inventory_observation(context).value
	_check(own["mass_milligrams"] == 3500000 and own["equipped"].size() == 1, "self movement must preserve mass and release only the tool binding")
	request = _intent("move", 3)
	request["item_id"] = "crowbar-1"
	request["source_container_id"] = "storage.pouch-1"
	request["destination_container_id"] = "body.human-2"
	_enqueue(world, context, request, "self-foreign")
	runner._physics_process(1.0 / 60.0)
	_check(not _last_result.is_success, "self operation must not bypass other-body timed interactions")
	request["destination_container_id"] = "body.human-1"
	_enqueue(world, context, request, "self-move")
	runner._physics_process(1.0 / 60.0)
	_check(_last_result.is_success, "owned unbound item must move between own containers")
	var saved: String = world.capture_world_snapshot_json().value
	var restored := WorldRuntime.new()
	root.add_child(restored)
	_check(restored.restore_world_snapshot_json(saved).is_success, "self actions and receipts must restore through world JSON")
	var restored_inventory: InventorySimulationSystem = restored.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	_check(restored_inventory.own_inventory_observation(context).value["active_hand_slot_id"] == "hand.right", "selected hand must survive recovery")
	world.free()
	restored.free()
	if _failures == 0:
		print("Self inventory command and equipment recovery scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _intent(operation: String, revision: int) -> Dictionary:
	return {"operation": operation, "item_id": "", "source_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": revision}


func _enqueue(world: WorldRuntime, context: AuthenticatedCommandContext, payload: Dictionary, id: String) -> void:
	var command := InventoryDevelopmentCommand.new()
	command.authenticated_context = context
	command.command_id = StringName(id)
	command.operation = "self"
	command.payload = payload
	_check(world.enqueue_command(command).is_success, "self command must enqueue")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
