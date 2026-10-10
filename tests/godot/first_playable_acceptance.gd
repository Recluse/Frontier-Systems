extends SceneTree

var _failures: int = 0
var _acks: Dictionary = {}
var _observations: Dictionary = {}
var _counter: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var directory: String = "user://acceptance-%d" % Time.get_ticks_usec()
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	var store := WorldPersistenceAdapter.new()
	root.add_child(store)
	_check(store.configure(world, directory).is_success, "new durable store initializes")
	var host := FirstPlayableHost.new()
	host.persistence = store
	root.add_child(host)
	var keys: Array[String] = ["acceptance-player-one-key-000000000000", "acceptance-player-two-key-000000000000"]
	_check(host.configure(world, keys, 27849).is_success and world.start_simulation().is_success, "shared host starts")
	var clients: Array[RemoteWorldRuntime] = []
	for slot in range(2):
		var client := RemoteWorldRuntime.new()
		root.add_child(client)
		client.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void: _acks[String(command.command_id)] = result)
		client.observation_received.connect(func(record: Dictionary) -> void: _observations[slot] = record)
		_check(client.connect_host("ws://127.0.0.1:27849", keys[slot]).is_success, "client connects")
		clients.append(client)
	await _wait(func() -> bool: return _observations.size() == 2, 5.0)
	if _observations.size() != 2:
		_check(false, "both authenticated clients receive scoped host observations")
		quit(1)
		return
	_check(_observations[0]["inventory"]["body_id"] != _observations[1]["inventory"]["body_id"], "invite slots bind separate bodies")
	var invalid := RemoteWorldRuntime.new()
	root.add_child(invalid)
	var rejected_auth: Dictionary = {}
	invalid.connection_closed.connect(func(_message: String) -> void: rejected_auth["closed"] = true)
	invalid.connect_host("ws://127.0.0.1:27849", "invalid-acceptance-key-0000000000000")
	await _wait(func() -> bool: return rejected_auth.has("closed"), 3.0)
	_check(rejected_auth.has("closed"), "invalid invite cannot obtain a player session")
	invalid.free()
	var pickup: Dictionary = {"operation": "pickup", "item_id": "resource-canister-2", "world_container_id": "world.tray-1", "destination_container_id": "body.human-1", "slot_id": "", "expected_revision": _observations[1]["world_items"]["inventory_revision"]}
	await _send(clients[1], "inventory", "world", pickup)
	await create_timer(0.25).timeout
	_check(_observations[1]["production"]["cargo"].has("resource-canister-2") and not _observations[0]["production"]["cargo"].has("resource-canister-2"), "payload observations remain identity scoped")
	await _walk_to(clients[0], 0, [-3000, 0, -1000])
	await _walk_to(clients[1], 1, [-3000, 0, -1000])
	await _reject(clients[0], 0, "production", "extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-2", "amount_milligrams": 1000})
	var revision: int = int(_observations[0]["production"]["state_revision"])
	var request_a: String = _queue(clients[0], "production", "extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000, "expected_revision": revision})
	var request_b: String = _queue(clients[1], "production", "extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-2", "amount_milligrams": 1000000, "expected_revision": revision})
	await _wait(func() -> bool: return _acks.has(request_a) and _acks.has(request_b), 3.0)
	_check(_acks.has(request_a) and _acks.has(request_b), "both competing requests receive acknowledgement")
	if not _acks.has(request_a) or not _acks.has(request_b):
		quit(1)
		return
	_check(_acks[request_a].is_success != _acks[request_b].is_success, "same-revision extraction produces exactly one winner")
	var winner: int = 0 if _acks[request_a].is_success else 1
	var carrier: String = "resource-canister-1" if winner == 0 else "resource-canister-2"
	await create_timer(0.25).timeout
	_check(_observations[0]["production"]["deposits"]["deposit.iron"] == 9000000, "race removes only one kilogram")
	await _production(clients[winner], winner, "extract", {"deposit_id": "deposit.iron", "carrier_id": carrier, "amount_milligrams": 1000000})
	await _reject(clients[winner], winner, "production", "extract", {"deposit_id": "deposit.iron", "carrier_id": carrier, "amount_milligrams": 1})
	await _walk_to(clients[winner], winner, [0, 0, 0])
	await _production(clients[winner], winner, "unload_cargo", {"carrier_id": carrier, "material": "ore.iron", "amount_milligrams": 2000000})
	await _reject(clients[winner], winner, "production", "process", {"recipe_id": "craft.plate"})
	await _production(clients[winner], winner, "power", {"station": "refinery", "enabled": false})
	await _reject(clients[winner], winner, "production", "process", {"recipe_id": "refine.iron"})
	await _production(clients[winner], winner, "power", {"station": "refinery", "enabled": true})
	await _production(clients[winner], winner, "process", {"recipe_id": "refine.iron"})
	await _production(clients[winner], winner, "power", {"station": "refinery", "enabled": false})
	await create_timer(0.25).timeout
	var remaining: int = int(_observations[winner]["production"]["job"]["remaining_ticks"])
	await create_timer(0.4).timeout
	_check(int(_observations[winner]["production"]["job"]["remaining_ticks"]) == remaining, "power outage pauses reserved work without consuming progress")
	await _production(clients[winner], winner, "cancel", {})
	await create_timer(0.25).timeout
	_check(_observations[winner]["production"]["job"].is_empty() and _observations[winner]["production"]["store"]["ore.iron"] == 2000000, "cancel returns reserved inputs without losing or duplicating material")
	await _production(clients[winner], winner, "power", {"station": "refinery", "enabled": true})
	for _batch in range(2):
		await _production(clients[winner], winner, "process", {"recipe_id": "refine.iron"})
		await _wait(func() -> bool: return _observations[winner]["production"]["job"].is_empty(), 4.0)
	await _production(clients[winner], winner, "process", {"recipe_id": "craft.plate"})
	await _wait(func() -> bool: return _observations[winner]["production"]["job"].is_empty(), 4.0)
	await _production(clients[winner], winner, "materialize_plate", {})
	await create_timer(0.25).timeout
	_check(_observations[winner]["production"]["components"].size() == 1, "printed matter becomes one physical inventory component")
	if _observations[winner]["production"]["components"].is_empty():
		quit(1)
		return
	var plate: String = _observations[winner]["production"]["components"][0]
	var component_save: ServiceResult = world.capture_world_snapshot_json()
	var component_restore := WorldRuntime.new()
	component_restore.resource_carriers_enabled = true
	root.add_child(component_restore)
	_check(component_save.is_success and component_restore.restore_world_snapshot_json(component_save.value).is_success, "a live physical component restores with its payload and inventory association")
	var restored_production := component_restore.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem
	_check(restored_production.payload_mass(plate) == 1000000, "restored physical plate retains its loaded mass")
	component_restore.free()
	await _production(clients[winner], winner, "recycle_component", {"item_id": plate})
	await create_timer(0.25).timeout
	_check(_observations[winner]["production"]["components"].is_empty() and _observations[winner]["production"]["store"]["iron"] == 1200000, "physical recycling returns conserved iron without duplicating the plate")
	# Cooperative deployed machinery uses the same remote authority and durable store.
	var machine_parts: Array[String] = []
	for kind in ["frame", "controller", "power", "solar"]:
		await _production(clients[winner], winner, "machine_craft", {"kind": kind})
		await create_timer(0.25).timeout
		for id in _observations[winner]["production"]["machinery"]["parts"]:
			if not machine_parts.has(id): machine_parts.append(id)
	var shared_machine: String = machine_parts[0]
	_check(not _observations[1 - winner]["production"]["machinery"]["parts"].has(shared_machine), "packed machines stay private to their owner")
	await _reject(clients[1 - winner], 1 - winner, "production", "machine_recycle", {"item_id": shared_machine})
	for part in machine_parts.slice(1):
		await _production(clients[winner], winner, "machine_fit", {"machine_id": shared_machine, "item_id": part, "socket_id": ""})
	await _production(clients[winner], winner, "machine_deploy", {"machine_id": shared_machine, "position": [0, 0, 0], "mode": "surface"})
	await create_timer(0.25).timeout
	_check(_observations[1 - winner]["production"]["machinery"]["placements"].has(shared_machine), "deployed generator replicates to both crew")
	await _walk_to(clients[1 - winner], 1 - winner, [0, 0, 0])
	await _production(clients[1 - winner], 1 - winner, "machine_enable", {"machine_id": shared_machine, "enabled": false})
	await _production(clients[1 - winner], 1 - winner, "machine_enable", {"machine_id": shared_machine, "enabled": true})
	await _wait(func() -> bool: return not store.status()["busy"], 3.0)
	await _send(clients[1 - winner], "world", "checkpoint", {})
	var machinery_save: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	var machinery_restore := WorldRuntime.new()
	machinery_restore.resource_carriers_enabled = true
	root.add_child(machinery_restore)
	_check(machinery_save.is_success and machinery_restore.restore_world_snapshot_json(machinery_save.value["snapshot_json"]).is_success, "disk checkpoint restores a cooperative generator assembly")
	_check((machinery_restore.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem).capture_snapshot().value["machinery"]["placements"].has(shared_machine), "restored generator retains deployed identity")
	machinery_restore.free()
	await _production(clients[winner], winner, "machine_pack", {"machine_id": shared_machine})
	for part in machine_parts.slice(1):
		await _production(clients[winner], winner, "machine_unfit", {"machine_id": shared_machine, "item_id": part, "socket_id": ""})
		await _production(clients[winner], winner, "machine_recycle", {"item_id": part})
	await _production(clients[winner], winner, "machine_recycle", {"item_id": shared_machine})
	await _production(clients[winner], winner, "fabricate_equipment", {"blueprint_id": "equipment.canister"})
	await create_timer(0.25).timeout
	var fabricated: String = _observations[winner]["production"]["structures"].keys()[0]
	_check(_observations[winner]["production"]["cargo"].has(fabricated) and not _observations[1 - winner]["production"]["structures"].has(fabricated), "fabricated carrier is usable and its structural record is private")
	await _production(clients[winner], winner, "load_cargo", {"carrier_id": fabricated, "material": "iron", "amount_milligrams": 100000})
	await create_timer(0.25).timeout
	_check((world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem).payload_mass(fabricated) == 1100000, "fabricated shell and contents are counted exactly once")
	await _walk_to(clients[1 - winner], 1 - winner, [0, 0, 0])
	await _reject(clients[1 - winner], 1 - winner, "production", "salvage_equipment", {"item_id": fabricated})
	await _inventory_transfer(clients[winner], winner, "drop", fabricated)
	await _inventory_transfer(clients[1 - winner], 1 - winner, "pickup", fabricated)
	await _wait(func() -> bool: return not store.status()["busy"], 3.0)
	await _send(clients[1 - winner], "world", "checkpoint", {})
	var equipment_save: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	var equipment_restore := WorldRuntime.new()
	equipment_restore.resource_carriers_enabled = true
	root.add_child(equipment_restore)
	_check(equipment_save.is_success and equipment_restore.restore_world_snapshot_json(equipment_save.value["snapshot_json"]).is_success, "disk checkpoint restores transferred loaded fabricated equipment")
	_check((equipment_restore.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem).payload_mass(fabricated) == 1100000, "restored fabricated equipment retains shell and contents")
	equipment_restore.free()
	await _production(clients[1 - winner], 1 - winner, "salvage_equipment", {"item_id": fabricated})
	await create_timer(0.25).timeout
	_check(_observations[winner]["production"]["store"]["iron"] == 1200000 and _observations[1 - winner]["production"]["structures"].is_empty(), "new owner salvages shell and contents without material loss")
	await _production(clients[winner], winner, "fabricate_tool_part", {"blueprint_id": "part.head.space", "expected_tool_revision": _observations[winner]["tools"]["state_revision"]})
	await create_timer(0.25).timeout
	var physical_part: String = _observations[winner]["tools"]["loose_parts"][0]["part_id"]
	_check(_observations[1 - winner]["tools"]["loose_parts"].is_empty(), "physical component observations are private")
	await _reject(clients[1 - winner], 1 - winner, "production", "recycle_tool_part", {"part_id": physical_part, "expected_tool_revision": _observations[1 - winner]["tools"]["state_revision"]})
	await _inventory_transfer(clients[winner], winner, "drop", physical_part)
	await _inventory_transfer(clients[1 - winner], 1 - winner, "pickup", physical_part)
	await _wait(func() -> bool: return not store.status()["busy"], 3.0)
	await _send(clients[1 - winner], "world", "checkpoint", {})
	var part_save: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	var part_restore := WorldRuntime.new()
	part_restore.resource_carriers_enabled = true
	root.add_child(part_restore)
	_check(part_save.is_success and part_restore.restore_world_snapshot_json(part_save.value["snapshot_json"]).is_success, "disk checkpoint restores transferred independent tool part")
	_check((part_restore.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem).payload_mass(physical_part) == 900000, "restored physical part has its exact conserved mass")
	part_restore.free()
	await _production(clients[1 - winner], 1 - winner, "recycle_tool_part", {"part_id": physical_part, "expected_tool_revision": _observations[1 - winner]["tools"]["state_revision"]})
	await create_timer(0.25).timeout
	_check(_observations[winner]["production"]["store"]["iron"] == 1200000 and _observations[1 - winner]["tools"]["loose_parts"].is_empty(), "new owner recycles transferred part without matter loss")
	await _production(clients[winner], winner, "process", {"recipe_id": "craft.plate"})
	await _wait(func() -> bool: return not store.status()["busy"], 3.0)
	await _send(clients[winner], "world", "checkpoint", {})
	await _wait(func() -> bool: return not store.status()["busy"], 3.0)
	_check(store.status()["saved_tick"] >= 0, "worker checkpoint commits to disk")
	var latest: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	_check(latest.is_success and not latest.value.is_empty(), "durable checkpoint reloads")
	var corrupt_slot: String = "a" if (int(latest.value["sequence"]) + 1) % 2 == 0 else "b"
	var corrupt := FileAccess.open(directory.path_join("world-%s.json" % corrupt_slot), FileAccess.WRITE)
	corrupt.store_string("interrupted checkpoint")
	corrupt.close()
	_check(LocalWorldSaveStore.read_latest(directory).value["sequence"] == latest.value["sequence"], "an interrupted alternate slot preserves the valid checkpoint")
	var restarted := WorldRuntime.new()
	restarted.resource_carriers_enabled = true
	root.add_child(restarted)
	var restored: ServiceResult = restarted.restore_world_snapshot_json(latest.value["snapshot_json"])
	_check(restored.is_success, "whole world restores: " + restored.message)
	_check(restored.is_success and restarted.start_simulation().is_success, "restored world restarts")
	var production := restarted.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem
	_check(production.capture_snapshot().value["deposits"]["deposit.iron"] == 8000000 and not production.capture_snapshot().value["job"].is_empty(), "restart preserves depletion and remaining batch work")
	await _wait(func() -> bool: return production.capture_snapshot().value["job"].is_empty(), 4.0)
	_check(production.capture_snapshot().value["store"]["plate"] == 1000000, "restarted batch completes once")
	for client in clients:
		client.free()
	host.free()
	store.free()
	world.free()
	var restarted_host := FirstPlayableHost.new()
	root.add_child(restarted_host)
	_check(restarted_host.configure(restarted, keys, 27849).is_success, "restarted host opens the same endpoint")
	var reconnected := RemoteWorldRuntime.new()
	root.add_child(reconnected)
	var reconnect_state: Dictionary = {}
	reconnected.observation_received.connect(func(record: Dictionary) -> void: reconnect_state["record"] = record)
	reconnected.observation_received.connect(func(record: Dictionary) -> void: _observations[winner] = record)
	reconnected.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void: _acks[String(command.command_id)] = result)
	_check(reconnected.connect_host("ws://127.0.0.1:27849", keys[winner]).is_success, "persistent invite reconnects to restarted host")
	await _wait(func() -> bool: return reconnect_state.has("record"), 4.0)
	_check(reconnect_state.has("record") and reconnect_state["record"]["production"]["deposits"]["deposit.iron"] == 8000000 and reconnect_state["record"]["production"]["store"]["plate"] == 1000000, "reconnected client sees durable depletion and exactly one recovered output")
	await _walk_to(reconnected, winner, [-3000, 0, -1000])
	var original_id: String = request_a if winner == 0 else request_b
	_acks.erase(original_id)
	var retry := ProductionDevelopmentCommand.new()
	retry.command_id = StringName(original_id)
	retry.operation = "extract"
	retry.payload = {"deposit_id": "deposit.iron", "carrier_id": carrier, "amount_milligrams": 1000000, "expected_revision": revision}
	_check(reconnected.enqueue_command(retry).is_success, "retained request can be retried after reconnect")
	await _wait(func() -> bool: return _acks.has(original_id), 3.0)
	_check(_acks.has(original_id) and _acks[original_id].is_success and production.capture_snapshot().value["deposits"]["deposit.iron"] == 8000000, "durable retry receipt prevents repeated extraction after restart")
	reconnected.free()
	restarted_host.free()
	restarted.free()
	if _failures == 0:
		print("FIRST PLAYABLE ACCEPTANCE: two authenticated clients, scoped cargo, competing extraction, refinement, physical crafting/recycling, shared generator control, assembly checkpoint and restarted batch passed.")
	quit(0 if _failures == 0 else 1)


func _production(client: RemoteWorldRuntime, slot: int, operation: String, payload: Dictionary) -> void:
	await create_timer(0.2).timeout
	payload["expected_revision"] = _observations[slot]["production"]["state_revision"]
	await _send(client, "production", operation, payload)
	if operation == "process":
		await _wait(func() -> bool: return not _observations[slot]["production"]["job"].is_empty(), 1.0)


func _inventory_transfer(client: RemoteWorldRuntime, slot: int, operation: String, item: String) -> void:
	await create_timer(0.25).timeout
	await _send(client, "inventory", "world", {"operation": operation, "item_id": item, "world_container_id": "world.tray-1", "destination_container_id": _observations[slot]["inventory"]["body_container_id"] if operation == "pickup" else "", "slot_id": "", "expected_revision": _observations[slot]["inventory"]["inventory_revision"]})
	await create_timer(0.25).timeout


func _walk_to(client: RemoteWorldRuntime, slot: int, target: Array) -> void:
	while _observations[slot]["position"] != target:
		var current: Array = _observations[slot]["position"]
		var from := Vector3(float(current[0]), float(current[1]), float(current[2]))
		var to := Vector3(float(target[0]), float(target[1]), float(target[2]))
		var next: Vector3 = from + (to - from).limit_length(750.0)
		var position: Array = [roundi(next.x), roundi(next.y), roundi(next.z)]
		await create_timer(0.2).timeout
		await _send(client, "inventory", "move_to", {"position_millimetres": position})
		await _wait(func() -> bool: return _observations[slot]["position"] == position, 2.0)
		if _observations[slot]["position"] != position:
			_check(false, "bounded player movement must replicate")
			return


func _queue(client: RemoteWorldRuntime, system: String, operation: String, payload: Dictionary) -> String:
	_counter += 1
	var command: SimulationCommand = ProductionDevelopmentCommand.new() if system == "production" else (InventoryDevelopmentCommand.new() if system == "inventory" else CheckpointRequest.new())
	command.command_id = StringName("acceptance-%d" % _counter)
	command.operation = operation
	command.payload = payload
	_check(client.enqueue_command(command).is_success, "client request queues")
	return String(command.command_id)


func _send(client: RemoteWorldRuntime, system: String, operation: String, payload: Dictionary) -> void:
	var id: String = _queue(client, system, operation, payload)
	await _wait(func() -> bool: return _acks.has(id), 3.0)
	_check(_acks.has(id) and _acks[id].is_success, "host applies " + operation + (": " + _acks[id].message if _acks.has(id) else " (no acknowledgement)"))


func _reject(client: RemoteWorldRuntime, slot: int, system: String, operation: String, payload: Dictionary) -> void:
	await create_timer(0.2).timeout
	if system == "production":
		payload["expected_revision"] = _observations[slot]["production"]["state_revision"]
	var id: String = _queue(client, system, operation, payload)
	await _wait(func() -> bool: return _acks.has(id), 3.0)
	_check(_acks.has(id) and not _acks[id].is_success, "host rejects unauthorized or overcapacity " + operation)


func _wait(predicate: Callable, seconds: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
