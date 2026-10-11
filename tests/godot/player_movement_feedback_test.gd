extends "res://tests/godot/client_inventory_shell_test.gd"

class MovementRemote extends InventoryRemote:
	var reject: bool = false
	func enqueue_command(command: SimulationCommand) -> ServiceResult:
		if reject: return ServiceResult.failure(&"remote_not_ready", "Host is not ready.")
		return super.enqueue_command(command)

class MovementClient extends InventoryClient:
	func _create_client_remote() -> RemoteWorldRuntime:
		return MovementRemote.new()

func move_view() -> InventoryDevelopmentCommand:
	client._habitat.character.position.x += 0.1
	var before: int = remote.sent.size()
	client._process(0.15)
	check(remote.sent.size() == before + 1, "changed local pose submits one movement")
	return remote.sent[-1]

func receipt(request: SimulationCommand, ok: bool, code: String = "movement_rejected", message: String = "Movement exceeds the server step budget.") -> void:
	remote._requests[String(request.command_id)] = request
	remote._receive({"type": "ack", "request_id": String(request.command_id), "ok": ok, "code": code, "message": message})

func run() -> void:
	root.size = Vector2i(1100, 720)
	world = WorldRuntime.new()
	root.add_child(world)
	check(world.start_simulation().is_success, "canonical fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	client = MovementClient.new()
	root.add_child(client)
	client.set_process(false)
	remote = client._remote
	remote.set_process(false)
	remote.server_slot = 0
	check(client._movement_status.text.contains("unavailable"), "no host position before observation")
	observe_shell()
	var canonical: String = world.capture_world_snapshot_json().value
	var request: InventoryDevelopmentCommand = move_view()
	var waiting: String = client._movement_status.text
	check(waiting.contains("waiting for host acceptance") and waiting.contains("Local view"), "pending status distinguishes visual pose")
	var foreign := InventoryDevelopmentCommand.new()
	foreign.command_id = request.command_id
	foreign.operation = "move_to"
	remote.command_completed.emit(foreign, ServiceResult.failure(&"fixture", "Unrelated movement"))
	observe_shell()
	check(client._movement_status.text == waiting and client._movement_request == request, "same ID unrelated object and observations cannot settle pending movement")
	var sent: int = remote.sent.size()
	client._process(1.0)
	check(remote.sent.size() == sent, "pending movement cannot issue another request")
	receipt(request, false)
	observe_shell() # Socket poll can deliver receipt and observation in one frame.
	var corrected: String = client._movement_status.text
	check(corrected.contains("Host rejected movement") and corrected.contains("latest observed host position"), "rejection explanation survives next observation")
	check(not client._movement_pending and client._movement_request == null, "exact receipt settles own request")
	check(client._habitat.character.position == ProceduralWorldInventoryPreview.DISPLAY_ORIGIN + Vector3(0, 0.95, 0), "rejection returns visual pose to observed host position")
	client._process(0.15)
	check(remote.sent.size() == sent, "correction alone does not emit phantom movement")
	remote.command_completed.emit(request, ServiceResult.success())
	check(client._movement_status.text == corrected, "duplicate late success cannot rewrite rejection")
	var current: InventoryDevelopmentCommand = move_view()
	remote.command_completed.emit(request, ServiceResult.success())
	check(client._movement_status.text == waiting and client._movement_request == current, "prior receipt cannot settle new movement")
	receipt(current, true)
	observe_shell()
	check(client._movement_status.text.contains("Host accepted the submitted movement") and client._movement_status.text.contains("Further local motion"), "exact acceptance does not claim all visual movement accepted")
	var abandoned: InventoryDevelopmentCommand = move_view()
	receipt(abandoned, false, "remote_disconnected", "Transport lost")
	check(client._movement_status.text.contains("outcome unknown"), "synthetic transport failure is not host rejection")
	remote.connection_closed.emit("Fixture disconnect")
	check(client._movement_status.text.contains("session ended") and client._movement_request == null and client._elapsed == 0.0, "disconnect invalidates session feedback and sampling timer")
	remote.command_completed.emit(abandoned, ServiceResult.success())
	check(client._movement_status.text.contains("session ended"), "late receipt cannot revive disconnected session")
	sent = remote.sent.size()
	client._process(1.0)
	observe_shell()
	check(remote.sent.size() == sent and client._movement_status.text.contains("Host position observed"), "fresh session observation resets feedback without replay")
	var reject_remote: MovementRemote = remote
	reject_remote.reject = true
	client._habitat.character.position.x += 0.1
	client._process(0.15)
	check(remote.sent.size() == sent and not client._movement_pending and client._movement_request == null and client._movement_status.text.contains("not submitted"), "enqueue failure explains visual divergence without claiming acceptance")
	observe_shell()
	check(client._movement_status.text.contains("not submitted"), "queue failure survives observation")
	reject_remote.reject = false
	var bounded: InventoryDevelopmentCommand = move_view()
	remote.command_completed.emit(bounded, ServiceResult.failure(&"fixture", "x".repeat(2000)))
	check(client._movement_status.text.length() < 700, "one bounded result truncates long adapter messages")
	await settle()
	check(client._movement_status.is_visible_in_tree() and client._movement_status.autowrap_mode == TextServer.AUTOWRAP_WORD_SMART, "actual shell movement label visible and wraps")
	check(root.get_visible_rect().encloses(client._movement_status.get_global_rect()), "bounded long feedback stays inside desktop shell")
	root.size = Vector2i(960, 640)
	await settle()
	check(root.get_visible_rect().encloses(client._movement_status.get_global_rect()), "wrapped movement feedback stays inside smaller shell")
	observe_shell()
	var dropped: InventoryDevelopmentCommand = move_view()
	remote.connection_closed.emit("Fixture disconnect without receipt")
	remote.command_completed.emit(dropped, ServiceResult.failure(&"fixture", "Late host rejection"))
	check(client._movement_status.text.contains("session ended") and client._movement_request == null, "disconnect without synthetic receipt also invalidates correlation")
	check(world.capture_world_snapshot_json().value == canonical, "presentation feedback never changes canonical snapshot")
	client.free()
	world.free()
	PlayerInputSettings.instance().release_all()
	await process_frame
	print("Movement feedback: %d failures; socket-free actual shell, no graphical acceptance" % failures)
	quit(1 if failures else 0)
