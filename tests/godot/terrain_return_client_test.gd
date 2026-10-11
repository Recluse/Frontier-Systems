extends SceneTree

const PORT: int = 19243
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
	_directory = "user://terrain-return-client-%d" % Time.get_ticks_usec()
	_world = WorldRuntime.new()
	_world.resource_carriers_enabled = true
	root.add_child(_world)
	var store := WorldPersistenceAdapter.new()
	root.add_child(store)
	_check(store.configure(_world, _directory.path_join("host")).is_success, "temporary host storage configures")
	_start_host(store)
	await _connect_clients()
	if _views.size() != 2: quit(1); return
	# Both real crews fabricate shovels from finite matter; no synthetic grants.
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
		var shovel: String = _views[slot]["production"]["structures"].keys()[0]
		await _self(slot, "equip", shovel, _views[slot]["inventory"]["body_container_id"], "hand.left")
		await _self(slot, "select_hand", "", "", "hand.left")
	await _terrain_send(0, _terrain(0, "excavate", "terrain.dirt.source", 777777), true)
	var original_claim: SimulationCommand = _claim(0, "terrain-transfer-1")
	await _claim_send(0, original_claim, true)
	_check(_views[0]["terrain"]["returnable_parcels"].has("terrain-item-1") and _views[1]["terrain"]["returnable_parcels"].is_empty(), "returnable parcel projection is holder-scoped")
	var before: Dictionary = _canonical(_world)
	await _claim_send(1, _return_command(1, "terrain-item-1"), false)
	_check(_canonical(_world) == before, "foreign wire return leaves both owners unchanged")
	var stale: SimulationCommand = _return_command(0, "terrain-item-1")
	stale.payload["expected_inventory_revision"] += 1
	await _claim_send(0, stale, false)
	_check(_canonical(_world) == before, "stale wire return leaves both owners unchanged")
	for field in ["mass_milligrams", "material_id", "principal_id", "parcels", "transfer_id", "destination_container_id"]:
		var forged: SimulationCommand = _return_command(0, "terrain-item-1")
		forged.payload[field] = "forged"
		_check(not _clients[0].enqueue_command(forged).is_success and _clients[0].terrain_pending_intent().is_empty(), "client rejects injected return field " + field)
		_clients[0]._requests["terrain-return-1"] = forged
		_acks.erase("0:terrain-return-1")
		_clients[0]._socket.send_text(JSON.stringify({"type": "command", "system": "terrain", "operation": "return", "request_id": "terrain-return-1", "request_number": 1, "payload": forged.payload}))
		await _wait(func() -> bool: return _acks.has("0:terrain-return-1"), 3.0)
		_check(_acks.has("0:terrain-return-1") and not _acks["0:terrain-return-1"].is_success and _canonical(_world) == before, "host rejects injected return field " + field)
		await create_timer(0.13).timeout
	# Transfer the stable physical identity through normal drop/pickup commands.
	await _world_move(0, "drop", "terrain-item-1", "")
	await _world_move(1, "pickup", "terrain-item-1", _views[1]["inventory"]["body_container_id"])
	_check(_views[0]["terrain"]["returnable_parcels"].is_empty() and _views[1]["terrain"]["returnable_parcels"].has("terrain-item-1"), "new holder alone sees return eligibility")
	var panel := TerrainControlsPanel.new()
	root.add_child(panel)
	panel.configure(_clients[1])
	panel.observe(_views[1])
	_check(not panel._return.disabled, "actual panel enables legitimate holder return")
	panel._return.emit_signal("pressed")
	var retained: Dictionary = _clients[1].terrain_pending_intent()
	_check(retained.get("schema_version") == 3 and retained.get("operation") == "return" and retained["payload"].size() == 2 and panel._return.disabled and panel._claim.disabled, "panel freezes original two-field return and disables fresh terrain work")
	var changed: SimulationCommand = _return_command(1, "terrain-item-1")
	changed.payload["expected_inventory_revision"] += 1
	_check(not _clients[1].enqueue_command(changed).is_success and _clients[1].terrain_pending_intent() == retained, "uncertain return cannot be replaced by changed revisions")
	_check(not _clients[1].enqueue_command(_terrain(1, "excavate", "terrain.dirt.source", 1)).is_success, "uncertain return blocks fresh terrain work")
	await _wait(func() -> bool: return not _host._pending.is_empty(), 3.0, false)
	_step()
	_check(_host._events.size() == 1 and _host._events[0]["frame"]["ok"], "real atomic holder return commits before lost acknowledgement")
	_host._events.clear()
	var settled: Dictionary = _canonical(_world)
	var fixture := FileAccess.open("res://var/terrain-return-client-fixture.json", FileAccess.WRITE)
	fixture.store_string(JSON.stringify({"observation": _world.terrain_observation(_host._context(1)).value, "intent": retained}))
	fixture.close()
	await _wait(func() -> bool: return not store.status()["busy"], 3.0, false)
	_check(store.request_checkpoint().is_success, "return checkpoint requests")
	await _wait(func() -> bool: return not store.status()["busy"], 3.0)
	var saved: ServiceResult = LocalWorldSaveStore.read_latest(_directory.path_join("host"))
	_check(saved.is_success, "return checkpoint reaches temporary disk")
	panel.free()
	_host.free()
	await _wait(func() -> bool: return _clients[1]._requests.is_empty(), 3.0)
	_check(_clients[1].terrain_pending_intent() == retained and _clients[1]._terrain_record.is_empty(), "disconnect clears views while retaining immutable original return")
	for client in _clients: client.free()
	_clients.clear()
	_views.clear()
	store.free()
	_world.free()
	_world = WorldRuntime.new()
	_world.resource_carriers_enabled = true
	root.add_child(_world)
	_check(_world.restore_world_snapshot_json(saved.value["snapshot_json"]).is_success, "host return checkpoint restores")
	_start_host(null)
	await _connect_clients()
	_check(_clients[1].terrain_pending_intent() == retained and _views[1]["terrain"]["next_return_request_number"] == 2 and _views[1]["terrain"]["transfers"]["terrain-transfer-1"]["mass_milligrams"] == 777777, "restart retains original ordinal despite next 2 and holder escrow")
	_acks.erase("1:terrain-return-1")
	_check(_clients[1].retry_terrain_intent().is_success, "original return retries after both-end restart")
	await _wait(func() -> bool: return _acks.has("1:terrain-return-1"), 3.0)
	await create_timer(0.13).timeout
	_check(_acks.has("1:terrain-return-1") and _acks["1:terrain-return-1"].is_success and _clients[1].terrain_pending_intent().is_empty() and _canonical(_world) == settled, "return reconciliation is exactly once")
	panel = TerrainControlsPanel.new()
	root.add_child(panel)
	panel.configure(_clients[1])
	panel.observe(_views[1])
	_check(panel._claim.disabled and panel._return.disabled and not panel._fill.disabled, "returned escrow explicitly permits fill and denies rematerialization")
	panel.free()
	_check(_clients[0].restore_terrain_intent({"schema_version": 2, "world_id": String(_world.world_id), "region_id": String(_world.region_id), "slot": 0, "request_number": original_claim.request_number, "operation": "materialize", "payload": original_claim.payload}).is_success, "original claim uncertainty journal reloads")
	await _claim_send(0, original_claim, true)
	_check(_canonical(_world) == settled, "original claimant wire retry never resurrects a returned parcel")
	await _terrain_send(1, _terrain(1, "fill", "terrain.dirt.fill", 777777, "terrain-transfer-1"), true)
	var filled: Dictionary = _canonical(_world)
	_check(filled["terrain"]["cells"]["terrain.dirt.fill"]["state"]["mass_milligrams"] == 777777 and filled["terrain"]["transfers"].is_empty(), "authenticated holder fills exact original mass from returned escrow")
	_check(_clients[1].restore_terrain_intent(retained).is_success, "original return journal reloads after fill")
	_clients[1]._socket.close(-1)
	await _wait(func() -> bool: return _host._peers.size() == 1 and not _clients[1]._connecting, 3.0)
	_views.erase(1)
	_check(_clients[1].connect_host("ws://127.0.0.1:%d" % PORT, _keys[1]).is_success, "same adapter reconnects after fill")
	await _wait(func() -> bool: return _views.has(1), 3.0)
	_acks.erase("1:terrain-return-1")
	_check(_clients[1].retry_terrain_intent().is_success, "old return intent retries across reconnect and fill")
	await _wait(func() -> bool: return _acks.has("1:terrain-return-1"), 3.0)
	_check(_acks.has("1:terrain-return-1") and _acks["1:terrain-return-1"].is_success and _canonical(_world) == filled, "reconnect reconciliation never duplicates matter or physical records")
	for client in _clients: client.free()
	_host.free()
	_world.free()
	_cleanup(ProjectSettings.globalize_path(_directory))
	if _failures == 0: print("Terrain return client: scoped holder transfer, panel action, forged/stale/foreign denial, frozen journal, lost ack, disk restart, fill and reconnect exactly-once acceptance passed.")
	quit(0 if _failures == 0 else 1)


func _return_command(slot: int, item: String) -> SimulationCommand:
	return TerrainTransportCodec.command(int(_views[slot]["terrain"]["next_return_request_number"]), "return", {"item_id": item, "expected_inventory_revision": _views[slot]["inventory"]["inventory_revision"]})


func _world_move(slot: int, operation: String, item: String, destination: String) -> void:
	var command := InventoryDevelopmentCommand.new()
	command.operation = "world"
	command.payload = {"operation": operation, "item_id": item, "world_container_id": "world.tray-1", "destination_container_id": destination, "slot_id": "", "expected_revision": _views[slot]["inventory"]["inventory_revision"]}
	await _send(slot, command)


func _canonical(world: WorldRuntime) -> Dictionary:
	var terrain := world.get_simulation_system(TerrainSimulationSystem.SYSTEM_ID) as TerrainSimulationSystem
	var inventory := world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem
	return JSON.parse_string(JSON.stringify({"terrain": terrain.capture_snapshot().value["owner"], "portable": terrain.capture_snapshot().value["portable"], "claims": terrain.capture_snapshot().value["claims"], "inventory": inventory.capture_snapshot().value["owner"]}))


func _claim(slot: int, transfer: String) -> SimulationCommand:
	return TerrainTransportCodec.command(int(_views[slot]["terrain"]["next_materialize_request_number"]), "materialize", {"transfer_id": transfer, "expected_inventory_revision": _views[slot]["inventory"]["inventory_revision"]})


func _claim_send(slot: int, command: SimulationCommand, success: bool) -> void:
	var key: String = "%d:%s" % [slot, command.command_id]
	_acks.erase(key)
	_check(_clients[slot].enqueue_command(command).is_success, "claim transport queues")
	await _wait(func() -> bool: return _acks.has(key), 3.0)
	_check(_acks.has(key) and _acks[key].is_success == success, "claim expected host outcome")
	await create_timer(0.13).timeout


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
