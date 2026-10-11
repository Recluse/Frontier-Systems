extends "res://tests/godot/client_inventory_shell_test.gd"

class CheckpointRemote extends InventoryRemote:
	var reject: bool = false
	func enqueue_command(command: SimulationCommand) -> ServiceResult:
		if reject: return ServiceResult.failure(&"remote_not_ready", "Host is not ready.")
		return super.enqueue_command(command)

class CheckpointClient extends InventoryClient:
	func _create_client_remote() -> RemoteWorldRuntime:
		return CheckpointRemote.new()

func save() -> CheckpointRequest:
	var before: int = remote.sent.size()
	client._host_actions[3].pressed.emit()
	check(remote.sent.size() == before + 1, "explicit save emits exactly one command")
	check(remote.sent[-1] is CheckpointRequest, "only checkpoint I/O intent emitted")
	return remote.sent[-1]

func run() -> void:
	world = WorldRuntime.new()
	root.add_child(world)
	check(world.start_simulation().is_success, "canonical observation fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	client = CheckpointClient.new()
	root.add_child(client)
	client.set_process(false)
	remote = client._remote
	remote.set_process(false)
	remote.server_slot = 0
	observe_shell()
	var before: String = world.capture_world_snapshot_json().value
	check(not client._checkpoint_status.text.contains("confirmed"), "observation alone never confirms manual save")
	var request: CheckpointRequest = save()
	var waiting: String = client._checkpoint_status.text
	var foreign := CheckpointRequest.new()
	foreign.command_id = request.command_id
	remote.command_completed.emit(foreign, ServiceResult.success())
	check(client._checkpoint_status.text == waiting, "same ID on unrelated object cannot claim own request")
	var unrelated := InventoryDevelopmentCommand.new()
	unrelated.command_id = request.command_id
	remote.command_completed.emit(unrelated, ServiceResult.failure(&"fixture", "Unrelated failure"))
	observe_shell()
	check(client._checkpoint_status.text == waiting, "unrelated failure and observation preserve pending feedback")
	remote._requests[String(request.command_id)] = request
	remote._receive({"type": "ack", "request_id": String(request.command_id), "ok": true, "code": "checkpoint_saved", "message": "Saved"})
	observe_shell() # Receipt then observation in one frame, matching the socket poll race.
	check(client._checkpoint_status.text == "Shared world checkpoint confirmed on disk.", "same-frame observation preserves disk confirmation")
	await settle()
	check(client._checkpoint_status.is_visible_in_tree() and client._scroll.get_global_rect().encloses(client._checkpoint_status.get_global_rect()), "wrapped confirmation fully visible in actual shell")
	client._checkpoint_status.grab_focus()
	await settle()
	check(client._checkpoint_status.has_focus(), "checkpoint feedback supports keyboard focus")
	remote.command_completed.emit(request, ServiceResult.failure(&"fixture", "Duplicate late failure"))
	observe_shell()
	check(client._checkpoint_status.text.contains("confirmed on disk"), "settled request ignores duplicate completion")
	var next: CheckpointRequest = save()
	check(next != request and next.command_id != request.command_id and client._checkpoint_status.text == waiting, "new explicit save clears previous confirmation")
	remote.command_completed.emit(request, ServiceResult.success())
	check(client._checkpoint_status.text == waiting, "stale prior receipt cannot settle new request")
	remote.command_completed.emit(next, ServiceResult.failure(&"checkpoint_busy", "Checkpoint store busy."))
	observe_shell()
	check(client._checkpoint_status.text == "Checkpoint failed: Checkpoint store busy.", "failure remains readable after observation")
	remote.command_completed.emit(unrelated, ServiceResult.success())
	check(client._checkpoint_status.text.contains("Checkpoint failed"), "unrelated success cannot clear failure")
	var superseded: CheckpointRequest = save()
	var current: CheckpointRequest = save()
	remote.command_completed.emit(superseded, ServiceResult.success())
	check(client._checkpoint_status.text == waiting and client._checkpoint_request == current, "new save replaces pending correlation without accepting older receipt")
	remote.connection_closed.emit("Fixture disconnect")
	check(client._checkpoint_status.text.contains("outcome unknown"), "disconnect without synthetic command failure also reports unknown")
	observe_shell()
	var abandoned: CheckpointRequest = save()
	remote.command_completed.emit(abandoned, ServiceResult.failure(&"remote_disconnected", "Transport lost"))
	remote.connection_closed.emit("Fixture disconnect")
	var unknown: String = client._checkpoint_status.text
	check(unknown.contains("outcome unknown") and client._checkpoint_request == null, "pending disconnect reports unknown and invalidates correlation")
	remote.command_completed.emit(abandoned, ServiceResult.success())
	observe_shell()
	check(client._checkpoint_status.text == unknown, "late receipt and reconnect observation cannot claim disk success")
	var sent: int = remote.sent.size()
	check(sent == 5, "observations receipts and disconnect never replay or send other commands")
	var rejected_remote: CheckpointRemote = remote
	rejected_remote.reject = true
	client._host_actions[3].pressed.emit()
	check(remote.sent.size() == sent and client._checkpoint_request == null and client._checkpoint_status.text.contains("not submitted"), "queue failure clears old outcome without a send")
	observe_shell()
	check(client._checkpoint_status.text.contains("not submitted"), "queue failure survives observation")
	rejected_remote.reject = false
	var final_request: CheckpointRequest = save()
	remote.command_completed.emit(final_request, ServiceResult.success())
	remote.connection_closed.emit("Fixture disconnect")
	check(not client._checkpoint_status.text.contains("confirmed") and not client._checkpoint_status.text.contains("unknown"), "disconnect ends completed session feedback")
	remote.command_completed.emit(final_request, ServiceResult.success())
	check(not client._checkpoint_status.text.contains("confirmed"), "late completed receipt cannot revive ended session")
	check(client._checkpoint_status.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "bounded feedback wraps beside save control")
	check(world.capture_world_snapshot_json().value == before, "checkpoint presentation preserves canonical snapshot")
	client.free()
	world.free()
	PlayerInputSettings.instance().release_all()
	await process_frame
	print("Checkpoint feedback: %d failures; socket-free actual shell, no disk or graphical acceptance" % failures)
	quit(1 if failures else 0)
