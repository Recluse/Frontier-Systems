extends SceneTree

var _world: WorldRuntime
var _runner: SimulationRunner
var _terrain: TerrainSimulationSystem
var _inventory: InventorySimulationSystem
var _tools: ToolSimulationSystem
var _production: ProductionSimulationSystem
var _context: AuthenticatedCommandContext
var _last: ServiceResult
var _helper_id: int = 0
var _failures: int = 0
var _shovel: String = ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	_bind(world)
	_context = _session("local-inventory-actor", ["inventory.operate", "terrain.operate"])
	_check(_world.start_simulation().is_success, "registered terrain world starts")
	var fresh: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_check(_mass() == 2000000, "new-world terrain has an independent 2 kg generation budget")
	var legacy: Dictionary = fresh.duplicate(true)
	legacy["systems"].erase("terrain")
	var migrated := _clone(legacy)
	var migrated_terrain := migrated.get_simulation_system(TerrainSimulationSystem.SYSTEM_ID) as TerrainSimulationSystem
	_check(migrated_terrain.capture_snapshot().value["owner"]["cells"]["terrain.dirt.source"]["state"]["mass_milligrams"] == 0, "legacy world receives no new terrain matter")
	_check(migrated_terrain.capture_snapshot().value["owner"]["cells"]["terrain.dirt.source"]["capacity_milligrams"] == 0, "legacy fixture has zero commissioning capacity")
	migrated.free()
	# The real production fixture fabricates the shovel from three finite ore batches.
	for batch in range(3):
		_move([-3000, 0, -1000])
		_produce("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
		_move([0, 0, 0])
		_produce("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
		_produce("process", {"recipe_id": "refine.iron"})
		for tick in range(120): _step()
	_produce("fabricate_equipment", {"blueprint_id": "equipment.shovel"})
	_shovel = _production.capture_snapshot().value["structures"].keys()[0]
	_context.tools_by_capability[&"tool.shovel"] = PackedStringArray(["forged-client-shovel"])
	var without_tool: Dictionary = _payload("terrain.dirt.source", 1000000)
	_deny("excavate", without_tool, "declared tool tags cannot replace an actually held shovel")
	_context.tools_by_capability.clear()
	_self("equip", _shovel, "body.human-2", "hand.left")
	_self("select_hand", "", "", "hand.left")
	_check(_tools.capability(_shovel, "tool.shovel").value == true, "actual manufactured components support excavation")
	_deny("excavate", without_tool, "stale inventory revision rejects")
	var no_grant: AuthenticatedCommandContext = _session("local-inventory-actor", ["inventory.operate"])
	var actor: AuthenticatedCommandContext = _context
	_context = no_grant
	_deny("excavate", _payload("terrain.dirt.source", 1000000), "authenticated remote identity without terrain permission rejects")
	_context = actor
	var command := TerrainCommand.new()
	command.command_id = &"terrain-client-1"
	command.request_number = 1
	command.operation = "excavate"
	command.payload = _payload("terrain.dirt.source", 1000000)
	command.authenticated_context = _session("local-inventory-actor", ["inventory.operate", "terrain.operate"])
	command.authenticated_context.region_id = &"foreign-region"
	var before: Dictionary = _canonical()
	_check(not _world.enqueue_command(command).is_success and _canonical() == before, "foreign region ingress denies without changing terrain")
	_move([10000, 0, 0])
	_deny("excavate", _payload("terrain.dirt.source", 1000000), "out-of-reach excavation rejects")
	_move([0, 0, 0])
	var stale: Dictionary = _payload("terrain.dirt.source", 1000000)
	stale["expected_tool_revision"] += 1
	_deny("excavate", stale, "stale component revision rejects")
	stale = _payload("terrain.dirt.source", 1000000)
	stale["expected_cell_revision"] += 1
	_deny("excavate", stale, "stale cell revision rejects")
	stale = _payload("terrain.dirt.source", 1000001)
	_deny("excavate", stale, "bounded command quantity rejects excess")
	_self("equip", "extractor-1", "storage.backpack-2", "hand.right")
	_deny("excavate", _payload("terrain.dirt.source", 1000000), "occupied supporting hand rejects")
	_self("unequip", "", "", "hand.right")
	var ready: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	# Trusted health input settles on a tick before testing voluntary action denial.
	var health := _world.get_simulation_system(HealthSimulationSystem.SYSTEM_ID) as HealthSimulationSystem
	var causes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/health/suppression.combined.v1.json"))
	_check(health.queue_observation("body.human-2", causes, 0, _world.current_tick_number() + 1).is_success, "trusted unconscious fixture queues")
	_step()
	_deny("excavate", _payload("terrain.dirt.source", 1000000), "unconscious actor cannot excavate")
	_restart(ready)
	# Break the mounted shovel head without altering conserved component matter.
	var broken: Dictionary = ready.duplicate(true)
	var head: String = broken["systems"]["tools"]["ledger"]["assemblies"][_shovel]["slots"]["head"]
	broken["systems"]["tools"]["ledger"]["parts"][head]["integrity_ppm"] = 0
	_restart(broken)
	_deny("excavate", _payload("terrain.dirt.source", 1000000), "broken component-backed shovel rejects")
	_restart(ready)
	var before_skipped: Dictionary = _canonical()
	_send("excavate", _payload("terrain.dirt.source", 1000000), 2)
	_check(not _last.is_success and _canonical() == before_skipped, "skipped principal ordinal rejects unchanged")
	var first_payload: Dictionary = _payload("terrain.dirt.source", 1000000)
	_send("excavate", first_payload, 1)
	_check(_last.is_success and _mass() == 2000000 and _state()["owner"]["cells"]["terrain.dirt.source"]["state"]["mass_milligrams"] == 1000000, "finite dig transfers exact mass into escrow")
	var first_receipt: Dictionary = _last.value.duplicate(true)
	var after_first: Dictionary = _canonical()
	_send("excavate", first_payload, 1)
	_check(_last.is_success and _last.value == first_receipt and _canonical() == after_first, "retained retry returns original owner receipt")
	_self("select_hand", "", "", "hand.right")
	_send("excavate", first_payload, 1)
	_check(_last.is_success and _canonical() == after_first, "retained reconciliation does not require repeating now-unavailable work")
	_self("select_hand", "", "", "hand.left")
	var results: Array = []
	var listener: Callable = func(_command: SimulationCommand, result: ServiceResult) -> void: results.append(result.is_success)
	_world.command_completed.connect(listener)
	for index in range(17):
		var retry := TerrainCommand.new()
		retry.command_id = &"terrain-client-1"
		retry.request_number = 1
		retry.operation = "excavate"
		retry.payload = first_payload.duplicate(true)
		retry.authenticated_context = _context
		_check(_world.enqueue_command(retry).is_success, "bounded retry batch queues")
	_step()
	_world.command_completed.disconnect(listener)
	_check(results.size() == 17 and results.count(true) == 16 and _canonical() == after_first, "per-tick terrain budget admits sixteen commands and rejects excess unchanged")
	var changed: Dictionary = first_payload.duplicate(true)
	changed["amount_milligrams"] = 1
	_send("excavate", changed, 1)
	_check(not _last.is_success and _canonical() == after_first, "changed retained intent rejects unchanged")
	var foreign := _session("local-inventory-target", ["inventory.operate", "terrain.operate"])
	_check(_world.terrain_observation(foreign).value["transfers"].is_empty(), "other principal cannot observe escrow")
	_context = foreign
	_deny("fill", _payload("terrain.dirt.fill", 500000, "terrain-transfer-1"), "foreign transfer fill rejects")
	_check(_last.message.contains("claimant"), "foreign transfer denial checks claimant permission")
	_context = actor
	var fill_payload: Dictionary = _payload("terrain.dirt.fill", 400000, "terrain-transfer-1")
	_send("fill", fill_payload, 2)
	_check(_last.is_success and _state()["owner"]["transfers"]["terrain-transfer-1"]["mass_milligrams"] == 600000 and _mass() == 2000000, "partial cross-cell fill conserves exact escrow and provenance")
	var saved: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	var original: Dictionary = _canonical()
	_restart(saved)
	_check(_canonical() == original, "JSON checkpoint recovers owner, positions, mappings and claims")
	_send("excavate", first_payload, 1)
	_check(_last.is_success and _last.value == first_receipt and _canonical() == original, "retained retry survives restart")
	var corrupt: Dictionary = saved.duplicate(true)
	corrupt["systems"]["terrain"]["claims"]["terrain-transfer-1"] = "other-principal"
	_reject_snapshot(corrupt, "unknown claimant rejects atomically")
	corrupt = saved.duplicate(true)
	corrupt["systems"]["terrain"]["requests"][0]["owner_sequence"] = 2
	_reject_snapshot(corrupt, "contradictory owner allocation rejects atomically")
	corrupt = saved.duplicate(true)
	corrupt["systems"]["terrain"]["principals"]["local-inventory-actor"] += 1
	_reject_snapshot(corrupt, "contradictory high-water mark rejects atomically")
	corrupt = saved.duplicate(true)
	corrupt["systems"]["terrain"]["positions"]["terrain.dirt.source"][0] = 100000
	_reject_snapshot(corrupt, "changed stable position rejects atomically")
	_send("fill", _payload("terrain.dirt.source", 600000, "terrain-transfer-1"), 3)
	_check(_last.is_success and _state()["claims"].is_empty(), "full fill releases escrow claim")
	# Evict initial runtime mapping and owner receipt while preserving ordinal high-water.
	for cycle in range(33):
		var number: int = _next()
		_send("excavate", _payload("terrain.dirt.source", 1), number)
		_check(_last.is_success, "bounded loop dig")
		_send("fill", _payload("terrain.dirt.source", 1, "terrain-transfer-%d" % _state()["owner"]["last_sequence"]), _next())
		_check(_last.is_success, "bounded loop fill")
	_check(_state()["requests"].size() == 64 and _mass() == 2000000, "runtime and owner tails evict together without matter loss")
	var expired_saved: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(expired_saved)
	before = _canonical()
	_send("excavate", first_payload, 1)
	_check(not _last.is_success and _canonical() == before, "expired request remains denied after eviction and restart")
	var last_mapping: Dictionary = _state()["requests"][-1]
	_send(last_mapping["intent"]["operation"], last_mapping["intent"]["payload"], last_mapping["request_number"])
	_check(_last.is_success and _canonical() == before, "latest retained fill retry remains idempotent after restart")
	_send("excavate", _payload("terrain.dirt.source", 1000000), _next())
	_check(_last.is_success, "first depletion dig")
	_send("excavate", _payload("terrain.dirt.source", 600000), _next())
	_check(_last.is_success, "second depletion dig")
	_send("excavate", _payload("terrain.dirt.fill", 400000), _next())
	_check(_last.is_success and _mass() == 2000000, "all commissioned cell matter becomes finite escrow")
	var depleted: Dictionary = _world.capture_world_snapshot().value.to_dictionary()
	_restart(depleted)
	_deny("excavate", _payload("terrain.dirt.source", 1), "depleted terrain cannot reseed after restart")
	_check(_state()["owner"]["cells"]["terrain.dirt.source"]["state"]["mass_milligrams"] == 0 and _mass() == 2000000, "depletion ledger and escrow survive")
	var exported := FileAccess.open("res://var/terrain-runtime-fixture.json", FileAccess.WRITE)
	exported.store_string(_world.capture_world_snapshot_json().value)
	exported.close()
	_world.free()
	if _failures == 0: print("Terrain runtime: authenticated finite commands, real shovel, capability denials, escrow conservation, legacy zero budget, atomic JSON recovery and retained/expired retries passed.")
	quit(0 if _failures == 0 else 1)


func _bind(world: WorldRuntime) -> void:
	_world = world
	_runner = world.get_node("SimulationRunner")
	_runner.set_physics_process(false)
	_terrain = world.get_simulation_system(TerrainSimulationSystem.SYSTEM_ID)
	_inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	_tools = world.get_simulation_system(ToolSimulationSystem.SYSTEM_ID)
	_production = world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: _last = result)


func _session(principal: String, grants: Array) -> AuthenticatedCommandContext:
	return AuthenticatedCommandContext.from_authenticated_session(StringName(principal), &"terrain-test-session", _world.world_id, _world.region_id, PackedStringArray(grants))


func _clone(record: Dictionary) -> WorldRuntime:
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(clone.restore_world_snapshot_json(JSON.stringify(record)).is_success, "JSON clone restores")
	return clone


func _restart(record: Dictionary) -> void:
	var clone := _clone(record)
	_world.free()
	_bind(clone)
	_check(_world.start_simulation().is_success, "restored world starts")


func _reject_snapshot(record: Dictionary, message: String) -> void:
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	var before: Dictionary = clone.capture_world_snapshot().value.to_dictionary()
	_check(not clone.restore_world_snapshot_json(JSON.stringify(record)).is_success and clone.capture_world_snapshot().value.to_dictionary() == before, message)
	clone.free()


func _state() -> Dictionary:
	return _terrain.capture_snapshot().value


func _canonical() -> Dictionary:
	var record: Dictionary = _state()
	record.erase("last_tick")
	return record


func _mass() -> int:
	var owner: Dictionary = _state()["owner"]
	var mass: int = 0
	for cell in owner["cells"].values(): mass += int(cell["state"]["mass_milligrams"])
	for transfer in owner["transfers"].values(): mass += int(transfer["mass_milligrams"])
	return mass


func _next() -> int:
	return int(_state()["principals"].get(String(_context.principal_id), 0)) + 1


func _payload(cell: String, amount: int, transfer: String = "") -> Dictionary:
	return {"cell_id": cell, "amount_milligrams": amount, "transfer_id": transfer, "expected_cell_revision": _state()["owner"]["cells"][cell]["state"]["state_revision"],
		"expected_inventory_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"], "expected_tool_revision": _tools.capture_snapshot().value["ledger"]["state_revision"]}


func _deny(operation: String, payload: Dictionary, message: String) -> void:
	var before: Dictionary = _canonical()
	_send(operation, payload, _next())
	_check(not _last.is_success and _canonical() == before, message)


func _send(operation: String, payload: Dictionary, number: int) -> void:
	var command := TerrainCommand.new()
	command.command_id = StringName("terrain-client-%d" % number)
	command.request_number = number
	command.operation = operation
	command.payload = payload.duplicate(true)
	command.authenticated_context = _context
	_check(_world.enqueue_command(command).is_success, "terrain ingress queues")
	_step()


func _produce(operation: String, payload: Dictionary) -> void:
	_helper_id += 1
	var command := ProductionDevelopmentCommand.new()
	command.command_id = StringName("terrain-setup-%d" % _helper_id)
	command.authenticated_context = _context
	command.operation = operation
	payload["expected_revision"] = _production.capture_snapshot().value["state_revision"]
	command.payload = payload
	_check(_world.enqueue_command(command).is_success, "production setup queues")
	_step()
	_check(_last.is_success, "finite shovel setup: " + _last.message)


func _move(position: Array) -> void:
	_inventory_command("move_to", {"position_millimetres": position})


func _self(operation: String, item: String, source: String, slot: String) -> void:
	_inventory_command("self", {"operation": operation, "item_id": item, "source_container_id": source, "destination_container_id": "storage.backpack-2" if operation == "unequip" else "", "slot_id": slot, "expected_revision": _inventory.own_inventory_observation(_context, true).value["inventory_revision"]})


func _inventory_command(operation: String, payload: Dictionary) -> void:
	_helper_id += 1
	var command := InventoryDevelopmentCommand.new()
	command.command_id = StringName("terrain-inventory-%d" % _helper_id)
	command.authenticated_context = _context
	command.operation = operation
	command.payload = payload
	_check(_world.enqueue_command(command).is_success, "inventory setup queues")
	_step()
	_check(_last.is_success, "inventory setup: " + _last.message)


func _step() -> void:
	_runner._physics_process(1.0 / 60.0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
