extends "res://tests/godot/player_movement_loopback_test.gd"

## Reuse the existing loopback shell/trace/wait fixture. Configuration and button
## signals are synthetic; all authentication, commands, receipts and observations
## traverse production WebSockets. Replacement is in-process, not a crash test.
class ContainerClient extends LoopbackClient:
	var port: int = 27861
	func _connect_client() -> void:
		if _reconnect.disabled: return
		_reconnect.disabled = true
		_remote.terrain_retry_directory = "" # No terrain commands/journal in this fixture.
		var result: ServiceResult = _remote.connect_host("ws://127.0.0.1:%d" % port, invite)
		if not result.is_success:
			_connection_status.text = result.message
			_reconnect.disabled = false

var store: WorldPersistenceAdapter
var directory: String
var panel: PlayerInventoryPanel
var foreign_results: Dictionary = {}

func owner() -> Dictionary:
	return (world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem).capture_snapshot().value["owner"]

func normalized(value: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(value))

func selected(id: String) -> void:
	for index in range(panel._closure_target.item_count):
		if panel._closure_target.get_item_metadata(index) == id:
			panel._closure_target.select(index)
			panel._closure_target.item_selected.emit(index)
			return
	check(false, "actual owner picker includes " + id)

func observed_open(id: String, opened: bool) -> bool:
	var record: Dictionary = PlayerInventoryPresentation.owned_container(panel._equipment_record, id)
	return record.has("is_open") and record["is_open"] == opened

func closure(id: String, operation: String) -> SimulationCommand:
	selected(id)
	var count: int = remote.sent.size()
	check(not panel._closure_buttons[operation].disabled, "actual closure button enabled")
	panel._closure_buttons[operation].pressed.emit()
	check(remote.sent.size() == count + 1, "button submits exactly one real transport intent")
	if remote.sent.size() != count + 1: return null
	var command: SimulationCommand = remote.sent[-1]
	check(command.operation == operation and command.payload == {"container_id": id, "expected_revision": int(panel._equipment_record["inventory_revision"])}, "owner-selected exact ID/revision reaches transport")
	return command

func settle(command: SimulationCommand, id: String, opened: bool) -> bool:
	if command == null: return false
	if not await wait_for(func() -> bool: return results.has(String(command.command_id)) and panel._pending.is_empty() and observed_open(id, opened), "matching wire receipt and fresh closure observation"): return false
	check(results[String(command.command_id)].is_success and panel._closure_feedback.text.contains(String(command.command_id)), "panel retains exact accepted closure receipt")
	return true

func transfer(transport: RemoteWorldRuntime, id: String) -> InventoryDevelopmentCommand:
	var command := InventoryDevelopmentCommand.new()
	command.command_id = StringName(id)
	command.operation = &"self"
	command.payload = {"operation": "move", "item_id": "crowbar-1", "source_container_id": "storage.pouch-1", "destination_container_id": "body.human-1", "slot_id": "", "expected_revision": owner()["state_revision"]}
	check(transport.enqueue_command(command).is_success, "submit nested transfer through real adapter")
	return command

func start_host(port: int) -> bool:
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	store = WorldPersistenceAdapter.new()
	root.add_child(store)
	if not store.configure(world, directory).is_success:
		check(false, "native temporary checkpoint adapter configures replacement world")
		return false
	host = FirstPlayableHost.new()
	host.persistence = store
	root.add_child(host)
	if not host.configure(world, KEYS, port).is_success:
		check(false, "leased port available; never replace another listener")
		return false
	check(world.start_simulation().is_success, "canonical host starts")
	return true

func exercise() -> void:
	directory = OS.get_user_data_dir().path_join("container-wire-%d" % Time.get_ticks_usec())
	if not start_host(27861): return
	client = ContainerClient.new()
	client.invite = KEYS[1]
	root.add_child(client)
	client.set_process(false)
	client._habitat.character.read_local_keyboard = false
	client._habitat.character.set_physics_process(false)
	remote = client._remote as TracedRemote
	remote.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void: results[String(command.command_id)] = result)
	panel = client._inventory_panel
	observer = RemoteWorldRuntime.new()
	root.add_child(observer)
	observer.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void: foreign_results[String(command.command_id)] = result)
	check(observer.connect_host("ws://127.0.0.1:27861", KEYS[0]).is_success, "different principal connects through invite authentication")
	if not await wait_for(func() -> bool: return client._body_initialized and observer.server_slot == 0, "owner and foreign principal authenticate"): return
	check(remote.server_slot == 1 and panel._record["body_id"] == "body.human-1", "owner shell observes server-selected body")
	var before: Dictionary = owner().duplicate(true)
	var mass: int = panel._record["mass_milligrams"]
	var denied := InventoryDevelopmentCommand.new()
	denied.command_id = &"wire.foreign.close"
	denied.operation = &"close_container"
	denied.payload = {"container_id": "storage.backpack-1", "expected_revision": before["state_revision"]}
	check(observer.enqueue_command(denied).is_success, "other authenticated principal submits same physical target")
	if not await wait_for(func() -> bool: return foreign_results.has("wire.foreign.close"), "foreign denial arrives on wire"): return
	check(not foreign_results["wire.foreign.close"].is_success and owner() == before, "foreign close denied without canonical mutation")
	# Hold only fixture ticks; observations continue over the real connection.
	world.get_node("SimulationRunner").set_physics_process(false)
	var command: SimulationCommand = closure("storage.backpack-1", "close_container")
	if command == null: return
	var count: int = remote.sent.size()
	selected("storage.pouch-1")
	if not await wait_for(func() -> bool: return not host._pending.is_empty(), "actual host holds panel close intent"): return
	await create_timer(0.25).timeout
	check(owner() == before and not observed_open("storage.backpack-1", false), "pending observations never optimistically close owner state")
	check(panel._pending_closure["container_id"] == "storage.backpack-1" and panel._pending_closure["expected_revision"] == before["state_revision"] and remote.sent.size() == count, "picker changes and repeated observations retain original pending target without retry")
	world.get_node("SimulationRunner").set_physics_process(true)
	if not await settle(command, "storage.backpack-1", false): return
	var closed: Dictionary = owner().duplicate(true)
	var receipt: Dictionary = {}
	for retained in closed["receipts"]:
		if retained["request_id"] == "net-1-" + String(command.command_id): receipt = retained.duplicate(true)
	check(closed["receipts"].has(receipt) and receipt["request_id"] == "net-1-" + String(command.command_id) and int(receipt["state_revision"]) == int(before["state_revision"]) + 1, "matching wire acknowledgement identifies exact canonical closure receipt/revision")
	check(closed["ledger"]["items"] == before["ledger"]["items"] and panel._record["mass_milligrams"] == mass, "closure conserves every item/provenance field and exact mass")
	transfer(remote, "wire.closed.transfer")
	if not await wait_for(func() -> bool: return results.has("wire.closed.transfer"), "closed nested transfer wire denial"): return
	check(not results["wire.closed.transfer"].is_success and owner() == closed, "closed ancestor blocks nested move without mutation")
	# Request disk confirmation through the actual shell and host checkpoint route.
	client._request_checkpoint()
	if not await wait_for(func() -> bool: return client._checkpoint_request == null and client._checkpoint_status.text.contains("confirmed on disk"), "real checkpoint receipt confirms native disk save"): return
	var saved: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	check(saved.is_success, "read checksummed native checkpoint")
	if not saved.is_success: return
	var checkpoint: Dictionary = JSON.parse_string(saved.value["snapshot_json"])
	check(checkpoint["systems"]["inventory"]["owner"] == normalized(closed), "disk retains complete closed owner/revision/closure receipt")
	var sent_before: int = remote.sent.size()
	var old_frames: int = remote.frames.size()
	remote._socket.close(-1)
	observer._socket.close(-1)
	if not await wait_for(func() -> bool: return not client._body_initialized and host._peers.is_empty(), "real disconnect clears both host sessions"): return
	check(panel._record.is_empty() and panel._pending_closure.is_empty() and remote.sent.size() == sent_before, "disconnect clears presentation without replay")
	host.free()
	store.free()
	world.free()
	if not start_host(27862): return
	check(normalized(owner()) == checkpoint["systems"]["inventory"]["owner"], "replacement world restores exact owner and retained closure receipt")
	(client as ContainerClient).port = 27862
	client._connect_client()
	check(panel._record.is_empty() and remote.sent.size() == sent_before, "manual reconnect sends no action before fresh observation")
	if not await wait_for(func() -> bool: return client._body_initialized and observed_open("storage.backpack-1", false), "fresh replacement wire observation establishes closed state"): return
	check(remote.sent.size() == sent_before and normalized(owner()) == normalized(closed) and panel._record["mass_milligrams"] == mass, "reconnect and ticks retain exact closure receipt/items/mass without auto-retry")
	check(not remote.frames.slice(old_frames).any(func(frame: Dictionary) -> bool: return frame.get("type") == "ack" and frame.get("request_id") == String(command.command_id)), "old closure acknowledgement never leaks into replacement session")
	transfer(remote, "wire.recovered.closed")
	if not await wait_for(func() -> bool: return results.has("wire.recovered.closed"), "replacement closed transfer denial"): return
	check(not results["wire.recovered.closed"].is_success and normalized(owner()) == normalized(closed), "restored closed ancestry still blocks nested move")
	var opened: SimulationCommand = closure("storage.backpack-1", "open_container")
	if not await settle(opened, "storage.backpack-1", true): return
	transfer(remote, "wire.reopened.transfer")
	if not await wait_for(func() -> bool: return results.has("wire.reopened.transfer") and panel._record["inventory_revision"] == owner()["state_revision"], "reopened transfer receipt and fresh inventory"): return
	check(results["wire.reopened.transfer"].is_success, "explicit reopen permits intended nested transfer")
	var items: Array = owner()["ledger"]["items"].duplicate(true)
	for item in items:
		if item["item_id"] == "crowbar-1":
			check(item["container_id"] == "body.human-1", "only intended item moves to intended owner body")
			item["container_id"] = "storage.pouch-1"
	check(normalized(items) == normalized(before["ledger"]["items"]) and panel._record["mass_milligrams"] == mass, "successful transfer conserves all exact item/provenance fields and carried mass")
	check(normalized(owner()["receipts"]).has(normalized(receipt)), "original closure receipt retained after replacement/reopen/transfer")

func _run() -> void:
	root.size = Vector2i(1100, 720)
	await exercise()
	if is_instance_valid(client): client.free()
	if is_instance_valid(observer): observer.free()
	if is_instance_valid(host): host.free()
	if is_instance_valid(store): store.free()
	if is_instance_valid(world): world.free()
	if DirAccess.dir_exists_absolute(directory):
		for filename in DirAccess.get_files_at(directory):
			check(DirAccess.remove_absolute(directory.path_join(filename)) == OK, "remove task-owned checkpoint file")
		check(DirAccess.remove_absolute(directory) == OK, "remove task-owned checkpoint directory")
	PlayerInputSettings.instance().release_all()
	await process_frame
	print("Owned container wire/durable recovery: %d failures; fixture-owned listeners closed; no human/process-crash evidence" % failures)
	quit(1 if failures else 0)
