extends "res://tests/godot/first_playable_acceptance.gd"

## Finite paid wall only; reuse native transport/save helpers without broad fixture.
var world: WorldRuntime
var store: ManualCheckpointStore
var host: FirstPlayableHost
var client: RemoteWorldRuntime
var keys: Array[String] = ["wall-lifecycle-player-one-000000000000", "wall-lifecycle-player-two-000000000000"]
var directory: String

func record() -> Dictionary:
	return JSON.parse_string(world.capture_world_snapshot_json().value)

func stable_record() -> Dictionary:
	var value: Dictionary = record()
	value.erase("tick_number")
	for system in value["systems"].values():
		if system is Dictionary: system.erase("last_tick")
	return value

func _run() -> void:
	create_timer(100.0).timeout.connect(func() -> void: push_error("Wall lifecycle deadline"); quit(1))
	directory = "user://paid-wall-lifecycle-%d" % Time.get_ticks_usec()
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	store = ManualCheckpointStore.new()
	root.add_child(store)
	_check(store.configure(world, directory).is_success, "native disposable checkpoint adapter")
	host = FirstPlayableHost.new()
	host.persistence = store
	root.add_child(host)
	_check(host.configure(world, keys, 27849).is_success and world.start_simulation().is_success, "leased finite host starts")
	var shell: FirstPlayableBootstrap = _connect_shell(keys[0])
	_shells.append(shell)
	client = shell._remote
	client.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void: _acks[String(command.command_id)] = result; _ack_slots[String(command.command_id)] = 0)
	client.observation_received.connect(func(value: Dictionary) -> void: _observations[0] = value)
	await _wait(func() -> bool: return _observations.has(0), 5.0)
	if not _observations.has(0): _check(false, "authenticated own observation"); quit(1); return
	shell._habitat.character.read_local_keyboard = false
	shell._habitat.character.set_physics_process(false)
	var initial: Dictionary = record()
	var initial_mass: int = int(_observations[0]["inventory"]["mass_milligrams"])
	await _walk_to(client, 0, [-3000, 0, -1000])
	for extraction in range(2):
		await _production(client, 0, "extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
	await _walk_to(client, 0, [0, 0, 0])
	await _production(client, 0, "unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 2000000})
	for batch in range(2):
		await _production(client, 0, "process", {"recipe_id": "refine.iron"})
		await _wait(func() -> bool: return _observations[0]["production"]["job"].is_empty(), 4.0)
	await _production(client, 0, "process", {"recipe_id": "craft.plate"})
	await _wait(func() -> bool: return _observations[0]["production"]["job"].is_empty(), 4.0)
	await _production(client, 0, "materialize_plate", {})
	await _wait(func() -> bool: return not _observations[0]["production"]["components"].is_empty(), 3.0)
	if _observations[0]["production"]["components"].is_empty(): _check(false, "paid plate observation required"); quit(1); return
	var plate: String = _observations[0]["production"]["components"][0]
	var physical: Dictionary = record()
	_check(int(_observations[0]["inventory"]["mass_milligrams"]) == initial_mass + 1000000, "paid physical plate adds exactly one kilogram carried mass")
	var build: Dictionary = {"item_id": plate, "position": [0, 0, -1000], "quarter_turn": 0, "expected_revision": _observations[0]["production"]["state_revision"]}
	var build_id: String = _queue(client, "production", "wall_build", build)
	await _wait(func() -> bool: return _acks.has(build_id), 3.0)
	_check(_acks.has(build_id) and _acks[build_id].is_success, "canonical physical wall build accepted")
	await create_timer(0.25).timeout
	var wall: String = _observations[0]["production"]["walls"].keys()[0]
	_check(_observations[0]["production"]["components"].is_empty() and int(_observations[0]["inventory"]["mass_milligrams"]) == initial_mass, "wall consumes physical plate and exactly its carried mass")
	await replace_host()
	await replay(build_id, "wall_build", build, true)
	var removal: Dictionary = {"wall_id": wall, "expected_revision": _observations[0]["production"]["state_revision"]}
	var remove_id: String = _queue(client, "production", "wall_remove", removal)
	await _wait(func() -> bool: return _acks.has(remove_id), 3.0)
	_check(_acks.has(remove_id) and _acks[remove_id].is_success, "explicit removal accepted once")
	await create_timer(0.25).timeout
	var completed: Dictionary = record()
	var production: Dictionary = completed["systems"]["production"]
	_check(production["walls"].is_empty() and _observations[0]["production"]["components"].size() == 1, "absent wall returns one finite physical plate")
	var returned: String = _observations[0]["production"]["components"][0]
	_check(returned != plate and production["cargo"][returned] == physical["systems"]["production"]["cargo"][plate], "removal has its own stable receipt-derived identity and exact original material bill")
	var original_item: Dictionary = plate_item(physical, plate)
	var returned_item: Dictionary = plate_item(completed, returned)
	original_item["item_id"] = returned
	_check(not returned_item.is_empty() and returned_item == original_item, "returned plate preserves exact catalog definition, revision, condition and receiving container with only its new identity")
	_check(int(_observations[0]["inventory"]["mass_milligrams"]) == initial_mass + 1000000, "one kilogram returns to original receiver")
	_check(production["deposits"]["deposit.iron"] == 8000000 and production["store"]["iron"] == 200000 and production["store"]["tailings"] == 800000 and production["store"]["plate"] == 0, "ten-kilogram iron budget closes across source, stock, tailings and returned plate")
	_check(completed["systems"]["tools"]["ledger"] == initial["systems"]["tools"]["ledger"], "wall lifecycle preserves all unrelated tool component provenance")
	await removal_probes(remove_id, removal)
	await replace_host()
	_check(stable_record()["systems"]["inventory"]["owner"] == completed["systems"]["inventory"]["owner"], "completed checkpoint retains exact returned inventory provenance and revisions")
	await removal_probes(remove_id, removal)
	await _production(client, 0, "recycle_component", {"item_id": returned})
	await _wait(func() -> bool: return _observations[0]["production"]["components"].is_empty() and _observations[0]["production"]["store"]["iron"] == 1200000, 3.0)
	_check(_observations[0]["production"]["components"].is_empty() and _observations[0]["production"]["store"]["iron"] == 1200000, "returned plate recycles once to exactly original refined matter")
	await replace_host()
	await removal_probes(remove_id, removal)
	await replay("fresh.recycled-plate", "recycle_component", {"item_id": returned, "expected_revision": _observations[0]["production"]["state_revision"]}, false)
	host.free()
	for value in _shells: value.free()
	store.free()
	world.free()
	for file in DirAccess.get_files_at(directory): _check(DirAccess.remove_absolute(directory.path_join(file)) == OK, "remove disposable checkpoint file")
	_check(DirAccess.remove_absolute(directory) == OK, "remove disposable checkpoint directory")
	print("Paid wall lifecycle durable recovery: %d failures" % _failures)
	quit(1 if _failures else 0)

func replace_host() -> void:
	# Stop ticks before save: compare every world field, not merely visible wall.
	world.get_node("SimulationRunner").set_physics_process(false)
	await _manual_save(0, store)
	var disk: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	_check(disk.is_success and JSON.parse_string(disk.value["snapshot_json"]) == record(), "native worker disk readback retains complete exact world at saved tick")
	var before: Dictionary = stable_record()
	host.free()
	await _wait(func() -> bool: return not client.connection_ready() and _shells[0]._latest.is_empty(), 3.0)
	_check(client._requests.is_empty(), "disconnect retains no automatic replay request")
	store.free()
	world.free()
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	store = ManualCheckpointStore.new()
	root.add_child(store)
	_check(store.configure(world, directory).is_success, "replacement loads checksum-validated native checkpoint")
	_check(record() == JSON.parse_string(disk.value["snapshot_json"]), "all world records, identities, mass, receipts and revisions restore exactly before ticks")
	host = FirstPlayableHost.new()
	host.persistence = store
	root.add_child(host)
	_check(host.configure(world, keys, 27849).is_success and world.start_simulation().is_success, "replacement starts on exclusively leased port")
	world.get_node("SimulationRunner").set_physics_process(false)
	_observations.clear()
	await process_frame
	_check(not client.connection_ready() and _shells[0]._latest.is_empty(), "same client never automatically reconnects")
	var old_url: String = OS.get_environment("FRONTIER_HOST_URL")
	var old_key: String = OS.get_environment("FRONTIER_INVITE_KEY")
	OS.set_environment("FRONTIER_HOST_URL", "ws://127.0.0.1:27849")
	OS.set_environment("FRONTIER_INVITE_KEY", keys[0])
	_shells[0]._reconnect.pressed.emit()
	OS.set_environment("FRONTIER_HOST_URL", old_url)
	OS.set_environment("FRONTIER_INVITE_KEY", old_key)
	await _wait(func() -> bool: return _observations.has(0), 4.0)
	_check(_observations.has(0) and client._requests.is_empty(), "same manual reconnect control authenticates without replay")
	_check(stable_record() == before, "manual reconnect preserves complete canonical world")
	world.get_node("SimulationRunner").set_physics_process(true)
	await create_timer(0.25).timeout

func replay(id: String, operation: String, payload: Dictionary, success: bool) -> void:
	var before: Dictionary = domain_record()
	var action := ProductionDevelopmentCommand.new()
	action.command_id = StringName(id)
	action.operation = operation
	action.payload = payload.duplicate(true)
	_acks.erase(id)
	_check(client.enqueue_command(action).is_success, "exact authenticated probe queues")
	await _wait(func() -> bool: return _acks.has(id), 3.0)
	_check(_acks.has(id) and _acks[id].is_success == success, "expected retained/conflicting/absent-target outcome: " + operation)
	_check(domain_record() == before, "probe preserves complete production, inventory, terrain and component records except advancing tick")

func removal_probes(id: String, payload: Dictionary) -> void:
	await replay(id, "wall_remove", payload, true)
	var changed: Dictionary = payload.duplicate(true)
	changed["wall_id"] = "wall-absent-changed"
	await replay(id, "wall_remove", changed, false)
	await replay(id, "wall_build", {"item_id": "plate-absent", "position": [0, 0, -1000], "quarter_turn": 0, "expected_revision": payload["expected_revision"]}, false)
	await replay("fresh.absent.%d" % _counter, "wall_remove", {"wall_id": payload["wall_id"], "expected_revision": _observations[0]["production"]["state_revision"]}, false)



func domain_record() -> Dictionary:
	var systems: Dictionary = stable_record()["systems"]
	return {"production": systems["production"], "inventory": systems["inventory"], "tools": systems["tools"], "terrain": systems["terrain"]}

func plate_item(snapshot: Dictionary, id: String) -> Dictionary:
	var inventory_owner: Dictionary = snapshot["systems"]["inventory"]["owner"]
	for item in inventory_owner["ledger"]["items"]:
		if item["item_id"] == id: return item.duplicate(true)
	return {}
