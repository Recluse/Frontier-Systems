extends SceneTree

const PORT: int = 19241
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
	_directory = "user://terrain-parcel-client-%d" % Time.get_ticks_usec()
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
	var own_transfer: String = _views[0]["terrain"]["transfers"].keys()[0]
	var foreign: String = _views[1]["terrain"]["transfers"].keys()[0]
	var mistyped := TerrainCommand.new()
	mistyped.command_id = &"terrain-materialize-1"
	mistyped.request_number = 1
	mistyped.operation = "materialize"
	mistyped.payload = {"transfer_id": own_transfer, "expected_inventory_revision": _views[0]["inventory"]["inventory_revision"]}
	_check(not _clients[0].enqueue_command(mistyped).is_success, "work command cannot masquerade as typed claim")
	var before: Dictionary = _canonical(_world)
	await _claim_send(0, _claim(0, foreign), false)
	_check(_canonical(_world) == before, "foreign claimant rejection preserves both owners")
	var stale: SimulationCommand = _claim(0, own_transfer)
	stale.payload["expected_inventory_revision"] += 1
	await _claim_send(0, stale, false)
	_check(_canonical(_world) == before, "stale inventory rejection preserves both owners")
	for field in ["mass_milligrams", "definition_id", "material_id", "parcels", "principal_id", "destination_container_id"]:
		var forbidden: SimulationCommand = _claim(0, own_transfer)
		forbidden.payload[field] = "forged"
		_check(not _clients[0].enqueue_command(forbidden).is_success and _clients[0].terrain_pending_intent().is_empty(), "client codec rejects injected " + field)
		# Bypass client validation to prove the authenticated host boundary too.
		_acks.erase("0:terrain-materialize-1")
		_clients[0]._requests["terrain-materialize-1"] = forbidden
		_clients[0]._socket.send_text(JSON.stringify({"type": "command", "request_id": "terrain-materialize-1", "system": "terrain", "operation": "materialize", "request_number": 1, "payload": forbidden.payload}))
		await _wait(func() -> bool: return _acks.has("0:terrain-materialize-1"), 3.0)
		await create_timer(0.13).timeout
		_check(_acks.has("0:terrain-materialize-1") and not _acks["0:terrain-materialize-1"].is_success and _canonical(_world) == before, "host rejects injected matter/authority " + field)
	await _full_capacity(_world.capture_world_snapshot().value.to_dictionary(), own_transfer)
	# Both peers submit the independent claim ordinal 1; revisions are globally serialized.
	var claim_zero: SimulationCommand = _claim(0, own_transfer)
	var claim_one: SimulationCommand = _claim(1, foreign)
	_acks.erase("0:terrain-materialize-1")
	_acks.erase("1:terrain-materialize-1")
	_check(_clients[0].enqueue_command(claim_zero).is_success and _clients[1].enqueue_command(claim_one).is_success, "same claim ordinal queues for both authenticated peers")
	await _wait(func() -> bool: return _acks.has("0:terrain-materialize-1") and _acks.has("1:terrain-materialize-1"), 3.0)
	_check(_acks.has("0:terrain-materialize-1") and _acks.has("1:terrain-materialize-1") and _acks["0:terrain-materialize-1"].is_success != _acks["1:terrain-materialize-1"].is_success, "independent claim routes return exactly one stale revision rejection")
	await create_timer(0.13).timeout
	var claimant: int = 0 if not _acks["0:terrain-materialize-1"].is_success else 1
	var transfer: String = _views[claimant]["terrain"]["transfers"].keys()[0]
	# Drive the actual panel action and lose only its outbound acknowledgement.
	var panel := TerrainControlsPanel.new()
	root.add_child(panel)
	panel.configure(_clients[claimant])
	panel.observe(_views[claimant])
	_check(not panel._claim.disabled, "Terrain panel enables whole own escrow claim")
	panel._claim.emit_signal("pressed")
	var retained: Dictionary = _clients[claimant].terrain_pending_intent()
	_check(retained.get("schema_version") == 2 and retained.get("operation") == "materialize" and retained["payload"].size() == 2 and panel._claim.disabled, "panel freezes two-field original claim and disables fresh work")
	var changed: SimulationCommand = _claim(claimant, transfer)
	changed.payload["expected_inventory_revision"] += 1
	_check(not _clients[claimant].enqueue_command(changed).is_success and _clients[claimant].terrain_pending_intent() == retained, "changed unresolved retry never replaces original journal")
	await _wait(func() -> bool: return not _host._pending.is_empty(), 3.0, false)
	_step()
	_check(_host._events.size() == 1 and _host._events[0]["frame"]["ok"], "lost claim acknowledgement follows a real atomic commit")
	_host._events.clear()
	var settled: Dictionary = _canonical(_world)
	var fixture := FileAccess.open("res://var/terrain-parcel-client-fixture.json", FileAccess.WRITE)
	fixture.store_string(JSON.stringify({"observation": _world.terrain_observation(_host._context(claimant)).value, "intent": retained}))
	fixture.close()
	await _wait(func() -> bool: return not store.status()["busy"], 3.0, false)
	_check(store.request_checkpoint().is_success, "portable claim temporary checkpoint requests")
	await _wait(func() -> bool: return not store.status()["busy"], 3.0)
	var saved: ServiceResult = LocalWorldSaveStore.read_latest(_directory.path_join("host"))
	_check(saved.is_success, "portable claim checkpoint reaches temporary disk")
	panel.free()
	_host.free()
	await _wait(func() -> bool: return _clients[claimant]._requests.is_empty(), 3.0)
	_check(_clients[claimant].terrain_pending_intent() == retained and _clients[claimant]._terrain_record.is_empty(), "disconnect preserves claim while clearing projections and routes")
	for client in _clients: client.free()
	_clients.clear()
	_views.clear()
	store.free()
	_world.free()
	_world = WorldRuntime.new()
	_world.resource_carriers_enabled = true
	root.add_child(_world)
	_check(_world.restore_world_snapshot_json(saved.value["snapshot_json"]).is_success, "portable host checkpoint restores")
	_start_host(null)
	await _connect_clients()
	_check(_clients[claimant].terrain_pending_intent() == retained and _views[claimant]["terrain"]["next_materialize_request_number"] == 2 and _views[claimant]["terrain"]["transfers"].is_empty(), "restarted client retains ordinal 1 despite observed next 2 and consumed escrow")
	var retry_key: String = "%d:terrain-materialize-1" % claimant
	_acks.erase(retry_key)
	_check(_clients[claimant].retry_terrain_intent().is_success, "exact original claim retries after both-end restart")
	await _wait(func() -> bool: return _acks.has(retry_key), 3.0)
	await create_timer(0.13).timeout
	_check(_acks.has(retry_key) and _acks[retry_key].is_success and _clients[claimant].terrain_pending_intent().is_empty() and _canonical(_world) == settled, "exact retry reconciles without creating matter/items/revisions")
	# Send a changed retained ordinal directly; host owner must reject it atomically.
	var altered: Dictionary = retained["payload"].duplicate(true)
	altered["expected_inventory_revision"] += 1
	var forged_retry: SimulationCommand = TerrainTransportCodec.command(1, "materialize", altered)
	_clients[claimant]._requests["terrain-materialize-1"] = forged_retry
	_acks.erase(retry_key)
	_clients[claimant]._socket.send_text(JSON.stringify({"type": "command", "request_id": "terrain-materialize-1", "system": "terrain", "operation": "materialize", "request_number": 1, "payload": altered}))
	await _wait(func() -> bool: return _acks.has(retry_key), 3.0)
	_check(_acks.has(retry_key) and not _acks[retry_key].is_success and _canonical(_world) == settled, "host changed retained retry rejects atomically")
	await create_timer(0.13).timeout
	# Same adapter reconnect with a restored original retained intent also reconciles.
	_check(_clients[claimant].restore_terrain_intent(retained).is_success, "retained claim reloads for reconnect fixture")
	_clients[claimant]._socket.close(-1)
	await _wait(func() -> bool: return _host._peers.size() == 1 and not _clients[claimant]._connecting, 3.0)
	_views.erase(claimant)
	_check(_clients[claimant].connect_host("ws://127.0.0.1:%d" % PORT, _keys[claimant]).is_success, "same adapter reconnects")
	await _wait(func() -> bool: return _views.has(claimant), 3.0)
	_acks.erase(retry_key)
	_check(_clients[claimant].retry_terrain_intent().is_success, "same-adapter exact claim retries")
	await _wait(func() -> bool: return _acks.has(retry_key), 3.0)
	_check(_acks.has(retry_key) and _acks[retry_key].is_success and _canonical(_world) == settled, "same-adapter reconnect preserves single physical parcel")
	for slot in range(2):
		var items: int = 0
		for item in _views[slot]["inventory"]["items"]:
			if item["definition_id"] == "item.terrain-parcel.prototype": items += 1
		_check(items == 1 and _views[slot]["terrain"]["transfers"].is_empty(), "each peer sees only its own single portable inventory parcel")
	for client in _clients: client.free()
	_host.free()
	_world.free()
	_cleanup(ProjectSettings.globalize_path(_directory))
	if _failures == 0: print("TERRAIN PARCEL CLIENT: authenticated two-peer routing, scoped claims, panel action, atomic rejections, lost acknowledgement, disk restart and reconnect reconciliation passed.")
	quit(0 if _failures == 0 else 1)


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


func _full_capacity(snapshot: Dictionary, transfer: String) -> void:
	var full: Dictionary = snapshot.duplicate(true)
	var body_root: String = _views[0]["inventory"]["body_container_id"]
	var count: int = 0
	for item in full["systems"]["inventory"]["owner"]["ledger"]["items"]:
		if item["container_id"] == body_root: count += 1
	for container in full["systems"]["inventory"]["owner"]["ledger"]["containers"]:
		if container["container_id"] == body_root: container["capacity"]["max_items"] = count
	var clone := WorldRuntime.new()
	clone.resource_carriers_enabled = true
	root.add_child(clone)
	_check(clone.restore_world_snapshot_json(JSON.stringify(full)).is_success, "trusted full inventory fixture restores")
	var host := FirstPlayableHost.new()
	root.add_child(host)
	_check(host.configure(clone, _keys, 19242).is_success and clone.start_simulation().is_success, "separate full-capacity loopback fixture starts")
	var clients: Array[RemoteWorldRuntime] = []
	var views: Dictionary = {}
	var results: Dictionary = {}
	for slot in range(2):
		var client := RemoteWorldRuntime.new()
		root.add_child(client)
		client.observation_received.connect(func(record: Dictionary) -> void: views[slot] = record)
		client.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void: results[String(command.command_id)] = result)
		clients.append(client)
		_check(client.connect_host("ws://127.0.0.1:19242", _keys[slot]).is_success, "full fixture client connects")
	await _wait(func() -> bool: return views.size() == 2, 3.0, false)
	var before: Dictionary = _canonical(clone)
	_check(clients[0].enqueue_command(TerrainTransportCodec.command(1, "materialize", {"transfer_id": transfer, "expected_inventory_revision": views[0]["inventory"]["inventory_revision"]})).is_success, "full fixture claim queues through actual client")
	await _wait(func() -> bool: return results.has("terrain-materialize-1"), 3.0, false)
	_check(results.has("terrain-materialize-1") and not results["terrain-materialize-1"].is_success and _canonical(clone) == before, "full inventory host rejection is atomic and consumes no claim ordinal")
	for client in clients: client.free()
	host.free()
	clone.free()

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
