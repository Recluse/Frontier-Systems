extends SceneTree
var _world: WorldRuntime
var _runner: SimulationRunner
var _production: ProductionSimulationSystem
var _inventory: InventorySimulationSystem
var _tools: ToolSimulationSystem
var _context: AuthenticatedCommandContext
var _last: ServiceResult
var _sequence: int = 0
var _failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_world = WorldRuntime.new()
	_world.resource_carriers_enabled = true
	root.add_child(_world)
	_world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: _last = result)
	_check(_world.start_simulation().is_success, "world starts")
	_runner = _world.get_node("SimulationRunner")
	_runner.set_physics_process(false)
	_production = _world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	_inventory = _world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	_tools = _world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID)
	_context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", _world.world_id, _world.region_id)
	var observed: Dictionary = _tools.observation(_context).value
	_check(ToolObservationValidation.valid(observed), "bounded network view accepts scoped tools")
	var forged: Dictionary = observed.duplicate(true)
	forged["assemblies"][0]["parts"][0]["integrity_ppm"] = -1
	_check(not ToolObservationValidation.valid(forged), "invalid condition rejected by client")
	var ledger: Dictionary = _tools.capture_snapshot().value["ledger"]
	var head: String = ledger["assemblies"]["extractor-1"]["slots"]["head"]
	var drive: String = ledger["assemblies"]["extractor-1"]["slots"]["drive"]
	_repair(head, false) # Full condition does not debit energy.
	_self("equip", "extractor-1", "storage.backpack-2", "hand.left")
	_self("select_hand", "", "", "hand.left")
	_move([-3000, 0, -1000])
	var payload: Dictionary = {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000, "expected_revision": _state()["state_revision"]}
	_enqueue("tool_extract", payload, "tool-wear-once")
	_check(_last.is_success, "equipped extractor performs completed work")
	ledger = _tools.capture_snapshot().value["ledger"]
	_check(ledger["parts"][head]["integrity_ppm"] == 999999 and ledger["parts"][drive]["wear_remainder"] == 250, "space-tier wear is one ppm, fractional drive wear retained")
	_enqueue("tool_extract", payload, "tool-wear-once")
	_check(_last.is_success and ledger == _tools.capture_snapshot().value["ledger"], "retained retry does not wear twice")
	for _tick in range(100): _step()
	_check(ledger == _tools.capture_snapshot().value["ledger"], "idle ticks never wear tools")
	_repair(head, false) # Out of workstation reach.
	_move([0, 0, 0])
	var other := AuthenticatedCommandContext.for_local_development(&"local-inventory-target", _world.world_id, _world.region_id)
	_check(not _tools.prepare_repair(other, head, 1000000, ledger["state_revision"]).is_success, "another crew cannot maintain private parts")
	_check(not _tools.prepare_repair(_context, head, 1000000, ledger["state_revision"] - 1).is_success, "stale tool revision rejects")
	_command("power", {"station": "construction", "enabled": false})
	_repair(head, false)
	_command("power", {"station": "construction", "enabled": true})
	var energy: int = _state()["energy_joules"]
	_repair(head)
	_check(_state()["energy_joules"] < energy and _tools.capture_snapshot().value["ledger"]["parts"][head]["integrity_ppm"] == 1000000, "paid maintenance restores part atomically")
	var saved: Dictionary = JSON.parse_string(_world.capture_world_snapshot_json().value)
	_restore_check(saved, true, "component condition and fractional wear restore")
	var broken: Dictionary = saved.duplicate(true)
	broken["systems"]["tools"]["ledger"]["parts"][head]["integrity_ppm"] = 0
	_repair_in_clone(broken, head, true)
	broken["systems"]["production"]["energy_joules"] = 0
	_repair_in_clone(broken, head, false)
	var missing: Dictionary = saved.duplicate(true)
	missing["systems"]["tools"]["ledger"]["parts"].erase(head)
	_restore_check(missing, false, "missing part rejects whole restore")
	var malformed: Dictionary = saved.duplicate(true)
	malformed["systems"]["tools"]["ledger"] = []
	_restore_check(malformed, false, "non-object ledger rejects without script errors")
	var legacy: Dictionary = saved.duplicate(true)
	legacy["systems"].erase("tools")
	for item in legacy["systems"]["inventory"]["owner"]["ledger"]["items"]:
		if item["item_id"] == "extractor-1": item["condition_permille"] = 0
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(clone.restore_world_snapshot_json(JSON.stringify(legacy)).is_success, "legacy scalar condition migrates")
	var clone_tools := clone.get_simulation_system(ToolSimulationSystem.SYSTEM_ID) as ToolSimulationSystem
	_check(clone_tools.capture_snapshot().value["ledger"]["parts"][head]["integrity_ppm"] == 0 and not clone_tools.capability("extractor-1", "tool.extractor").value, "broken legacy tools stay broken and retain parts")
	clone.free()
	_world.free()
	if _failures == 0: print("Live tools: scoped views, completed-work wear, retained retries, idle ticks, paid maintenance, ownership, power/reach, saved condition and migration passed.")
	quit(0 if _failures == 0 else 1)

func _repair(part: String, success: bool = true) -> void:
	var before: Dictionary = _tools.capture_snapshot().value["ledger"]
	var energy: int = _state()["energy_joules"]
	_command("repair_tool_component", {"part_id": part, "amount_ppm": 1000000, "expected_tool_revision": before["state_revision"]}, success)
	if not success: _check(before == _tools.capture_snapshot().value["ledger"] and energy == _state()["energy_joules"], "failed repair changes neither condition nor energy")

func _restore_check(record: Dictionary, success: bool, message: String) -> void:
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(clone.restore_world_snapshot_json(JSON.stringify(record)).is_success == success, message)
	clone.free()


func _repair_in_clone(record: Dictionary, part: String, success: bool) -> void:
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(clone.restore_world_snapshot_json(JSON.stringify(record)).is_success and clone.start_simulation().is_success, "broken-part repair fixture starts")
	var runner: SimulationRunner = clone.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var tools := clone.get_simulation_system(ToolSimulationSystem.SYSTEM_ID) as ToolSimulationSystem
	var production := clone.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem
	var before: Dictionary = tools.capture_snapshot().value["ledger"]
	var result: Dictionary = {}
	clone.command_completed.connect(func(_command: SimulationCommand, completed: ServiceResult) -> void: result["value"] = completed)
	var command := ProductionDevelopmentCommand.new()
	command.command_id = &"revive-broken-tool"
	command.authenticated_context = _context
	command.operation = "repair_tool_component"
	command.payload = {"part_id": part, "amount_ppm": 1000000, "expected_tool_revision": before["state_revision"], "expected_revision": production.capture_snapshot().value["state_revision"]}
	clone.enqueue_command(command)
	runner._physics_process(1.0 / 60.0)
	_check(result["value"].is_success == success, "broken component repair settles energy")
	_check(tools.capability("extractor-1", "tool.extractor").value == success, "repair recovers disabled capability only when paid")
	if not success: _check(before == tools.capture_snapshot().value["ledger"], "insufficient energy preserves broken parts")
	clone.free()

func _state() -> Dictionary:
	return _production.capture_snapshot().value


func _command(operation: String, payload: Dictionary, success: bool = true) -> void:
	payload["expected_revision"] = _state()["state_revision"]
	_sequence += 1
	_enqueue(operation, payload, "equipment-test-%d" % _sequence)
	_check(_last.is_success == success, operation + ": " + _last.message)


func _enqueue(operation: String, payload: Dictionary, id: String) -> void:
	var command := ProductionDevelopmentCommand.new()
	command.command_id = StringName(id)
	command.operation = operation
	command.payload = payload
	command.authenticated_context = _context
	_check(_world.enqueue_command(command).is_success, "production command queued")
	_step()


func _move(position: Array) -> void:
	var command := InventoryDevelopmentCommand.new()
	_sequence += 1
	command.command_id = StringName("equipment-move-%d" % _sequence)
	command.operation = "move_to"
	command.payload = {"position_millimetres": position}
	command.authenticated_context = _context
	_check(_world.enqueue_command(command).is_success, "movement queued")
	_step()
	_check(_last.is_success, "fixture movement applies")


func _self(operation: String, item: String, source: String, slot: String) -> void:
	var command := InventoryDevelopmentCommand.new()
	_sequence += 1
	command.command_id = StringName("equipment-self-%d" % _sequence)
	command.operation = "self"
	command.payload = {"operation": operation, "item_id": item, "source_container_id": source, "destination_container_id": "", "slot_id": slot, "expected_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"]}
	command.authenticated_context = _context
	_check(_world.enqueue_command(command).is_success, "self command queued")
	_step()
	_check(_last.is_success, "equipment/hand command applies: " + _last.message)


func _step() -> void:
	_runner._physics_process(1.0 / 60.0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
