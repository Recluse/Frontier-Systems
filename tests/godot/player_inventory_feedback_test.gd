extends SceneTree

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
	var world := WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	world.start_simulation()
	world.get_node("SimulationRunner").set_physics_process(false)
	var context := AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var frame: Dictionary = {"inventory": inventory.own_inventory_observation(context, true).value, "production": world.production_observation(context).value, "world_items": inventory.world_inventory_observation(context).value}
	# Presentation fixture stays detached; no item is minted in canonical storage.
	frame["world_items"]["containers"][0]["items"] = [{"item_id": "visible-canister", "definition_id": "item.resource-canister.prototype", "container_id": "world.tray-1"}]
	var before: String = world.capture_world_snapshot_json().value
	var remote := RecordingRemote.new()
	root.add_child(remote)
	var panel := PlayerInventoryPanel.new()
	root.add_child(panel)
	panel.configure(remote)
	panel.observe(frame)
	panel._world_items.select(0)
	panel._inspect_world()
	check(panel._world_details.text.contains("visible-canister") and panel._world_details.text.contains("Not carried by you"), "selected item identity and ownership advisory")
	var shifted: Dictionary = frame.duplicate(true)
	shifted["world_items"]["containers"][0]["distance_millimetres"] = 1400
	panel.observe(shifted)
	check(panel._world_details.text.contains("1.40 m"), "distance refreshes without revision changes")
	panel._world_action("pickup")
	check(remote.sent.size() == 1 and not panel._pending.is_empty(), "pickup queues once before acknowledgement")
	var frozen: Dictionary = panel._pending_world.duplicate(true)
	panel._world_items.deselect_all()
	panel.observe(frame)
	panel._world_action("pickup")
	check(remote.sent.size() == 1 and panel._pending_world == frozen and panel._result.text.contains("visible-canister"), "pending target stays frozen through selection/observation changes")
	remote.command_completed.emit(remote.sent[0], ServiceResult.failure(&"capacity", "Destination full"))
	check(panel._pending.is_empty() and panel._pending_world.is_empty() and panel._result.text.contains("Destination full"), "rejected action clears pending and reports host reason")
	var gone: Dictionary = shifted.duplicate(true)
	gone["world_items"]["containers"][0]["items"].clear()
	panel.observe(gone)
	panel._world_action("pickup")
	check(remote.sent.size() == 1 and panel._world_items.item_count == 0, "removed item cannot be submitted from stale row")
	panel._items.select(0)
	panel._world_action("drop")
	check(panel._pending_world.get("operation") == "drop" and panel._result.text.contains("world.tray-1"), "drop pins exact owned item and chosen world root")
	remote.connection_closed.emit("Fixture disconnect")
	check(panel._pending.is_empty() and panel._pending_world.is_empty() and panel._nearby.is_empty() and panel._world_root.item_count == 0 and panel._details.text.is_empty(), "disconnect clears pending, observations, selectors and details")
	remote.command_completed.emit(remote.sent[-1], ServiceResult.success())
	check(panel._result.text.contains("Fixture disconnect"), "late completion cannot overwrite disconnect")
	panel.observe(frame)
	check(panel._world_items.item_count == 1, "fresh observation repopulates after disconnect even at same revision")
	check(world.capture_world_snapshot_json().value == before, "presentation and queued mock commands leave canonical world unchanged")
	panel.free()
	remote.free()
	world.free()
	print("Player inventory feedback: %d failures" % failures)
	quit(1 if failures else 0)
