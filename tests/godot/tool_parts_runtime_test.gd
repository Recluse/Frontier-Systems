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
	_part_command("fabricate_tool_part", {"blueprint_id": "part.head.space"}, false)
	for _batch in range(6): _refine("deposit.iron", "ore.iron", "refine.iron")
	_command("fabricate_equipment", {"blueprint_id": "equipment.extractor"})
	var tool: String = _state()["structures"].keys()[0]
	var old_head: String = _tools.capture_snapshot().value["ledger"]["assemblies"][tool]["slots"]["head"]
	_self("equip", tool, "body.human-2", "hand.left")
	_self("select_hand", "", "", "hand.left")
	_move([-3000, 0, -1000])
	_command("tool_extract", {"deposit_id":"deposit.iron", "carrier_id":"resource-canister-1", "amount_milligrams":1000000})
	_move([0, 0, 0])
	_command("unload_cargo", {"carrier_id":"resource-canister-1", "material":"ore.iron", "amount_milligrams":1000000})
	var head_before: Dictionary = _tools.capture_snapshot().value["ledger"]["parts"][old_head]
	var basic: String = _fabricate("part.head.basic")
	var before_mass: int = _inventory.own_inventory_observation(_context).value["mass_milligrams"]
	_part_command("fit_tool_part", {"item_id":tool,"slot_id":"head","part_id":basic})
	_check(_state()["loose_parts"].has(old_head) and not _state()["loose_parts"].has(basic), "replacement retains displaced physical part")
	_check(_tools.capture_snapshot().value["ledger"]["parts"][old_head] == head_before, "removed worn head preserves identity, condition and wear")
	_check(before_mass == _inventory.own_inventory_observation(_context).value["mass_milligrams"], "replacement does not duplicate carried matter")
	var after: Dictionary = _tools.capture_snapshot().value["ledger"]
	var last_payload: Dictionary = {"item_id":tool,"slot_id":"head","part_id":basic,"expected_revision":_state()["receipts"][-1]["state_revision"] - 1,"expected_tool_revision":after["state_revision"] - 1}
	_enqueue("fit_tool_part", last_payload, _state()["receipts"][-1]["request_id"])
	_check(_last.is_success and after == _tools.capture_snapshot().value["ledger"], "retained replacement retry is idempotent")
	_part_command("fit_tool_part", {"item_id":tool,"slot_id":"drive","part_id":old_head}, false)
	_part_command("detach_tool_part", {"item_id":"extractor-1","slot_id":"head"}, false)
	var controller: String = _fabricate("part.controller.space")
	_part_command("fit_tool_part", {"item_id":tool,"slot_id":"module","part_id":controller})
	_check(_state()["structures"][tool]["materials"]["iron"] == 1600000, "optional module changes installed mass")
	_check(_assembly(tool)["actions"]["action.scan"]["available"], "controller enables dependency-backed scanning capability")
	var lever: String = _fabricate("part.lever.space")
	_part_command("fit_tool_part", {"item_id":tool,"slot_id":"head","part_id":lever})
	_check(not _tools.capability(tool, "tool.extractor").value, "compatible nonsensical head may mount while extraction is unavailable")
	_part_command("detach_tool_part", {"item_id":tool,"slot_id":"head"})
	_check(not _tools.capability(tool, "tool.extractor").value and _state()["loose_parts"].has(lever), "missing head disables only its functions and retains part")
	for _batch in range(3): _refine("deposit.regolith", "regolith", "refine.regolith")
	var ceramic: String = _fabricate("part.head.ceramic")
	_part_command("fit_tool_part", {"item_id":tool,"slot_id":"head","part_id":ceramic})
	_check(_state()["structures"][tool]["materials"] == {"iron":700000,"silicate":900000} and _tools.capability(tool,"tool.extractor").value, "material upgrade preserves exact mixed construction matter")
	var observed: Dictionary = _tools.observation(_context).value
	_check(ToolObservationValidation.valid(observed) and observed["loose_parts"].size() == 3, "scoped mounted and loose part observation validates")
	var other := AuthenticatedCommandContext.for_local_development(&"local-inventory-target", _world.world_id, _world.region_id)
	_check(_tools.observation(other).value["loose_parts"].is_empty(), "another crew cannot observe loose parts")
	_check(not _tools.prepare_part_change(other,"fit_tool_part",{"item_id":tool,"slot_id":"head","part_id":old_head,"expected_tool_revision":_tools.capture_snapshot().value["ledger"]["state_revision"]},"unauthorized-fit").is_success, "other owner cannot replace parts")
	var saved: Dictionary = JSON.parse_string(_world.capture_world_snapshot_json().value)
	_restore(saved, true)
	_capacity_check(saved, tool)
	_command("power", {"station":"construction", "enabled":false})
	_part_command("detach_tool_part", {"item_id":tool,"slot_id":"head"}, false)
	_command("power", {"station":"construction", "enabled":true})
	var bad: Dictionary = saved.duplicate(true)
	bad["systems"]["production"]["loose_parts"][old_head]["iron"] += 1
	bad["systems"]["production"]["store"]["iron"] -= 1
	_restore(bad, false)
	for id in [old_head,basic,lever]: _part_command("recycle_tool_part",{"part_id":id})
	var installed: Dictionary = _tools.capture_snapshot().value["ledger"]["assemblies"][tool]["slots"].duplicate(true)
	for slot in installed: _part_command("detach_tool_part", {"item_id":tool,"slot_id":slot})
	_check(_state()["structures"][tool]["materials"].is_empty() and not _tools.capability(tool,"tool.extractor").value, "fully stripped equipment retains an empty assembly identity without matter")
	_restore(JSON.parse_string(_world.capture_world_snapshot_json().value), true)
	for slot in installed: _part_command("fit_tool_part", {"item_id":tool,"slot_id":slot,"part_id":installed[slot]})
	_check(_tools.capability(tool,"tool.extractor").value, "stripped assembly reconstructs from the same persistent parts")
	_command("salvage_equipment", {"item_id":tool})
	_check(_state()["loose_parts"].is_empty() and _state()["structures"].is_empty(), "mixed-material tool and detached parts recycle without leftovers")
	_check(_production.validate_snapshot_record(_state(), _world.current_tick_number()).is_success, "complete loop conserves closed fixture matter")
	_world.free()
	if _failures == 0: print("Physical tool parts: manufacture, replacement, retained wear/retries, module upgrades, missing/nonsensical mounts, ceramic grade, ownership, restart and conserved recycling passed.")
	quit(0 if _failures == 0 else 1)

func _assembly(id: String) -> Dictionary:
	for assembly in _tools.observation(_context).value["assemblies"]:
		if assembly["assembly_id"] == id: return assembly
	return {}

func _refine(deposit: String, material: String, recipe: String) -> void:
	_move(ProductionSimulationSystem.SOURCE_POSITIONS[deposit])
	_command("extract", {"deposit_id":deposit,"carrier_id":"resource-canister-1","amount_milligrams":1000000})
	_move([0,0,0])
	_command("unload_cargo", {"carrier_id":"resource-canister-1","material":material,"amount_milligrams":1000000})
	_command("process", {"recipe_id":recipe})
	for _tick in range(120): _step()

func _fabricate(blueprint: String) -> String:
	_part_command("fabricate_tool_part", {"blueprint_id":blueprint})
	return "tool-part-%s" % String(_state()["receipts"][-1]["request_id"]).sha256_text().substr(0,24)

func _part_command(operation: String, payload: Dictionary, success: bool = true) -> void:
	payload["expected_tool_revision"] = _tools.capture_snapshot().value["ledger"]["state_revision"]
	var before: Dictionary = _tools.capture_snapshot().value["ledger"]
	var production_before: Dictionary = _state()
	_command(operation, payload, success)
	if not success:
		_check(before == _tools.capture_snapshot().value["ledger"] and production_before["store"] == _state()["store"] and production_before["energy_joules"] == _state()["energy_joules"], "failed part transaction is atomic")

func _restore(record: Dictionary, success: bool) -> void:
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(clone.restore_world_snapshot_json(JSON.stringify(record)).is_success == success, "tool/physical part world restore validates associations")
	clone.free()


func _capacity_check(record: Dictionary, tool: String) -> void:
	var limited: Dictionary = record.duplicate(true)
	var count: int = 0
	for item in limited["systems"]["inventory"]["owner"]["ledger"]["items"]:
		if item["container_id"] == "body.human-2": count += 1
	for container in limited["systems"]["inventory"]["owner"]["ledger"]["containers"]:
		if container["container_id"] == "body.human-2": container["capacity"]["max_items"] = count
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(clone.restore_world_snapshot_json(JSON.stringify(limited)).is_success and clone.start_simulation().is_success, "full inventory component fixture restores")
	var runner: SimulationRunner = clone.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var tools := clone.get_simulation_system(ToolSimulationSystem.SYSTEM_ID) as ToolSimulationSystem
	var production := clone.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem
	var before: Dictionary = tools.capture_snapshot().value["ledger"]
	var energy: int = production.capture_snapshot().value["energy_joules"]
	var result: Dictionary = {}
	clone.command_completed.connect(func(_command: SimulationCommand, completed: ServiceResult) -> void: result["value"] = completed)
	var command := ProductionDevelopmentCommand.new()
	command.command_id = &"full-parts-inventory"
	command.authenticated_context = _context
	command.operation = "detach_tool_part"
	command.payload = {"item_id":tool,"slot_id":"head","expected_tool_revision":before["state_revision"],"expected_revision":production.capture_snapshot().value["state_revision"]}
	clone.enqueue_command(command)
	runner._physics_process(1.0 / 60.0)
	_check(not result["value"].is_success and before == tools.capture_snapshot().value["ledger"] and production.capture_snapshot().value["energy_joules"] == energy, "full inventory cannot lose detached part, installed condition or energy")
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
	_check(_last.is_success, "equipment/hand command applies")


func _step() -> void:
	_runner._physics_process(1.0 / 60.0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
