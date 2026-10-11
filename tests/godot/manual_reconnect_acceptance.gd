extends SceneTree

## Disposable loopback host; authentication can precede the first projection.
class DelayedHost extends FirstPlayableHost:
	var publish: bool = false
	var commands: int = 0
	func _publish(id: int) -> void:
		if publish: super._publish(id)
	func _receive(id: int, value: Dictionary) -> void:
		if value.get("type") == "command": commands += 1
		super._receive(id, value)

var failures: int = 0
var world: WorldRuntime
var store: WorldPersistenceAdapter
var host: DelayedHost
var client: FirstPlayableBootstrap
var directory: String
var keys: Array[String] = ["reconnect-fixture-one-000000000000000", "reconnect-fixture-two-000000000000000"]
var acks: Dictionary = {}
var checkpoint_receipt: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func wait_for(predicate: Callable, seconds: float = 4.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < deadline: await process_frame
	return predicate.call()

func start_host() -> void:
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	store = WorldPersistenceAdapter.new()
	root.add_child(store)
	check(store.configure(world, directory).is_success, "disposable checkpoint store configures/restores")
	host = DelayedHost.new()
	host.persistence = store
	root.add_child(host)
	check(host.configure(world, keys, 27849).is_success and world.start_simulation().is_success, "leased loopback host starts")

func run() -> void:
	create_timer(45.0).timeout.connect(func() -> void: push_error("Reconnect acceptance deadline"); quit(1))
	root.size = Vector2i(1440, 900)
	directory = "res://var/ci/manual-reconnect-world-%d" % Time.get_ticks_usec()
	var old_url: String = OS.get_environment("FRONTIER_HOST_URL")
	var old_key: String = OS.get_environment("FRONTIER_INVITE_KEY")
	OS.set_environment("FRONTIER_HOST_URL", "ws://127.0.0.1:27849")
	OS.set_environment("FRONTIER_INVITE_KEY", keys[0])
	start_host()
	client = FirstPlayableBootstrap.new()
	root.add_child(client)
	client._remote.terrain_retry_directory = directory.path_join("client-intents")
	client._remote.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void:
		acks[String(command.command_id)] = result
		if command is CheckpointRequest:
			# Dedicated checkpoint feedback survives the following observation.
			checkpoint_receipt["success"] = result.is_success
			checkpoint_receipt["visible"] = client._checkpoint_status.text == "Shared world checkpoint confirmed on disk."
	)
	check(await wait_for(func() -> bool: return client._remote._authenticated), "real session authenticates")
	check(client._latest.is_empty() and client._reconnect.disabled and not client._remote.connection_ready(), "authentication waits for first observation")
	var denied := CheckpointRequest.new()
	denied.command_id = &"before-observation"
	check(not client._remote.enqueue_command(denied).is_success and host.commands == 0, "no command transmitted before fresh projection")
	host.publish = true
	check(await wait_for(func() -> bool: return not client._latest.is_empty()), "first real observation readies client")
	client._habitat.character.read_local_keyboard = false
	client._habitat.character.set_physics_process(false)
	var body: String = client._latest["inventory"]["body_id"]
	var hand := InventoryDevelopmentCommand.new()
	hand.command_id = &"reconnect-hand"
	hand.operation = "self"
	hand.payload = {"operation": "switch_hand", "item_id": "", "source_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": client._latest["inventory"]["inventory_revision"]}
	check(client._remote.enqueue_command(hand).is_success, "real inventory command queues")
	check(await wait_for(func() -> bool: return acks.has("reconnect-hand")) and acks["reconnect-hand"].is_success, "real inventory command acknowledged")
	await create_timer(0.2).timeout
	var expected: Dictionary = client._latest.duplicate(true)
	await capture("connected")
	check(await wait_for(func() -> bool: return not store.status()["busy"]), "checkpoint worker idle")
	client._host_actions[-1].pressed.emit()
	check(await wait_for(func() -> bool: return checkpoint_receipt.has("success"), 5.0) and checkpoint_receipt.get("success", false) and checkpoint_receipt.get("visible", false), "actual save button confirms disk checkpoint at receipt delivery")
	var disk_checkpoint: ServiceResult = LocalWorldSaveStore.read_latest(directory)
	check(disk_checkpoint.is_success and not disk_checkpoint.value.is_empty(), "acknowledged checkpoint exists on disposable disk")
	var uncertain := InventoryDevelopmentCommand.new()
	var retained: Dictionary = {"schema_version": 3, "world_id": String(world.world_id), "region_id": String(world.region_id), "slot": 0, "request_number": 1, "operation": "return", "payload": {"item_id": "terrain-item-999999", "expected_inventory_revision": expected["inventory"]["inventory_revision"]}}
	check(client._remote.restore_terrain_intent(retained).is_success, "fixture restores bounded unresolved terrain intent without submission")
	retained = LocalTerrainRetryStore.normalized(retained)
	uncertain.command_id = &"unacknowledged-hand"
	uncertain.operation = "self"
	uncertain.payload = hand.payload.duplicate(true)
	uncertain.payload["expected_revision"] = expected["inventory"]["inventory_revision"]
	check(client._remote.enqueue_command(uncertain).is_success, "pending inventory request sent before shutdown")
	host.free()
	check(await wait_for(func() -> bool: return client._latest.is_empty() and not client._remote._connecting), "same running client clears disconnected observations")
	check(acks.has("unacknowledged-hand") and not acks["unacknowledged-hand"].is_success and client._remote._requests.is_empty(), "uncertain command abandoned without replay")
	check(not client._reconnect.disabled and client._production_panel == null and client._avatars.is_empty(), "disconnect exposes retry and clears production/crew")
	for action in client._host_actions: check(action.disabled, "host actions disabled after disconnect")
	check(client._remote.terrain_pending_intent() == retained, "disconnect preserves exact terrain intent")
	await capture("disconnected")
	store.free()
	world.free()
	# An absent host fails visibly and leaves manual retry enabled.
	client._reconnect.pressed.emit()
	check(await wait_for(func() -> bool: return not client._reconnect.disabled, 7.0) and client._latest.is_empty(), "unavailable host stays retryable")
	start_host()
	host.publish = true
	OS.set_environment("FRONTIER_INVITE_KEY", "reconnect-invalid-invite-000000000000")
	client._reconnect.pressed.emit()
	check(await wait_for(func() -> bool: return not client._reconnect.disabled) and client._connection_status.text.contains("rejected"), "real invite rejection stays visible/retryable")
	await capture("rejected")
	OS.set_environment("FRONTIER_INVITE_KEY", keys[0])
	client._reconnect.pressed.emit()
	client._reconnect.pressed.emit()
	check(await wait_for(func() -> bool: return not client._latest.is_empty()), "manual button reconnects same client to restored host")
	check(client._remote.server_slot == 0 and client._latest["inventory"]["body_id"] == body, "host reauthenticates same persistent identity")
	for field in ["items", "active_hand_slot_id", "inventory_revision"]:
		check(client._latest["inventory"][field] == expected["inventory"][field], "restored inventory retains " + field)
	for field in ["store", "deposits", "walls", "structures", "components"]:
		check(client._latest["production"][field] == expected["production"][field], "restored world retains " + field)
	check(host.commands == 0 and client._remote._requests.is_empty(), "reconnect sends no abandoned inventory or construction requests")
	check(client._remote.terrain_pending_intent() == retained and not client._terrain_panel._retry.disabled, "exact terrain intent remains available only for explicit retry")
	check(client._production_panel != null and not client._host_actions[-1].disabled and client._reconnect.disabled, "fresh data rebuilds production and enables actions")
	await capture("reconnected")
	client.free()
	host.free()
	store.free()
	world.free()
	PlayerInputSettings.instance().release_all()
	OS.set_environment("FRONTIER_HOST_URL", old_url)
	OS.set_environment("FRONTIER_INVITE_KEY", old_key)
	await process_frame
	print("Manual reconnect restored-world loopback acceptance: %d failures; same running client, real authentication/checkpoint/retry; no human gameplay claim" % failures)
	quit(0 if failures == 0 else 1)

func capture(stage: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture-reconnect"): return
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://var/ci/manual-reconnect-render/captures"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	check(root.get_texture().get_image().save_png(path.path_join(stage + ".png")) == OK, "internal ordinary engine capture " + stage)
