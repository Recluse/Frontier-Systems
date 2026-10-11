extends SceneTree

## Actual shell and loopback host. Only configuration/local poses are injected;
## every receipt and observation below comes through the production WebSocket.
class TracedRemote extends RemoteWorldRuntime:
	var sent: Array[SimulationCommand] = []
	var frames: Array[Dictionary] = []
	func enqueue_command(command: SimulationCommand) -> ServiceResult:
		var result: ServiceResult = super.enqueue_command(command)
		if result.is_success: sent.append(command)
		return result
	func _receive(frame: Dictionary) -> void:
		frames.append(frame.duplicate(true))
		super._receive(frame)

class LoopbackClient extends FirstPlayableBootstrap:
	var invite: String = "movement-loopback-one-key-000000000000"
	func _create_client_remote() -> RemoteWorldRuntime:
		return TracedRemote.new()
	func _connect_client() -> void:
		if _reconnect.disabled: return
		_reconnect.disabled = true
		var result: ServiceResult = _remote.connect_host("ws://127.0.0.1:27849", invite)
		if not result.is_success:
			_connection_status.text = result.message
			_reconnect.disabled = false

var failures: int = 0
var world: WorldRuntime
var host: FirstPlayableHost
var client: LoopbackClient
var remote: TracedRemote
var observer: RemoteWorldRuntime
var observations: Array[Dictionary] = []
var results: Dictionary = {}
var feedback_events: Array[Dictionary] = []
const KEYS: Array[String] = ["movement-loopback-one-key-000000000000", "movement-loopback-two-key-000000000000"]

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func wait_for(predicate: Callable, message: String) -> bool:
	var deadline: int = Time.get_ticks_msec() + 5000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	var passed: bool = predicate.call()
	check(passed, message)
	return passed

func display_position(position: Array) -> Vector3:
	return ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(float(position[0]), float(position[1]), float(position[2])) / 1000.0

func own_position(slot: int) -> Array:
	var inventory := world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID) as InventorySimulationSystem
	return inventory.own_position(host._context(slot)).value

func move_to(position: Array) -> InventoryDevelopmentCommand:
	var count: int = remote.sent.size()
	client._habitat.character.position = display_position(position)
	client._process(0.15)
	check(remote.sent.size() == count + 1, "shell sampler sends exactly one changed pose")
	return client._movement_request

func receipt_before_observation(id: String, position: Array) -> bool:
	var received: bool = false
	for frame in remote.frames:
		if frame.get("type") == "ack" and frame.get("request_id") == id:
			received = true
		elif received and frame.get("type") == "observation" and InventorySpatialMath.normalized(frame["position"]) == position:
			return true
	return false

func peer_for(slot: int) -> int:
	for id in host._peers:
		if host._peers[id]["slot"] == slot: return int(id)
	return -1

func _run() -> void:
	root.size = Vector2i(1100, 720)
	await exercise()
	# Fixture-owned nodes only; never terminate another listener/process.
	if is_instance_valid(client): client.free()
	if is_instance_valid(observer): observer.free()
	if is_instance_valid(host): host.free()
	if is_instance_valid(world): world.free()
	PlayerInputSettings.instance().release_all()
	await process_frame
	print("Movement loopback: %d failures; owned host/clients closed; no graphical/human acceptance" % failures)
	quit(1 if failures else 0)

func exercise() -> void:
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	host = FirstPlayableHost.new()
	root.add_child(host)
	if not host.configure(world, KEYS, 27849).is_success:
		check(false, "reserved loopback port must be available; never replace another listener")
		return
	check(world.start_simulation().is_success, "isolated canonical host starts without persistence/external effects")
	client = LoopbackClient.new()
	root.add_child(client)
	client.set_process(false)
	client._habitat.character.read_local_keyboard = false
	client._habitat.character.set_physics_process(false)
	remote = client._remote as TracedRemote
	remote.terrain_retry_directory = "" # Movement needs no journal/durable storage.
	remote.command_completed.connect(func(command: SimulationCommand, result: ServiceResult) -> void:
		results[String(command.command_id)] = result
		feedback_events.append({"type": "receipt", "id": String(command.command_id), "feedback": client._movement_status.text})
	)
	remote.observation_received.connect(func(_record: Dictionary) -> void:
		feedback_events.append({"type": "observation", "feedback": client._movement_status.text})
	)
	observer = RemoteWorldRuntime.new()
	root.add_child(observer)
	observer.observation_received.connect(func(record: Dictionary) -> void: observations.append(record))
	check(observer.connect_host("ws://127.0.0.1:27849", KEYS[1]).is_success, "second identity connects")
	if not await wait_for(func() -> bool: return client._body_initialized and not observations.is_empty(), "both identities receive real observations"): return
	check(remote.server_slot == 0 and observer.server_slot == 1 and client._latest["inventory"]["body_id"] != observations[-1]["inventory"]["body_id"], "authenticated bodies differ")
	client._habitat.character.set_physics_process(false)
	var second_position: Array = own_position(1).duplicate()
	# Allow the first request's vertical visual offset inside the capped step budget.
	await create_timer(0.5).timeout
	var accepted := move_to([100, 950, 0])
	if accepted == null: return
	var accepted_id: String = String(accepted.command_id)
	if not await wait_for(func() -> bool: return results.has(accepted_id) and client._latest["position"] == [100, 950, 0], "accepted receipt and post-tick observation arrive"): return
	check(receipt_before_observation(accepted_id, [100, 950, 0]), "accepted receipt precedes fresh position observation on real wire")
	check(results[accepted_id].is_success and own_position(0) == [100, 950, 0], "host accepts local motion into canonical actor position")
	check(client._movement_status.text.contains("Host accepted the submitted movement"), "actual shell retains acceptance through observations")
	check(own_position(1) == second_position, "moving first actor never moves second actor")
	if not await wait_for(func() -> bool: return observations[-1]["players"].any(func(player: Dictionary) -> bool: return player["slot"] == 0 and player["position"] == [100, 950, 0]), "second actor sees first actor position separately"): return
	check(observations[-1]["position"] == second_position, "other actor position remains distinct from own position")

	# Pause only this fixture's simulation runner; transport and observations keep running.
	var runner: Node = world.get_node("SimulationRunner")
	runner.set_physics_process(false)
	var pending := move_to([200, 950, 0])
	if pending == null: return
	if not await wait_for(func() -> bool: return not host._pending.is_empty(), "real host queues held movement"): return
	var sent_count: int = remote.sent.size()
	client._habitat.character.position.x += 0.1
	client._process(1.0)
	check(remote.sent.size() == sent_count and remote._requests.size() == 1 and client._movement_request == pending, "one pending request suppresses another changed local pose")
	var observation_count: int = feedback_events.size()
	if not await wait_for(func() -> bool: return feedback_events.size() > observation_count, "observations continue while movement pending"): return
	check(client._movement_pending and client._movement_status.text.contains("waiting for host acceptance"), "observation cannot settle pending movement")
	runner.set_physics_process(true)
	var pending_id: String = String(pending.command_id)
	if not await wait_for(func() -> bool: return results.has(pending_id) and client._latest["position"] == [200, 950, 0], "held movement settles at canonical tick"): return
	check(results[pending_id].is_success and not client._movement_pending and client._movement_request == null, "exact real receipt releases pending identity")

	# Inside region but > capped 4000 mm step: rejection must come from host budget.
	var rejected := move_to([-5000, 950, 0])
	if rejected == null: return
	var rejected_id: String = String(rejected.command_id)
	if not await wait_for(func() -> bool: return results.has(rejected_id), "real host rejection arrives"): return
	check(not results[rejected_id].is_success and results[rejected_id].error_code == &"movement_rejected", "host rejects excessive step")
	check(client._habitat.character.position == display_position([200, 950, 0]) and own_position(0) == [200, 950, 0], "rejection corrects visual pose to unchanged host position")
	var rejection_text: String = client._movement_status.text
	if not await wait_for(func() -> bool: return feedback_events[-1]["type"] == "observation", "observation follows rejection receipt"): return
	check(receipt_before_observation(rejected_id, [200, 950, 0]), "rejection receipt precedes following unchanged position observation")
	check(client._movement_status.text == rejection_text and rejection_text.contains("server step budget"), "following observation retains rejection explanation")
	check(feedback_events.any(func(event: Dictionary) -> bool: return event.get("id") == rejected_id and event["feedback"] == rejection_text), "receipt callback updates shell before subsequent observation")
	sent_count = remote.sent.size()
	for _sample in range(3):
		client._process(0.15)
		await create_timer(0.16).timeout
	check(remote.sent.size() == sent_count and remote._requests.is_empty(), "visual correction never emits a phantom resubmit")

	# Drop the real connection with a queued command; then authenticate the same
	# shell/transport as the other actor. Old tick work must retain its old principal.
	runner.set_physics_process(false)
	var abandoned := move_to([300, 950, 0])
	if abandoned == null: return
	var abandoned_id: String = String(abandoned.command_id)
	if not await wait_for(func() -> bool: return not host._pending.is_empty(), "disconnect fixture has real pending host work"): return
	var prior_peer: int = peer_for(0)
	host._peers[prior_peer]["socket"].close(-1)
	if not await wait_for(func() -> bool: return not client._body_initialized and remote._requests.is_empty() and peer_for(0) == -1, "actual disconnect clears shell and transport session"): return
	check(results.has(abandoned_id) and results[abandoned_id].error_code == &"remote_disconnected", "unacknowledged movement receives unknown transport outcome")
	check(client._movement_request == null and client._last_position.is_empty() and client._latest.is_empty() and remote.server_slot == -1, "disconnect fences movement identity and baseline")
	check(client._movement_status.text.contains("session ended"), "disconnect feedback survives synthetic completion")
	observer._socket.close(-1)
	if not await wait_for(func() -> bool: return host._peers.is_empty(), "old invite slots released before reconnect"): return
	runner.set_physics_process(true)
	if not await wait_for(func() -> bool: return own_position(0) == [300, 950, 0], "old work finishes under old principal without new-session receipt"): return
	check(own_position(0) == [300, 950, 0] and own_position(1) == second_position, "abandoned tick work remains scoped to original actor: %s / %s" % [own_position(0), own_position(1)])
	var frame_count: int = remote.frames.size()
	sent_count = remote.sent.size()
	client.invite = KEYS[1]
	client._connect_client()
	client._process(1.0)
	check(not client._body_initialized and remote.sent.size() == sent_count, "reconnecting shell cannot sample before fresh baseline")
	if not await wait_for(func() -> bool: return client._body_initialized and remote.server_slot == 1, "same shell reconnects with fresh other-identity observation"): return
	client._habitat.character.set_physics_process(false)
	check(client._latest["inventory"]["body_id"] == observations[-1]["inventory"]["body_id"] and client._last_position == second_position, "fresh baseline belongs to newly authenticated actor")
	check(client._movement_status.text.contains("Host position observed") and client._movement_request == null and remote.sent.size() == sent_count, "fresh observation resets feedback without replay")
	var new_frames: Array[Dictionary] = remote.frames.slice(frame_count)
	check(not new_frames.any(func(frame: Dictionary) -> bool: return frame.get("type") == "ack" and frame.get("request_id") == abandoned_id), "old pending receipt never crosses new authenticated identity")
	var first_position: Array = own_position(0).duplicate()
	await create_timer(0.5).timeout
	var fresh := move_to([int(second_position[0]) + 100, 950, int(second_position[2])])
	if fresh == null: return
	var fresh_id: String = String(fresh.command_id)
	if not await wait_for(func() -> bool: return results.has(fresh_id) and client._latest["position"] == fresh.payload["position_millimetres"], "fresh identity movement receives own receipt and baseline"): return
	check(results[fresh_id].is_success and fresh_id != abandoned_id and own_position(0) == first_position, "new movement identity affects only new actor")
	check(not remote.frames.slice(frame_count).any(func(frame: Dictionary) -> bool: return frame.get("type") == "ack" and frame.get("request_id") == abandoned_id), "old receipt stays fenced through new movement completion")
