extends SceneTree

var _failures: int = 0
var _result: ServiceResult


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: WorldRuntime = _world()
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var actor := AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	_send(world, actor, "grip_join", {"session_id": "session.actor", "expected_revision": 0, "target_id": "fixture.ladder", "action": "pull_along", "hand_ids": ["hand.left"]}, "grip")
	_check(_result.is_success and inventory.profiling_counters()["grip_reserved_hands"] == 1, "capable actor must acquire a handhold")
	_send(world, actor, "start", _search(), "unfinished-search")
	_check(_result.is_success and inventory.profiling_counters()["jobs"] == 1, "capable actor must start a timed search")
	_knockout(world, "body.human-2")
	_check(inventory.profiling_counters()["jobs"] == 0 and inventory.profiling_counters()["grip_reserved_hands"] == 0, "incapacity must cancel voluntary jobs and release grips on the health tick")
	_check(inventory.own_inventory_observation(actor).is_success, "own inventory observations must retain identity scope without granting actions")
	_check(not inventory.authorize(actor, true).is_success, "unconscious actor must fail voluntary-action authorization")
	_check(not inventory.read_search(actor, "unfinished-search").is_success, "interrupted search must reveal no contents")
	var ledger_before: Dictionary = inventory.capture_snapshot().value["owner"]["ledger"]
	_send(world, actor, "resist", {}, "blocked-resist")
	_check(not _result.is_success, "unconscious actor cannot resist")
	_send(world, actor, "move", {"x_millimetres": 500}, "blocked-move")
	_check(not _result.is_success, "unconscious actor cannot move the logical body")
	_send(world, actor, "start", _search(), "blocked-search")
	_check(not _result.is_success and inventory.capture_snapshot().value["owner"]["ledger"] == ledger_before, "blocked search must preserve item ownership")
	var saved: String = world.capture_world_snapshot_json().value
	var restored := WorldRuntime.new()
	root.add_child(restored)
	_check(restored.restore_world_snapshot_json(saved).is_success and restored.start_simulation().is_success, "unconscious world must restore")
	(restored.get_node("SimulationRunner") as SimulationRunner).set_physics_process(false)
	var restored_inventory: InventorySimulationSystem = restored.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	_check(not restored_inventory.authorize(actor, true).is_success, "reconnect/restore must not bypass incapacity")
	var health: HealthSimulationSystem = world.get_simulation_system(HealthSimulationSystem.SYSTEM_ID)
	var current: Dictionary = health.body_observation("body.human-2").value
	_check(health.queue_observation("body.human-2", [], current["source_revision"], world.current_tick_number() + 1).is_success, "trusted recovery observation must queue")
	_step(world, 61)
	_check(inventory.authorize(actor, true).is_success, "recovered actor may act again")
	_send(world, actor, "resist", {}, "recovered-resist")
	_check(_result.is_success, "recovery must restore normal command availability")
	var rescue: WorldRuntime = _world()
	var rescue_inventory: InventorySimulationSystem = rescue.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	_knockout(rescue, "body.human-1")
	var rescuer := AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", rescue.world_id, rescue.region_id)
	_send(rescue, rescuer, "start", _search(), "search-unconscious-target")
	_check(_result.is_success, "a capable player can interact with an unconscious target")
	_step(rescue, 120)
	_check(rescue_inventory.read_search(rescuer, "search-unconscious-target").is_success, "unconscious target must not fabricate resistance or block scoped physical searching")
	_check(rescue_inventory.profiling_counters()["search_views"] == 1, "completed search must grant one scoped view")
	_knockout(rescue, "body.human-2")
	_check(rescue_inventory.profiling_counters()["search_views"] == 0, "incapacity must revoke completed external inventory views")
	rescue.free()
	restored.free()
	world.free()
	if _failures == 0:
		print("Inventory consciousness gating, grip/job interruption, recovery and passive-target scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _world() -> WorldRuntime:
	var world := WorldRuntime.new()
	root.add_child(world)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: _result = result)
	_check(world.start_simulation().is_success, "world must start")
	(world.get_node("SimulationRunner") as SimulationRunner).set_physics_process(false)
	return world


func _knockout(world: WorldRuntime, body_id: String) -> void:
	var health: HealthSimulationSystem = world.get_simulation_system(HealthSimulationSystem.SYSTEM_ID)
	var causes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/health/suppression.combined.v1.json"))
	var source: Dictionary = health.body_observation(body_id).value
	_check(health.queue_observation(body_id, causes, source["source_revision"], world.current_tick_number() + 1).is_success, "trusted knockout source must queue")
	_step(world)
	_check(not health.consciousness_allows_actions(body_id), "fixed tick must make body unconscious")


func _send(world: WorldRuntime, context: AuthenticatedCommandContext, operation: String, payload: Dictionary, id: String) -> void:
	var command := InventoryDevelopmentCommand.new()
	command.authenticated_context = context
	command.command_id = StringName(id)
	command.operation = operation
	command.payload = payload
	_result = null
	_check(world.enqueue_command(command).is_success, "fixture intent must queue")
	_step(world)
	_check(_result != null, "queued command must complete")


func _step(world: WorldRuntime, count: int = 1) -> void:
	for _index in range(count):
		(world.get_node("SimulationRunner") as SimulationRunner)._physics_process(1.0 / 60.0)


func _search() -> Dictionary:
	return {"action": "search", "target_body_id": "body.human-1", "target_container_id": "storage.pouch-1", "item_id": "", "slot_id": "", "destination_container_id": "", "expected_revision": 0}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
