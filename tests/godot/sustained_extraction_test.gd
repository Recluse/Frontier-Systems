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
	_self("equip", "extractor-1", "storage.backpack-2", "hand.left")
	_self("select_hand", "", "", "hand.left")
	_move([-3000,0,-1000])
	var payload: Dictionary = {"deposit_id":"deposit.iron", "carrier_id":"resource-canister-1", "cycles":3, "expected_revision":_state()["state_revision"]}
	_enqueue("start_tool_extract", payload, "sustained-once")
	_check(_last.is_success and _state()["deposits"]["deposit.iron"] == 7000000, "start reserves exactly three kilograms")
	_enqueue("start_tool_extract", payload, "sustained-once")
	_check(_last.is_success and _state()["deposits"]["deposit.iron"] == 7000000, "retained start does not reserve twice")
	for _tick in range(58): _step()
	_check(_state()["cargo"]["resource-canister-1"]["ore.iron"] == 1000000, "one timed cycle commits one kilogram")
	var head: String = _tools.capture_snapshot().value["ledger"]["assemblies"]["extractor-1"]["slots"]["head"]
	_check(_tools.capture_snapshot().value["ledger"]["parts"][head]["integrity_ppm"] == 999999, "wear is charged for completed work only")
	for _tick in range(120): _step()
	_check(_state()["job"]["extraction"]["status"] == "paused" and _state()["job"]["extraction"]["pause_reason"] == "capacity" and _state()["job"]["extraction"]["remaining_cycles"] == 1, "full carrier pauses without losing reservation")
	var energy: int = _state()["energy_joules"]
	for _tick in range(60): _step()
	_check(_state()["energy_joules"] == energy and _tools.capture_snapshot().value["ledger"]["parts"][head]["integrity_ppm"] == 999998, "paused ticks cost no energy or wear")
	var other := AuthenticatedCommandContext.for_local_development(&"local-inventory-target", _world.world_id, _world.region_id)
	_check(_production.observation(other).value["tool_extraction"].is_empty(), "private tool binding does not leak to another crew")
	_move([0,0,0])
	_command("unload_cargo", {"carrier_id":"resource-canister-1","material":"ore.iron","amount_milligrams":2000000})
	_move([-3000,0,-1000])
	_command("resume_tool_extract", {})
	for _tick in range(60): _step()
	_check(_state()["job"].is_empty() and _state()["cargo"]["resource-canister-1"]["ore.iron"] == 1000000 and _tools.capture_snapshot().value["ledger"]["parts"][head]["integrity_ppm"] == 999997, "resumed final cycle completes exactly once")
	_command("start_tool_extract", {"deposit_id":"deposit.iron","carrier_id":"resource-canister-1","cycles":2})
	for _tick in range(10): _step()
	var saved: Dictionary = JSON.parse_string(_world.capture_world_snapshot_json().value)
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(clone.restore_world_snapshot_json(JSON.stringify(saved)).is_success and clone.start_simulation().is_success, "reserved work restores")
	var runner: SimulationRunner = clone.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var prod := clone.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem
	var before: Dictionary = prod.capture_snapshot().value
	for _tick in range(100): runner._physics_process(1.0 / 60.0)
	_check(prod.capture_snapshot().value["cargo"] == before["cargo"] and prod.capture_snapshot().value["job"]["extraction"]["pause_reason"] == "restart", "restart requires explicit resume and preserves reserved progress")
	clone.free()
	_self("select_hand", "", "", "hand.right")
	_check(_state()["job"]["extraction"]["status"] == "paused", "changed active hand interrupts work")
	_command("resume_tool_extract", {}, false)
	_self("select_hand", "", "", "hand.left")
	_command("resume_tool_extract", {})
	var operator: AuthenticatedCommandContext = _context
	_context = other
	_command("power", {"station":"drill","enabled":false})
	_context = operator
	_check(_state()["job"]["extraction"]["pause_reason"] == "power", "power loss pauses work")
	_command("cancel_tool_extract", {})
	_check(_state()["deposits"]["deposit.iron"] == 7000000 and _state()["job"].is_empty(), "cancel returns only unprocessed reserve to source")
	_check(_production.validate_snapshot_record(_state(),_world.current_tick_number()).is_success,"reservation/cargo loop conserves the closed fixture")
	_world.free()
	if _failures == 0: print("Sustained extraction: reservations, retries, per-cycle output/wear, capacity/hand/power interruption, explicit resume, cancellation and safe restart passed.")
	quit(0 if _failures == 0 else 1)

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
