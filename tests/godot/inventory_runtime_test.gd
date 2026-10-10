extends SceneTree

var _failures: int = 0
var _last_result: ServiceResult


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world: WorldRuntime = _world()
	_enqueue(world, "local-inventory-actor", "start", _intent("search"), "search-runtime")
	_step(world)
	_check(_last_result.is_success, "search must start through the command queue")
	_check(_inventory(world).profiling_counters()["jobs"] == 1, "new job must not instantly complete")
	_step(world, 120)
	var actor: AuthenticatedCommandContext = _context(world, "local-inventory-actor")
	var search: ServiceResult = _inventory(world).read_search(actor, "search-runtime")
	_check(search.is_success and search.value["items"].size() == 1 and search.value["items"][0]["item_id"] == "crowbar-1", "runtime search must reveal direct selected-container contents")
	_check(not _inventory(world).read_search(_context(world, "local-inventory-target"), "search-runtime").is_success, "target principal must not read actor's search view")
	_enqueue(world, "local-inventory-actor", "start", _intent("take"), "take-resisted")
	_step(world)
	_step(world, 179)
	_enqueue(world, "local-inventory-target", "resist", {}, "resist-final-tick")
	_step(world)
	var captured: Dictionary = world.capture_world_snapshot().value.to_dictionary()
	_check(captured["systems"]["inventory"]["owner"]["ledger"]["items"][2]["container_id"] == "storage.pouch-1", "same-completion-tick resistance must prevent transfer")
	_check(captured["systems"]["inventory"]["owner"]["receipts"].is_empty(), "interrupted work must create no completion receipt")
	_enqueue(world, "local-inventory-actor", "start", _intent("take"), "take-complete")
	_step(world)
	_step(world, 180)
	captured = world.capture_world_snapshot().value.to_dictionary()
	_check(captured["systems"]["inventory"]["owner"]["ledger"]["items"][2]["container_id"] == "body.human-2", "fixed-tick completion must transfer through the shared owner")
	_check(captured["systems"]["inventory"]["owner"]["receipts"].size() == 1, "transfer and receipt must share a checkpoint")
	_check(not _inventory(world).read_search(actor, "search-runtime").is_success, "search must expire or revoke after changing inventory")
	var production := InventoryDevelopmentCommand.new()
	production.command_id = &"production-rejected"
	production.operation = "resist"
	production.authenticated_context = AuthenticatedCommandContext.from_authenticated_session(&"local-inventory-target", &"session", world.world_id, world.region_id, PackedStringArray(["inventory.development"]))
	world.enqueue_command(production)
	_step(world)
	_check(not _last_result.is_success, "authenticated production origin must not access fixture commands")
	world.free()
	var source: WorldRuntime = _world()
	_enqueue(source, "local-inventory-actor", "start", _intent("take"), "take-restore")
	_step(source)
	_step(source, 20)
	var detached: Dictionary = _inventory(source).capture_snapshot().value
	detached["jobs"][0]["request"]["destination_container_id"] = "invented"
	_check(_inventory(source).capture_snapshot().value["jobs"][0]["request"]["destination_container_id"] == "body.human-2", "saved transfer intents must be detached from runtime work")
	var saved: String = source.capture_world_snapshot_json().value
	var restored: WorldRuntime = _world(false)
	var recovered: ServiceResult = restored.restore_world_snapshot_json(saved)
	_check(recovered.is_success, "inventory and active jobs must restore through world JSON: " + recovered.message)
	if not recovered.is_success:
		source.free()
		restored.free()
		quit(1)
		return
	_check(_inventory(restored).capture_snapshot().value["jobs"][0]["job"]["state"] == "paused", "restored job must require explicit resume")
	_start(restored)
	_step(restored, 10)
	_check(_inventory(restored).capture_snapshot().value["jobs"][0]["job"]["progress_ticks"] == 20, "paused restored job must gain no automatic progress")
	_enqueue(restored, "local-inventory-actor", "resume", {"job_id": "take-restore"}, "resume-restore")
	_step(restored)
	_check(_last_result.is_success, "initiating actor must resume revalidated saved job")
	_step(restored, 160)
	_check(_inventory(restored).capture_snapshot().value["owner"]["receipts"].size() == 1, "resumed job must complete only its remaining work once")
	var invalid: Dictionary = JSON.parse_string(saved)
	invalid["systems"]["inventory"]["jobs"][0]["job"]["target_action_epoch"] = 999
	var reject: WorldRuntime = _world(false)
	var before: String = reject.capture_world_snapshot_json().value
	_check(not reject.restore_world_snapshot_json(JSON.stringify(invalid)).is_success and reject.capture_world_snapshot_json().value == before, "invalid future job epoch must reject world restore atomically")
	var legacy: Dictionary = JSON.parse_string(saved)
	legacy["systems"].erase("inventory")
	legacy["systems"].erase("health")
	var old_world: WorldRuntime = _world(false)
	_check(old_world.restore_world_snapshot_json(JSON.stringify(legacy)).is_success, "older worlds must migrate an empty inventory system")
	_check(_inventory(old_world).capture_snapshot().value["owner"]["ledger"]["items"].is_empty(), "legacy migration must not spawn duplicate fixture matter")
	source.free()
	restored.free()
	reject.free()
	old_world.free()
	if _failures == 0:
		print("Inventory fixed-tick commands and world recovery scenarios passed.")
	quit(0 if _failures == 0 else 1)


func _world(start: bool = true) -> WorldRuntime:
	var world := WorldRuntime.new()
	root.add_child(world)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: _last_result = result)
	if start:
		_start(world)
	return world


func _start(world: WorldRuntime) -> void:
	_check(world.start_simulation().is_success, "world must start with inventory catalogs")
	(world.get_node("SimulationRunner") as SimulationRunner).set_physics_process(false)


func _step(world: WorldRuntime, count: int = 1) -> void:
	for _index in range(count):
		(world.get_node("SimulationRunner") as SimulationRunner)._physics_process(1.0 / 60.0)


func _inventory(world: WorldRuntime) -> InventorySimulationSystem:
	return world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem


func _context(world: WorldRuntime, principal: String) -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.for_local_development(StringName(principal), world.world_id, world.region_id)


func _enqueue(world: WorldRuntime, principal: String, operation: String, payload: Dictionary, id: String) -> void:
	var command := InventoryDevelopmentCommand.new()
	command.command_id = StringName(id)
	command.operation = operation
	command.payload = payload
	command.authenticated_context = _context(world, principal)
	_check(world.enqueue_command(command).is_success, "development intent must enqueue")


func _intent(action: String) -> Dictionary:
	return {"action": action, "target_body_id": "body.human-1", "target_container_id": "storage.pouch-1", "item_id": "" if action == "search" else "crowbar-1", "slot_id": "",
		"destination_container_id": "" if action == "search" else "body.human-2", "expected_revision": 0}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
