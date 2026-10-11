extends "res://tests/godot/player_inventory_closure_loopback_test.gd"

## Paid matter setup reuses player_inventory_access_guidance_test's finite recipe.
## Shell button signals are synthetic; transport, ticks, disk and receipts are real.
const PORT: int = 27849
var paid_item: String
var seed_result: ServiceResult
var seed_sequence: int = 0

func seed_command(operation: String, payload: Dictionary, production: bool = false) -> void:
	seed_sequence += 1
	var command: SimulationCommand = ProductionDevelopmentCommand.new() if production else InventoryDevelopmentCommand.new()
	command.command_id = StringName("nested-paid-%d" % seed_sequence)
	command.operation = StringName(operation)
	command.payload = payload
	command.authenticated_context = host._context(1)
	check(world.enqueue_command(command).is_success, "existing paid fixture queues " + operation)
	world.get_node("SimulationRunner")._physics_process(1.0 / 60.0)
	check(seed_result != null and seed_result.is_success, "existing paid fixture settles " + operation)

func produce(operation: String, payload: Dictionary = {}) -> void:
	payload["expected_revision"] = world.production_observation(host._context(1)).value["state_revision"]
	seed_command(operation, payload, true)

func seed_move(id: String, source: String, destination: String) -> void:
	seed_command("self", {"operation": "move", "item_id": id, "source_container_id": source, "destination_container_id": destination, "slot_id": "", "expected_revision": owner()["state_revision"]})

func pay_for_item() -> void:
	var runner: Node = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: seed_result = result)
	seed_command("move_to", {"position_millimetres": [0, 0, 0]})
	seed_command("world", {"operation": "pickup", "item_id": "resource-canister-2", "world_container_id": "world.tray-1", "destination_container_id": "body.human-1", "slot_id": "", "expected_revision": owner()["state_revision"]})
	for _batch in range(2):
		seed_command("move_to", {"position_millimetres": ProductionSimulationSystem.SOURCE_POSITIONS["deposit.iron"]})
		produce("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-2", "amount_milligrams": 1000000})
		seed_command("move_to", {"position_millimetres": [0, 0, 0]})
		produce("unload_cargo", {"carrier_id": "resource-canister-2", "material": "ore.iron", "amount_milligrams": 1000000})
		produce("process", {"recipe_id": "refine.iron"})
		for _tick in range(120): runner._physics_process(1.0 / 60.0)
	produce("process", {"recipe_id": "craft.plate"})
	for _tick in range(120): runner._physics_process(1.0 / 60.0)
	produce("materialize_plate")
	var paid: Dictionary = world.production_observation(host._context(1)).value
	check(paid["deposits"]["deposit.iron"] == 8000000 and paid["store"]["iron"] == 200000 and paid["store"]["tailings"] == 800000, "finite paid extraction/processing budget")
	if paid["components"].is_empty(): return
	paid_item = paid["components"][0]
	var production := world.get_simulation_system(ProductionSimulationSystem.SYSTEM_ID) as ProductionSimulationSystem
	check(production.payload_mass(paid_item) == 1000000 and paid["energy_joules"] < 100000, "real one-kilogram material provenance and consumed processing energy")
	seed_move("crowbar-1", "storage.pouch-1", "body.human-1")
	seed_move(paid_item, "body.human-1", "storage.pouch-1")
	runner.set_physics_process(true)

func choose(picker: OptionButton, id: String) -> void:
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == id:
			picker.select(index)
			picker.item_selected.emit(index)
			return
	check(false, "real picker includes " + id)

func move_paid() -> SimulationCommand:
	choose(panel._source, "storage.pouch-1")
	for index in range(panel._items.item_count):
		if panel._items.get_item_metadata(index)["item_id"] == paid_item:
			panel._items.select(index)
			panel._items.item_selected.emit(index)
	choose(panel._destination, "body.human-1")
	var count: int = remote.sent.size()
	check(not panel._inventory_buttons["move"].disabled, "fresh paid move control enabled")
	panel._inventory_buttons["move"].pressed.emit()
	check(remote.sent.size() == count + 1, "actual button sends one paid transfer")
	if remote.sent.size() != count + 1: return null
	var command: SimulationCommand = remote.sent[-1]
	check(command.operation == &"self" and normalized(command.payload) == normalized({"operation": "move", "item_id": paid_item, "source_container_id": "storage.pouch-1", "destination_container_id": "body.human-1", "slot_id": "", "expected_revision": owner()["state_revision"]}), "exact paid transfer and observed revision")
	return command

func checkpoint_owner(expected: Dictionary) -> Dictionary:
	client._request_checkpoint()
	if not await wait_for(func() -> bool: return client._checkpoint_request == null and client._checkpoint_status.text.contains("confirmed on disk"), "native shell checkpoint confirmed on disk"): return {}
	var saved: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	check(saved.is_success, "checksummed native checkpoint readable")
	if not saved.is_success: return {}
	var record: Dictionary = JSON.parse_string(saved.value["snapshot_json"])
	check(record["systems"]["inventory"]["owner"] == normalized(expected), "complete canonical owner persisted with equipment/provenance/receipts")
	return record

func replace_from_disk(expected: Dictionary, sent_count: int) -> bool:
	remote._socket.close(-1)
	if not await wait_for(func() -> bool: return not client._body_initialized and host._peers.is_empty(), "real disconnect fences shell and host session"): return false
	check(panel._record.is_empty() and panel._pending.is_empty() and remote._requests.is_empty(), "disconnection clears observations and pending transport/panel")
	host.free()
	store.free()
	world.free()
	if not start_host(PORT): return false
	check(normalized(owner()) == normalized(expected), "replacement restores exact checkpoint owner")
	client._connect_client()
	check(panel._record.is_empty() and remote.sent.size() == sent_count, "explicit manual reconnect sends no inventory action")
	if not await wait_for(func() -> bool: return client._body_initialized and int(panel._record["inventory_revision"]) == int(expected["state_revision"]), "fresh authenticated replacement observation"): return false
	await create_timer(0.25).timeout
	check(normalized(owner()) == normalized(expected) and remote.sent.size() == sent_count, "reconnect observations/ticks neither replay nor optimistically move")
	return true

func exercise() -> void:
	directory = OS.get_user_data_dir().path_join("nested-paid-recovery-%d" % Time.get_ticks_usec())
	if not start_host(PORT): return
	pay_for_item()
	if paid_item.is_empty(): return
	client = ContainerClient.new()
	(client as ContainerClient).port = PORT
	client.invite = KEYS[1]
	root.add_child(client)
	client.set_process(false)
	client._habitat.character.read_local_keyboard = false
	client._habitat.character.set_physics_process(false)
	remote = client._remote as TracedRemote
	remote.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void: results[String(command.command_id)] = result)
	panel = client._inventory_panel
	if not await wait_for(func() -> bool: return client._body_initialized and remote.server_slot == 1, "paid owner authenticates in actual shell"): return
	var mass: int = panel._record["mass_milligrams"]
	var closed_command: SimulationCommand = closure("storage.backpack-1", "close_container")
	if not await settle(closed_command, "storage.backpack-1", false): return
	var closed: Dictionary = owner().duplicate(true)
	var saved: Dictionary = await checkpoint_owner(closed)
	if saved.is_empty(): return
	var open_command: SimulationCommand = closure("storage.backpack-1", "open_container")
	if not await settle(open_command, "storage.backpack-1", true): return
	var pending_before: Dictionary = owner().duplicate(true)
	world.get_node("SimulationRunner").set_physics_process(false)
	var abandoned: SimulationCommand = move_paid()
	if abandoned == null: return
	if not await wait_for(func() -> bool: return not host._pending.is_empty(), "real paid transfer admitted but ticks held"): return
	var count: int = remote.sent.size()
	var frames: int = remote.frames.size()
	await create_timer(0.25).timeout
	check(owner() == pending_before and not panel._pending.is_empty() and remote.sent.size() == count, "pending paid transfer never moves optimistically or repeats")
	if not await replace_from_disk(closed, count): return
	check(results.has(String(abandoned.command_id)) and results[String(abandoned.command_id)].error_code == &"remote_disconnected", "abandoned paid transfer reports unknown outcome")
	check(observed_open("storage.backpack-1", false) and panel._record["mass_milligrams"] == mass, "restored closed ancestor and total carried mass observed")
	check(not remote.frames.slice(frames).any(func(value: Dictionary) -> bool: return value.get("type") == "ack" and value.get("request_id") == String(abandoned.command_id)), "fresh session invents no abandoned transfer acknowledgement")
	var feedback: String = panel._result.text
	check(feedback.contains("outcome is unknown") and feedback.contains("Reconnect and refresh"), "fresh observation preserves transfer uncertainty and explicit recovery guidance")
	panel._completed(abandoned, ServiceResult.success())
	check(panel._result.text == feedback and panel._pending.is_empty(), "late abandoned completion cannot settle unknown transfer")
	# Send an explicit fresh intent through the adapter despite the disabled UI.
	var denied := InventoryDevelopmentCommand.new()
	denied.command_id = &"nested.recovered.closed"
	denied.operation = &"self"
	denied.payload = abandoned.payload.duplicate(true)
	denied.payload["expected_revision"] = owner()["state_revision"]
	check(remote.enqueue_command(denied).is_success, "fresh closed transfer reaches real host validation")
	if not await wait_for(func() -> bool: return results.has(String(denied.command_id)), "restored closed rejection receipt"): return
	check(not results[String(denied.command_id)].is_success and results[String(denied.command_id)].error_code == &"inventory_container_closed" and normalized(owner()) == normalized(closed), "closed ancestor rejects paid move atomically")
	open_command = closure("storage.backpack-1", "open_container")
	if not await settle(open_command, "storage.backpack-1", true): return
	var before: Dictionary = owner().duplicate(true)
	var fresh: SimulationCommand = move_paid()
	if fresh == null: return
	check(fresh.command_id != abandoned.command_id, "explicit new move allocates fresh identity")
	if not await wait_for(func() -> bool: return results.has(String(fresh.command_id)) and panel._pending.is_empty() and int(panel._record["inventory_revision"]) == int(owner()["state_revision"]), "paid move receipt and fresh observation"): return
	check(results[String(fresh.command_id)].is_success, "explicit reopen permits fresh paid transfer")
	var expected: Dictionary = before.duplicate(true)
	expected["state_revision"] = int(before["state_revision"]) + 1
	expected["ledger"]["state_revision"] = int(before["ledger"]["state_revision"]) + 1
	for item in expected["ledger"]["items"]:
		if item["item_id"] == paid_item: item["container_id"] = "body.human-1"
	for body in expected["bodies"]:
		if body["body_id"] == "body.human-1": body["state_revision"] = int(body["state_revision"]) + 1
	var request_id: String = "net-1-" + String(fresh.command_id)
	var fingerprint: String = JSON.stringify(["self", before["owner_id"], request_id, "body.human-1", "move", paid_item, "storage.pouch-1", "body.human-1", "", int(before["state_revision"])]).sha256_text()
	expected["receipts"].append({"request_id": request_id, "fingerprint": fingerprint, "state_revision": expected["state_revision"]})
	check(normalized(owner()) == normalized(expected), "complete owner differs only by paid item location, revisions and exact receipt; containers/equipment/provenance conserved")
	check(panel._record["mass_milligrams"] == mass, "paid nested move conserves exact carried mass")
	var committed: Dictionary = await checkpoint_owner(expected)
	if committed.is_empty(): return
	check(conserved_production(saved, committed), "inventory recovery never refunds or repeats paid production")
	count = remote.sent.size()
	if not await replace_from_disk(expected, count): return
	check(panel._record["mass_milligrams"] == mass, "completed paid transfer remains conserved after second native recovery")

func conserved_production(before: Dictionary, after: Dictionary) -> bool:
	var current: Dictionary = after["systems"]["production"].duplicate(true)
	current["last_tick"] = before["systems"]["production"]["last_tick"]
	return current == before["systems"]["production"]
