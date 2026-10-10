extends SceneTree

var _failures: int = 0
var _result: ServiceResult


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: _result = result)
	_check(world.start_simulation().is_success, "world must start")
	var runner: SimulationRunner = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var actor := AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	var target := AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	_send(world, runner, target, "self", _equip("hand.left", 0, "storage.pouch-1"), "tool")
	_check(_result.is_success, "tool must equip before gripping")
	_send(world, runner, target, "grip_join", _join("hand.left", 0), "occupied")
	_check(not _result.is_success and inventory.local_grip_observation(target).value["grip_revision"] == 0, "occupied hand must reject without mutation")
	_send(world, runner, target, "grip_join", _join("hand.right", 0), "target-grip")
	_check(_result.is_success and not inventory.local_grip_observation(target).value["sessions"][0]["movement_available"], "one body waits for cooperative strength")
	_send(world, runner, actor, "grip_join", _join("hand.left", 1), "actor-grip")
	_check(_result.is_success and inventory.local_grip_observation(actor).value["sessions"][0]["movement_available"], "independent second principal can explicitly join")
	_send(world, runner, actor, "grip_join", _join("hand.left", 1), "actor-grip")
	_check(_result.is_success and inventory.local_grip_observation(actor).value["grip_revision"] == 2, "retained queued join retry must not duplicate participation")
	_send(world, runner, target, "self", {"operation": "unequip", "item_id": "", "source_container_id": "", "destination_container_id": "body.human-1", "slot_id": "hand.left", "expected_revision": 1}, "free-tool")
	_check(_result.is_success, "unreserved hand can stow an item while the other hand grips")
	_send(world, runner, target, "self", _equip("hand.right", 2, "body.human-1"), "conflict")
	_check(not _result.is_success, "inventory equip cannot use a reserved hand")
	var saved: String = world.capture_world_snapshot_json().value
	var restored := WorldRuntime.new()
	root.add_child(restored)
	_check(restored.restore_world_snapshot_json(saved).is_success, "world grip snapshot must restore")
	var restored_inventory: InventorySimulationSystem = restored.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var observation: Dictionary = restored_inventory.local_grip_observation(target).value
	_check(observation["sessions"][0]["paused"] and not observation["sessions"][0]["movement_available"], "recovery must preserve paused reservations")
	var invalid: Dictionary = JSON.parse_string(saved)
	for body in invalid["systems"]["inventory"]["owner"]["bodies"]:
		if body["body_id"] == "body.human-1":
			body["equipped"].append({"item_id": "crowbar-1", "slot_id": "hand.right"})
	var before: String = restored.capture_world_snapshot_json().value
	_check(not restored.restore_world_snapshot_json(JSON.stringify(invalid)).is_success and restored.capture_world_snapshot_json().value == before, "cross-owner occupied grip snapshot must reject atomically")
	_check(restored.start_simulation().is_success, "restored world must start")
	var restored_runner: SimulationRunner = restored.get_node("SimulationRunner")
	restored_runner.set_physics_process(false)
	restored.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: _result = result)
	_send(restored, restored_runner, target, "grip_resume", {"session_id": "session.crate", "expected_revision": 2}, "cooperative-resume")
	_check(not _result.is_success, "one principal cannot resume all cooperative participants")
	_send(restored, restored_runner, target, "grip_release", {"session_id": "session.crate", "expected_revision": 2}, "restored-release")
	_check(_result.is_success and restored_inventory.local_grip_observation(target).value["sessions"].is_empty(), "paused member can explicitly release")
	_send(world, runner, target, "world", {"operation": "drop", "item_id": "crowbar-1", "world_container_id": "world.tray-1", "destination_container_id": "", "slot_id": "", "expected_revision": 2}, "drop-tool")
	_check(_result.is_success, "drop through an unreserved hand must succeed")
	_send(world, runner, target, "world", {"operation": "pickup", "item_id": "crowbar-1", "world_container_id": "world.tray-1", "destination_container_id": "body.human-1", "slot_id": "hand.right", "expected_revision": 3}, "pickup-conflict")
	_check(not _result.is_success, "world pickup must reject a reserved destination hand")
	_send(world, runner, actor, "world", {"operation": "pickup", "item_id": "crowbar-1", "world_container_id": "world.tray-1", "destination_container_id": "body.human-2", "slot_id": "hand.right", "expected_revision": 3}, "pickup-other-hand")
	_check(_result.is_success, "unreserved actor hand can pick up the tool")
	_send(world, runner, actor, "start", {"action": "equip", "target_body_id": "body.human-1", "target_container_id": "body.human-1", "item_id": "crowbar-1", "slot_id": "hand.right", "destination_container_id": "", "expected_revision": 4}, "timed-conflict")
	_check(_result.is_success, "timed equipment work can begin before final hand arbitration")
	for step in range(180):
		runner._physics_process(1.0 / 60.0)
	var outcomes: Array = inventory.local_observation(actor).value["outcomes"]
	_check(not outcomes.is_empty() and not outcomes.back()["success"], "timed equipment completion must reject a reserved destination hand")
	_check(inventory.own_inventory_observation(actor).value["items"].size() == 1, "failed timed equip must leave the actor's item in place")
	_send(world, runner, actor, "move_to", {"position_millimetres": [2000, 0, 0]}, "walk-away")
	_check(_result.is_success and inventory.local_grip_observation(actor).value["sessions"].is_empty(), "contact loss must release only the moved participant")
	_check(not inventory.local_grip_observation(target).value["sessions"][0]["movement_available"], "remaining group must lose sufficient force")
	_send(world, runner, target, "grip_release", {"session_id": "session.crate", "expected_revision": 3}, "target-release")
	_check(_result.is_success, "last release must remove target session")
	_send(world, runner, target, "grip_join", {"session_id": "session.ladder", "expected_revision": 4, "target_id": "fixture.ladder", "action": "pull_along", "hand_ids": ["hand.left"]}, "ladder")
	_check(_result.is_success and inventory.local_grip_observation(target).value["sessions"][0]["movement_available"], "one free hand can establish supported ladder traversal")
	var solo := WorldRuntime.new()
	root.add_child(solo)
	_check(solo.restore_world_snapshot_json(world.capture_world_snapshot_json().value).is_success and solo.start_simulation().is_success, "solo ladder grip must recover paused")
	var solo_runner: SimulationRunner = solo.get_node("SimulationRunner")
	solo_runner.set_physics_process(false)
	solo.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: _result = result)
	_send(solo, solo_runner, target, "grip_resume", {"session_id": "session.ladder", "expected_revision": 5}, "solo-resume")
	var solo_inventory: InventorySimulationSystem = solo.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	_check(_result.is_success and not solo_inventory.local_grip_observation(target).value["sessions"][0]["paused"], "sole participant can explicitly resume after fresh checks")
	var legacy: Dictionary = JSON.parse_string(saved)
	legacy["systems"]["inventory"]["schema_version"] = 3
	legacy["systems"]["inventory"].erase("grips")
	var migrated := WorldRuntime.new()
	root.add_child(migrated)
	_check(migrated.restore_world_snapshot_json(JSON.stringify(legacy)).is_success, "v3 saves must migrate without introducing grips")
	var migrated_inventory: InventorySimulationSystem = migrated.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	_check(migrated_inventory.capture_snapshot().value["grips"]["sessions"].is_empty() and migrated_inventory.capture_snapshot().value["owner"]["ledger"]["items"].size() == 3, "migration must preserve matter and initialize empty grips")
	var production := AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-target", &"session.production", world.world_id, world.region_id, PackedStringArray(["inventory.development"]))
	_send(world, runner, production, "grip_join", _join("hand.right", 4), "production")
	_check(not _result.is_success, "production origin must reject development grip intents")
	world.free()
	restored.free()
	migrated.free()
	solo.free()
	if _failures == 0:
		print("Queued inventory grip arbitration, contact loss and world recovery scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _join(hand: String, revision: int) -> Dictionary:
	return {"session_id": "session.crate", "expected_revision": revision, "target_id": "fixture.salvage-crate", "action": "move_world_object", "hand_ids": [hand]}


func _equip(hand: String, revision: int, source: String) -> Dictionary:
	return {"operation": "equip", "item_id": "crowbar-1", "source_container_id": source, "destination_container_id": "", "slot_id": hand, "expected_revision": revision}


func _send(world: WorldRuntime, runner: SimulationRunner, context: AuthenticatedCommandContext, operation: String, payload: Dictionary, id: String) -> void:
	var command := InventoryDevelopmentCommand.new()
	command.authenticated_context = context
	command.command_id = StringName(id)
	command.operation = operation
	command.payload = payload
	_result = null
	_check(world.enqueue_command(command).is_success, "command must enqueue")
	runner._physics_process(1.0 / 60.0)
	_check(_result != null, "command must complete at tick")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
