extends SceneTree

const PORT: int = 27853
var _world: WorldRuntime
var _runner: SimulationRunner
var _host: FirstPlayableHost
var _clients: Array[RemoteWorldRuntime] = []
var _views: Dictionary = {}
var _acks: Dictionary = {}
var _counter: int = 0
var _failures: int = 0
var _directory: String
var _keys: Array[String] = ["terrain-peer-one-00000000000000000000", "terrain-peer-two-00000000000000000000"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_directory = "user://terrain-cooperative-%d" % Time.get_ticks_usec()
	_world = WorldRuntime.new()
	_world.resource_carriers_enabled = true
	root.add_child(_world)
	var store := WorldPersistenceAdapter.new()
	root.add_child(store)
	_check(store.configure(_world, _directory.path_join("host")).is_success, "temporary host storage configures")
	_start_host(store)
	var diagnostic: Dictionary = _world.terrain_observation(_host._context(0)).value
	_check(TerrainObservationValidation.valid(diagnostic) and TerrainObservationValidation.valid(JSON.parse_string(JSON.stringify(diagnostic))), "native and JSON host projection validate")
	await _connect_clients()
	if _views.size() != 2: quit(1); return
	_check(_views[0]["terrain"]["transfers"].is_empty() and _views[1]["terrain"]["next_request_number"] == 1, "authenticated peers receive bounded fresh scoped terrain")
	var forged := _terrain(0, "excavate", "terrain.dirt.source", 1)
	forged.payload["context"] = {"principal_id": "forged", "permissions": ["terrain.operate"]}
	_check(not _clients[0].enqueue_command(forged).is_success and _clients[0].terrain_pending_intent().is_empty(), "client-supplied context never crosses the terrain adapter")
	var original: Dictionary = _views[0]["terrain"].duplicate(true)
	_check(TerrainObservationValidation.valid(JSON.parse_string(JSON.stringify(original))), "JSON terrain projection validates")
	for mutation in range(6):
		var invalid: Dictionary = original.duplicate(true)
		match mutation:
			0: invalid["cells"]["terrain.dirt.source"]["position_millimetres"][0] = 9999
			1: invalid["cells"]["terrain.dirt.source"]["state"]["mass_milligrams"] = 2000001
			2: invalid["next_request_number"] = 1.5
			3: invalid["principal_id"] = "forged"
			4: invalid["cells"]["terrain.dirt.source"]["work_message"] = "x".repeat(513)
			5: invalid["transfers"] = {"terrain-transfer-1": {"material_id": "material.dirt", "material_revision": 1, "mass_milligrams": 1, "parcels": {"unknown": 1}}}
		_check(not TerrainObservationValidation.valid(invalid), "malformed projection rejects %d" % mutation)
	# Actual remote fabrication uses the finite production fixture for each crew.
	for slot in range(2):
		if slot == 1:
			var pickup := InventoryDevelopmentCommand.new()
			pickup.operation = "world"
			pickup.payload = {"operation": "pickup", "item_id": "resource-canister-2", "world_container_id": "world.tray-1", "destination_container_id": _views[slot]["inventory"]["body_container_id"], "slot_id": "", "expected_revision": _views[slot]["inventory"]["inventory_revision"]}
			await _send(slot, pickup)
		for _batch in range(3):
			await _walk(slot, [-3000, 0, -1000])
			await _production(slot, "extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-%d" % (slot + 1), "amount_milligrams": 1000000})
			await _walk(slot, [0, 0, 0])
			await _production(slot, "unload_cargo", {"carrier_id": "resource-canister-%d" % (slot + 1), "material": "ore.iron", "amount_milligrams": 1000000})
			await _production(slot, "process", {"recipe_id": "refine.iron"})
			for _tick in range(120): _step()
			await create_timer(0.13).timeout
		await _production(slot, "fabricate_equipment", {"blueprint_id": "equipment.shovel"})
		if _views[slot]["production"]["structures"].is_empty():
			_check(false, "finite shovel must exist before equipment tests")
			quit(1)
			return
		var shovel: String = _views[slot]["production"]["structures"].keys()[0]
		await _self(slot, "equip", shovel, _views[slot]["inventory"]["body_container_id"], "hand.left")
		await _self(slot, "select_hand", "", "", "hand.left")
	_check(_views[0]["terrain"]["cells"]["terrain.dirt.source"]["work_ready"] and _views[1]["terrain"]["cells"]["terrain.dirt.source"]["work_ready"], "both crews hold actual finite-material operational shovels")
	var first := _terrain(0, "excavate", "terrain.dirt.source", 500000)
	var other := _terrain(1, "excavate", "terrain.dirt.source", 500000)
	_check(first.command_id == other.command_id, "both peers deliberately submit terrain-client-1")
	_check(_clients[0].enqueue_command(first).is_success and _clients[1].enqueue_command(other).is_success, "same ordinal peer intents queue")
	await _wait(func() -> bool: return _acks.has("0:terrain-client-1") and _acks.has("1:terrain-client-1"), 3.0)
	_check(_acks.has("0:terrain-client-1") and _acks.has("1:terrain-client-1") and _acks["0:terrain-client-1"].is_success != _acks["1:terrain-client-1"].is_success, "two correlated acknowledgements reach their own peers; one stale cell rejects")
	await create_timer(0.13).timeout
	var loser: int = 1 if _acks["0:terrain-client-1"].is_success else 0
	await _terrain_send(loser, _terrain(loser, "excavate", "terrain.dirt.source", 500000), true)
	_check(_views[0]["terrain"]["transfers"].size() == 1 and _views[1]["terrain"]["transfers"].size() == 1 and _views[0]["terrain"]["transfers"].keys()[0] != _views[1]["terrain"]["transfers"].keys()[0], "own escrow is scoped to each principal")
	var foreign: String = _views[1]["terrain"]["transfers"].keys()[0]
	await _terrain_send(0, _terrain(0, "fill", "terrain.dirt.fill", 1, foreign), false)
	var stale := _terrain(0, "excavate", "terrain.dirt.source", 1)
	stale.payload["expected_cell_revision"] += 1
	await _terrain_send(0, stale, false)
	stale = _terrain(0, "excavate", "terrain.dirt.source", 1)
	stale.payload["expected_inventory_revision"] += 1
	await _terrain_send(0, stale, false)
	stale = _terrain(0, "excavate", "terrain.dirt.source", 1)
	stale.payload["expected_tool_revision"] += 1
	await _terrain_send(0, stale, false)
	await _walk(0, [4000, 0, 0])
	await _terrain_send(0, _terrain(0, "excavate", "terrain.dirt.source", 1), false)
	await _walk(0, [0, 0, 0])
	await _self(0, "select_hand", "", "", "hand.right")
	await _terrain_send(0, _terrain(0, "excavate", "terrain.dirt.source", 1), false)
	await _self(0, "select_hand", "", "", "hand.left")
	var health := _world.get_simulation_system(HealthSimulationSystem.SYSTEM_ID) as HealthSimulationSystem
	var body: String = _views[0]["inventory"]["body_id"]
	_check(health.queue_observation(body, JSON.parse_string(FileAccess.get_file_as_string("res://data/health/suppression.combined.v1.json")), 0, _world.current_tick_number() + 1).is_success, "injected trusted unconsciousness queues")
	for _tick in range(6): _step()
	await _terrain_send(0, _terrain(0, "excavate", "terrain.dirt.source", 1), false)
	_check(health.queue_observation(body, [], 1, _world.current_tick_number() + 1).is_success, "trusted consciousness recovery queues")
	for _tick in range(72): _step()
	await create_timer(0.13).timeout
	_check(_views[0]["terrain"]["cells"]["terrain.dirt.source"]["work_ready"], "health recovery hysteresis completes before fresh work")
	# Lose the acknowledgement after a real host commit, then restart both ends.
	var uncertain := _terrain(0, "excavate", "terrain.dirt.source", 500000)
	var ack_key: String = "0:" + String(uncertain.command_id)
	_acks.erase(ack_key)
	_check(_clients[0].enqueue_command(uncertain).is_success, "uncertain request journals before sending")
	var retained: Dictionary = _clients[0].terrain_pending_intent()
	var invalid_journal := FileAccess.open(_directory.path_join("oversized.json"), FileAccess.WRITE)
	invalid_journal.store_string("x".repeat(LocalTerrainRetryStore.MAX_BYTES + 1))
	invalid_journal.close()
	_check(not LocalTerrainRetryStore.read_intent(_directory.path_join("oversized.json")).is_success, "oversized client journal fails closed")
	var fixture := FileAccess.open("res://var/terrain-controls-fixture.json", FileAccess.WRITE)
	fixture.store_string(JSON.stringify({"observation": _views[0]["terrain"], "intent": retained}))
	fixture.close()
	uncertain.payload["amount_milligrams"] = 123 # Caller mutation cannot alter journal/wire.
	await _wait(func() -> bool: return not _host._pending.is_empty(), 3.0, false)
	_check(not _host._pending.is_empty(), "host pending route exists before commit")
	_step()
	_check(_host._events.size() == 1 and _host._events[0]["frame"]["ok"], "lost acknowledgement follows a successful terrain commit: " + str(_host._events))
	_host._events.clear() # Inject a lost outbound acknowledgement, no live service.
	var terrain_before: Dictionary = (_world.get_simulation_system(TerrainSimulationSystem.SYSTEM_ID) as TerrainSimulationSystem).capture_snapshot().value
	_check(terrain_before["owner"]["cells"]["terrain.dirt.source"]["state"]["mass_milligrams"] == 500000, "original immutable payload commits once")
	await _wait(func() -> bool: return not store.status()["busy"], 3.0, false)
	var checkpoint: ServiceResult = store.request_checkpoint()
	_check(checkpoint.is_success, "temporary disk checkpoint requests: " + checkpoint.message)
	await _wait(func() -> bool: return not store.status()["busy"], 3.0)
	var saved: ServiceResult = LocalWorldSaveStore.read_latest(_directory.path_join("host"))
	_check(saved.is_success, "temporary checkpoint reaches disk")
	_host.free()
	await _wait(func() -> bool: return _clients[0]._requests.is_empty() and _clients[1]._requests.is_empty(), 3.0)
	_check(_clients[0].terrain_pending_intent() == retained and _clients[0]._terrain_record.is_empty(), "disconnect clears projections/pending transport and preserves original intent")
	for client in _clients: client.free()
	_clients.clear()
	_views.clear()
	store.free()
	_world.free()
	_world = WorldRuntime.new()
	_world.resource_carriers_enabled = true
	root.add_child(_world)
	_check(_world.restore_world_snapshot_json(saved.value["snapshot_json"]).is_success, "actual world checkpoint restores")
	_start_host(null)
	await _connect_clients()
	_check(_clients[0].terrain_pending_intent() == retained and _views[0]["terrain"]["next_request_number"] == 3, "restarted client loads original ordinal 2 while fresh observation says 3")
	_acks.erase(ack_key)
	_check(_clients[0].retry_terrain_intent().is_success, "original retry queues after both-end restart")
	await _wait(func() -> bool: return _acks.has(ack_key), 3.0)
	await create_timer(0.13).timeout
	_check(_acks.has(ack_key) and _acks[ack_key].is_success and _clients[0].terrain_pending_intent().is_empty() and (_world.get_simulation_system(TerrainSimulationSystem.SYSTEM_ID) as TerrainSimulationSystem).capture_snapshot().value["owner"] == terrain_before["owner"], "restart retry reconciles without repeated matter")
	await _terrain_send(1, _terrain(1, "excavate", "terrain.dirt.source", 500000), true)
	await _terrain_send(0, _terrain(0, "excavate", "terrain.dirt.source", 1), false)
	for slot in range(2):
		var ids: Array = _views[slot]["terrain"]["transfers"].keys()
		for id in ids: await _terrain_send(slot, _terrain(slot, "fill", "terrain.dirt.fill", 500000, id), true)
	_check(_views[0]["terrain"]["cells"]["terrain.dirt.source"]["state"]["mass_milligrams"] == 0 and _views[0]["terrain"]["cells"]["terrain.dirt.fill"]["state"]["mass_milligrams"] == 2000000 and _views[0]["terrain"]["transfers"].is_empty() and _views[1]["terrain"]["transfers"].is_empty(), "finite source depletion and full scoped escrow fill conserve 2 kg")
	# Disconnect while queued: abandoned route cannot be delivered to a new session.
	_check(_clients[0].enqueue_command(_terrain(0, "excavate", "terrain.dirt.fill", 1)).is_success, "disconnect fixture queues")
	await _wait(func() -> bool: return not _host._pending.is_empty(), 3.0, false)
	_clients[0]._socket.close(-1)
	await _wait(func() -> bool: return _host._peers.size() == 1, 3.0, false)
	_check(_host._pending.is_empty(), "host disconnect removes pending routes")
	_step()
	_check(_host._events.is_empty(), "abandoned completion cannot leak to another peer")
	var settled: Dictionary = (_world.get_simulation_system(TerrainSimulationSystem.SYSTEM_ID) as TerrainSimulationSystem).capture_snapshot().value["owner"]
	_views.erase(0)
	_check(_clients[0].connect_host("ws://127.0.0.1:%d" % PORT, _keys[0]).is_success, "same client adapter reconnects")
	await _wait(func() -> bool: return _views.has(0), 3.0)
	var reconnect_key: String = "0:terrain-client-%d" % int(_clients[0].terrain_pending_intent()["request_number"])
	_acks.erase(reconnect_key)
	_check(_clients[0].retry_terrain_intent().is_success, "new authenticated session retries abandoned original intent")
	await _wait(func() -> bool: return _acks.has(reconnect_key), 3.0)
	_check(_acks.has(reconnect_key) and _acks[reconnect_key].is_success and (_world.get_simulation_system(TerrainSimulationSystem.SYSTEM_ID) as TerrainSimulationSystem).capture_snapshot().value["owner"] == settled, "same-client reconnect reconciles without repeating matter")
	var invalid_frame: Dictionary = _views[1].duplicate(true)
	invalid_frame["terrain"]["cells"]["terrain.dirt.fill"]["position_millimetres"][0] += 1
	_clients[1]._receive(invalid_frame)
	await _wait(func() -> bool: return _clients[1]._terrain_record.is_empty(), 3.0)
	_check(_clients[1]._terrain_record.is_empty(), "actual client closes and clears malformed host projection")
	for client in _clients: client.free()
	_host.free()
	_world.free()
	_cleanup(ProjectSettings.globalize_path(_directory))
	if _failures == 0: print("TERRAIN COOPERATIVE: real two-peer finite shovel construction, same-ordinal routing, scoped escrow, rejection gates, disk/reconnect retry, depletion/fill and malformed/disconnect cleanup passed.")
	quit(0 if _failures == 0 else 1)


func _start_host(store: WorldPersistenceAdapter) -> void:
	_host = FirstPlayableHost.new()
	_host.persistence = store
	root.add_child(_host)
	_check(_host.configure(_world, _keys, PORT).is_success and _world.start_simulation().is_success, "dedicated loopback host starts")
	_runner = _world.get_node("SimulationRunner") as SimulationRunner
	_runner.set_physics_process(false) # Accelerated deterministic ticks, real TCP adapter.


func _connect_clients() -> void:
	for slot in range(2):
		var client := RemoteWorldRuntime.new()
		client.terrain_retry_directory = _directory.path_join("client-%d" % slot)
		root.add_child(client)
		client.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void: _acks["%d:%s" % [slot, command.command_id]] = result)
		client.observation_received.connect(func(record: Dictionary) -> void: _views[slot] = record)
		_check(client.connect_host("ws://127.0.0.1:%d" % PORT, _keys[slot]).is_success, "authenticated client connects")
		_clients.append(client)
	await _wait(func() -> bool: return _views.size() == 2, 5.0)
	_check(_views.size() == 2, "two authenticated observations arrive")


func _terrain(slot: int, operation: String, cell: String, amount: int, transfer: String = "") -> TerrainCommand:
	var command := TerrainCommand.new()
	command.request_number = int(_views[slot]["terrain"]["next_request_number"])
	command.command_id = StringName("terrain-client-%d" % command.request_number)
	command.operation = operation
	command.payload = {"cell_id": cell, "expected_cell_revision": _views[slot]["terrain"]["cells"][cell]["state"]["state_revision"], "amount_milligrams": amount, "transfer_id": transfer, "expected_inventory_revision": _views[slot]["inventory"]["inventory_revision"], "expected_tool_revision": _views[slot]["tools"]["state_revision"]}
	return command


func _terrain_send(slot: int, command: TerrainCommand, success: bool) -> void:
	var key: String = "%d:%s" % [slot, command.command_id]
	_acks.erase(key)
	_check(_clients[slot].enqueue_command(command).is_success, "terrain transport queues " + command.operation)
	await _wait(func() -> bool: return _acks.has(key), 3.0)
	_check(_acks.has(key) and _acks[key].is_success == success, "terrain host expected outcome " + command.operation + (": " + _acks[key].message if _acks.has(key) else " missing ack"))
	await create_timer(0.13).timeout


func _send(slot: int, command: SimulationCommand) -> void:
	_counter += 1
	command.command_id = StringName("terrain-setup-%d" % _counter)
	var key: String = "%d:%s" % [slot, command.command_id]
	_check(_clients[slot].enqueue_command(command).is_success, "setup transport queues")
	await _wait(func() -> bool: return _acks.has(key), 3.0)
	_check(_acks.has(key) and _acks[key].is_success, "setup host applies " + command.operation + (": " + _acks[key].message if _acks.has(key) else " missing ack"))
	await create_timer(0.13).timeout


func _production(slot: int, operation: String, payload: Dictionary) -> void:
	var command := ProductionDevelopmentCommand.new()
	command.operation = operation
	command.payload = payload
	command.payload["expected_revision"] = _views[slot]["production"]["state_revision"]
	await _send(slot, command)


func _self(slot: int, operation: String, item: String, source: String, hand: String) -> void:
	var command := InventoryDevelopmentCommand.new()
	command.operation = "self"
	command.payload = {"operation": operation, "item_id": item, "source_container_id": source, "destination_container_id": "", "slot_id": hand, "expected_revision": _views[slot]["inventory"]["inventory_revision"]}
	await _send(slot, command)


func _walk(slot: int, target: Array) -> void:
	await create_timer(0.12).timeout
	for _attempt in range(20):
		var current: Array = _views[slot]["position"]
		if current == target: return
		var from := Vector3(current[0], current[1], current[2])
		var next: Vector3 = from + (Vector3(target[0], target[1], target[2]) - from).limit_length(750)
		var command := InventoryDevelopmentCommand.new()
		command.operation = "move_to"
		command.payload = {"position_millimetres": [roundi(next.x), roundi(next.y), roundi(next.z)]}
		await _send(slot, command)
	_check(false, "bounded movement reaches terrain fixture")


func _wait(predicate: Callable, seconds: float, advance: bool = true) -> void:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		if advance: _step()
		await process_frame


func _step() -> void:
	_runner._physics_process(1.0 / 60.0)


func _cleanup(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null: return
	for file in directory.get_files(): DirAccess.remove_absolute(path.path_join(file))
	for child in directory.get_directories(): _cleanup(path.path_join(child))
	DirAccess.remove_absolute(path)


func _check(condition: bool, message: String) -> void:
	if condition: return
	_failures += 1
	push_error(message)
