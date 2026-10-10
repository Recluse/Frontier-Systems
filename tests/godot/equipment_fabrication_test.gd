extends SceneTree

var _world: WorldRuntime
var _runner: SimulationRunner
var _production: ProductionSimulationSystem
var _inventory: InventorySimulationSystem
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
	_context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", _world.world_id, _world.region_id)
	var bad_blueprint: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/production/equipment-blueprints.v1.json"))
	bad_blueprint["blueprints"]["equipment.canister"]["materials"]["iron"] = -1
	_check(not EquipmentBlueprintCatalog.new().configure(bad_blueprint, _inventory, _production.observation(_context).value["store"].keys()).is_success, "negative blueprint materials reject at startup")
	var legacy: Dictionary = JSON.parse_string(_world.capture_world_snapshot_json().value)
	legacy["systems"]["production"]["schema_version"] = 2
	legacy["systems"]["production"].erase("structures")
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(clone.restore_world_snapshot_json(JSON.stringify(legacy)).is_success, "v2 saves migrate without spawning fabricated equipment")
	clone.free()
	legacy["systems"]["production"]["schema_version"] = 1
	legacy["systems"]["production"].erase("cargo")
	clone = WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(clone.restore_world_snapshot_json(JSON.stringify(legacy)).is_success, "v1 saves migrate to empty cargo and structural maps")
	clone.free()
	_command("fabricate_equipment", {"blueprint_id": "equipment.canister"}, false)
	_command("fabricate_equipment", {"blueprint_id": "unknown"}, false)
	for batch in range(3):
		_move([-3000, 0, -1000])
		_command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		_move([0, 0, 0])
		_command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		_command("process", {"recipe_id": "refine.iron"})
		for _tick in range(120):
			_step()
	_command("power", {"station": "printer", "enabled": false})
	_command("fabricate_equipment", {"blueprint_id": "equipment.extractor"}, false)
	_command("power", {"station": "printer", "enabled": true})
	var limited_record: Dictionary = JSON.parse_string(_world.capture_world_snapshot_json().value)
	for container in limited_record["systems"]["inventory"]["owner"]["ledger"]["containers"]:
		if container["container_id"] == "body.human-2":
			container["capacity"]["max_items"] = 2
	var limited := WorldRuntime.new()
	limited.resource_carriers_enabled = true
	root.add_child(limited)
	_check(limited.restore_world_snapshot_json(JSON.stringify(limited_record)).is_success and limited.start_simulation().is_success, "bounded inventory scenario starts")
	var limited_runner: SimulationRunner = limited.get_node("SimulationRunner")
	limited_runner.set_physics_process(false)
	var limited_production := limited.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem
	var capacity_result: Dictionary = {}
	limited.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: capacity_result["result"] = result)
	var capacity_command := ProductionDevelopmentCommand.new()
	capacity_command.command_id = &"full-equipment-inventory"
	capacity_command.authenticated_context = _context
	capacity_command.operation = "fabricate_equipment"
	capacity_command.payload = {"blueprint_id": "equipment.canister", "expected_revision": limited_production.capture_snapshot().value["state_revision"]}
	var limited_before: Dictionary = limited_production.capture_snapshot().value
	limited.enqueue_command(capacity_command)
	limited_runner._physics_process(1.0 / 60.0)
	var limited_after: Dictionary = limited_production.capture_snapshot().value
	_check(not capacity_result["result"].is_success and limited_after["store"] == limited_before["store"] and limited_after["energy_joules"] == limited_before["energy_joules"] and limited_after["structures"].is_empty(), "inventory capacity failure leaves resources, energy and equipment unchanged")
	limited.free()
	var before_mass: int = int(_inventory.own_inventory_observation(_context).value["mass_milligrams"])
	var payload: Dictionary = {"blueprint_id": "equipment.extractor", "expected_revision": _state()["state_revision"]}
	_sequence += 1
	var retained: String = "equipment-test-%d" % _sequence
	_enqueue("fabricate_equipment", payload, retained)
	_check(_last.is_success, "extractor fabricates from refined iron")
	var extractor: String = _state()["structures"].keys()[0]
	_check(_production.payload_mass(extractor) == 1500000 and _inventory.own_inventory_observation(_context).value["mass_milligrams"] == before_mass + 1500000, "fabricated tool mass is counted once")
	_enqueue("fabricate_equipment", payload, retained)
	_check(_last.is_success and _state()["structures"].size() == 1, "retained fabrication retry does not create another item")
	var rejected: Dictionary = payload.duplicate(true)
	rejected["blueprint_id"] = "equipment.canister"
	_enqueue("fabricate_equipment", rejected, retained)
	_check(not _last.is_success and _state()["structures"].size() == 1, "changed retained intent rejects")
	_self("equip", extractor, "body.human-2", "hand.left")
	_move([-3000, 0, -1000])
	_self("select_hand", "", "", "hand.right")
	_command("tool_extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000}, false)
	_self("select_hand", "", "", "hand.left")
	_command("tool_extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
	_move([0, 0, 0])
	var saved: Dictionary = JSON.parse_string(_world.capture_world_snapshot_json().value)
	clone = WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(clone.restore_world_snapshot_json(JSON.stringify(saved)).is_success, "equipped fabricated tool and its used carrier restore together")
	clone.free()
	var orphan: Dictionary = saved.duplicate(true)
	var kept: Array = []
	for item in orphan["systems"]["inventory"]["owner"]["ledger"]["items"]:
		if item["item_id"] != extractor:
			kept.append(item)
	orphan["systems"]["inventory"]["owner"]["ledger"]["items"] = kept
	for body in orphan["systems"]["inventory"]["owner"]["bodies"]:
		if body["body_id"] == "body.human-2":
			body["equipped"] = [{"slot_id": "back", "item_id": "backpack-2"}]
	clone = WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(not clone.restore_world_snapshot_json(JSON.stringify(orphan)).is_success, "orphaned structural records cannot restore without actual equipment")
	clone.free()
	var forged: Dictionary = saved.duplicate(true)
	forged["systems"]["production"]["structures"][extractor]["materials"]["iron"] += 1
	forged["systems"]["production"]["store"]["iron"] -= 1
	clone = WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(not clone.restore_world_snapshot_json(JSON.stringify(forged)).is_success, "balanced mass cannot forge a pinned construction specification")
	clone.free()
	_command("salvage_equipment", {"item_id": "extractor-1"}, false)
	_command("salvage_equipment", {"item_id": extractor})
	_check(_inventory.own_inventory_observation(_context).value["equipped"].size() == 1 and _state()["store"]["iron"] == 1800000, "salvage releases tool equipment binding and restores construction iron")
	_command("fabricate_equipment", {"blueprint_id": "equipment.canister"})
	var canister: String = _state()["structures"].keys()[0]
	_command("load_cargo", {"carrier_id": canister, "material": "iron", "amount_milligrams": 100000})
	_check(_production.payload_mass(canister) == 1100000, "canister structural mass and contents remain separate")
	_command("salvage_equipment", {"item_id": canister})
	_check(_state()["structures"].is_empty() and not _state()["cargo"].has(canister) and _state()["store"]["iron"] == 1800000, "loaded salvage returns structure and contents atomically")
	_check(_production.validate_snapshot_record(_state(), _world.current_tick_number()).is_success, "complete fabrication loop conserves the fixture matter budget")
	_world.free()
	if _failures == 0:
		print("Equipment fabrication: blueprint validation, migration, refined-material assembly, active-hand tool use, retained retries, restore and loaded salvage passed.")
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
	_check(_last.is_success, "equipment/hand command applies")


func _step() -> void:
	_runner._physics_process(1.0 / 60.0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
