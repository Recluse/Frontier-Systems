extends SceneTree

class RecordingWorld extends WorldRuntime:
	var sent: Array[SimulationCommand] = []
	var queue_failure: ServiceResult
	func enqueue_command(command: SimulationCommand) -> ServiceResult:
		sent.append(command)
		return queue_failure if queue_failure != null else ServiceResult.success()

class RecordingRemote extends RemoteWorldRuntime:
	var sent: Array[SimulationCommand] = []
	func enqueue_command(command: SimulationCommand) -> ServiceResult:
		sent.append(command)
		return ServiceResult.success()

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var world := RecordingWorld.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "Detached fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	var context := AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var frame: Dictionary = {"inventory": inventory.own_inventory_observation(context, true).value, "production": world.production_observation(context).value, "position": inventory.own_position(context).value, "world_items": inventory.world_inventory_observation(context).value}
	var before: String = world.capture_world_snapshot_json().value
	var frame_before: String = JSON.stringify(frame)
	var workstation := LocalProductionPanel.new()
	root.add_child(workstation)
	check(workstation.configure(world).is_success, "Actual Workstation configures")
	workstation._send("process", {"recipe_id": "refine.iron"})
	var request: SimulationCommand = world.sent[-1]
	world.command_completed.emit(request, ServiceResult.failure(&"production_rejected", "The production revision is stale or exhausted."))
	check(workstation._pending.is_empty() and workstation._feedback.text.contains("The production revision is stale or exhausted.") and workstation._feedback.text.contains("Code: production_rejected") and workstation._feedback.text.contains("Next:"), "Workstation preserves broad stale receipt and adds review advice")
	var prior: String = workstation._feedback.text
	workstation.refresh()
	check(workstation._feedback.text == prior, "Observation refresh does not pretend rejection is resolved")
	workstation._send("process", {"recipe_id": "refine.iron"})
	check(not workstation._feedback.text.contains("Next:"), "New explicit queued action replaces old advice")
	world.command_completed.emit(request, ServiceResult.failure(&"production_rejected", "Late unrelated receipt"))
	check(workstation._feedback.text == "Queued process", "Old completion cannot overwrite new pending feedback")
	world.command_completed.emit(world.sent[-1], ServiceResult.success())
	check(workstation._feedback.text == "Applied process", "Success clears rejection advice without claiming batch completion")
	world.queue_failure = ServiceResult.failure(&"production_rejected", "Insufficient feedstock")
	workstation._send("process", {"recipe_id": "refine.iron"})
	check(workstation._pending.is_empty() and workstation._feedback.text.contains("Insufficient feedstock") and workstation._feedback.text.contains("shared stock"), "Queue-time failure retains resources guidance")
	world.queue_failure = null
	workstation._pending = "maintenance-fixture"
	var maintenance := ProductionDevelopmentCommand.new()
	maintenance.command_id = &"maintenance-fixture"
	maintenance.operation = "repair_tool_component"
	world.command_completed.emit(maintenance, ServiceResult.failure(&"production_rejected", "Maintenance energy unavailable"))
	check(workstation._maintenance_feedback.text.contains("Maintenance energy unavailable") and workstation._maintenance_feedback.text.contains("Next:"), "Maintenance uses the same verified failure advice")
	workstation._pending = "maintenance-success"
	maintenance.command_id = &"maintenance-success"
	world.command_completed.emit(maintenance, ServiceResult.success())
	check(not workstation._maintenance_feedback.text.contains("Next:") and workstation._maintenance_feedback.text.contains("Await current condition observation"), "Maintenance success clears advice and retains observation uncertainty")

	var remote := RecordingRemote.new()
	root.add_child(remote)
	var panel := PlayerInventoryPanel.new()
	root.add_child(panel)
	panel.configure(remote)
	panel.observe(frame)
	for code: String in ["inventory_revision_conflict", "body_inventory_revision_conflict", "inventory_source_conflict", "equipment_slot_capacity", "shared_inventory_conflict", "inventory_development_rejected"]:
		panel._submit("move", {})
		var count: int = remote.sent.size()
		remote.command_completed.emit(remote.sent[-1], ServiceResult.failure(StringName(code), "Original host reason " + code))
		check(panel._pending.is_empty() and panel._result.text.contains("Original host reason " + code) and panel._result.text.contains("Code: " + code) and panel._result.text.contains("Next:"), "Inventory preserves reason and guidance for " + code)
		panel.observe(frame)
		check(remote.sent.size() == count, "Inventory observation and receipt never retry")
	panel._submit("move", {})
	check(not panel._result.text.contains("Next:"), "Inventory next pending clears previous advice")
	remote.command_completed.emit(remote.sent[-1], ServiceResult.failure(&"unrecognized_fixture_code", "Unknown host rejection"))
	check(panel._result.text.contains("Unknown host rejection") and not panel._result.text.contains("Next:"), "Unknown failure replaces advice without guessing")
	panel._submit("move", {})
	remote.command_completed.emit(remote.sent[-1], ServiceResult.success())
	check(not panel._result.text.contains("Code:") and not panel._result.text.contains("Next:"), "Inventory success removes failure presentation")

	var construction := MachineryPanel.new()
	root.add_child(construction)
	construction.configure(world)
	construction.observe(frame)
	construction._send("machine_craft")
	world.command_completed.emit(world.sent[-1], ServiceResult.failure(&"invalid_machinery_intent", "Not enough refined iron"))
	check(construction._pending.is_empty() and construction._feedback.text.contains("Not enough refined iron") and construction._feedback.text.contains("materials"), "Construction explains broad resource failure")
	construction._send("machine_craft")
	# Detached receipt fixture exercises the existing removal uncertainty formatter.
	construction._pending_wall = {"operation": "wall_remove", "wall_id": "wall.fixture"}
	world.command_completed.emit(world.sent[-1], ServiceResult.failure(&"wall_construction_denied", "Wall is outside reach"))
	check(construction._pending.is_empty() and construction._pending_wall.is_empty() and construction._feedback.text.contains("Wall is outside reach") and construction._feedback.text.contains("No plate return confirmed") and construction._placement_status.text.contains("Next:"), "Removal keeps original reach reason, no-return uncertainty and advice")
	construction._send("machine_craft")
	world.command_completed.emit(world.sent[-1], ServiceResult.success())
	check(construction._feedback.text == "Completed" and not construction._placement_status.text.contains("Next:"), "New successful construction result clears old wall advice")
	check(world.sent.size() == 6 and remote.sent.size() == 8, "Only the explicitly invoked panel actions were submitted")
	var total: int = world.sent.size()
	var remote_total: int = remote.sent.size()
	workstation.refresh()
	construction.observe(frame)
	panel.observe(frame)
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	check(world.sent.size() == total and remote.sent.size() == remote_total, "Rendering and observation never enqueue an unintended command")
	check(world.capture_world_snapshot_json().value == before and JSON.stringify(frame) == frame_before, "All panel receipt guidance preserves canonical state and observations")
	workstation._on_closed()
	check(not workstation._feedback.text.contains("Next:"), "Closed Workstation retires advice")
	remote.connection_closed.emit("Disconnected fixture; outcome unknown")
	check(panel._result.text.contains("outcome unknown") and not panel._result.text.contains("Next:"), "Disconnect retires settled Inventory advice and preserves uncertainty")
	construction.free()
	workstation.free()
	panel.free()
	remote.free()
	world.free()
	print("Engineering failure guidance: %d failures" % failures)
	quit(1 if failures else 0)
