extends SceneTree

class RecordingRemote extends RemoteWorldRuntime:
	var sent: Array[SimulationCommand] = []
	var reject_queue: bool = false
	func enqueue_command(command: SimulationCommand) -> ServiceResult:
		if reject_queue: return ServiceResult.failure(&"offline", "Queue unavailable")
		sent.append(command)
		return ServiceResult.success()

var failures: int = 0
var last_result: ServiceResult

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func choose(picker: OptionButton, id: String) -> void:
	picker.select(-1)
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == id: picker.select(index)

func select_item(list: ItemList, id: String) -> void:
	list.deselect_all()
	for index in range(list.item_count):
		if list.get_item_metadata(index)["item_id"] == id: list.select(index)

func frame(world: WorldRuntime, inventory: InventorySimulationSystem, context: AuthenticatedCommandContext) -> Dictionary:
	return {"inventory": inventory.own_inventory_observation(context, true).value, "production": world.production_observation(context).value, "world_items": inventory.world_inventory_observation(context).value}

func apply(world: WorldRuntime, context: AuthenticatedCommandContext, request: SimulationCommand) -> void:
	request.authenticated_context = context
	check(world.enqueue_command(request).is_success, "real owner command must queue")
	world.get_node("SimulationRunner")._physics_process(1.0 / 60.0)

func run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	world.start_simulation()
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: last_result = result)
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var owner := AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	var collector := AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	var remote := RecordingRemote.new()
	root.add_child(remote)
	var panel := PlayerInventoryPanel.new()
	root.add_child(panel)
	panel.configure(remote)
	var observed: Dictionary = frame(world, inventory, owner)
	panel.observe(observed)
	check(panel._items.item_count == 3 and panel._world_items.item_count == 0, "owned nested contents visible; empty tray has no private items")
	check(panel._inventory_buttons["pickup"].disabled and panel._inventory_buttons["drop"].disabled and panel._inventory_buttons["pickup"].tooltip_text.contains("Select"), "buttons explain absent selection prerequisites")
	check(inventory.own_inventory_observation(collector, true).value["items"].is_empty(), "foreign observer has no private possessions")
	check(not observed["inventory"]["container_ids"].has("body.human-2"), "owned destination excludes foreign body")
	choose(panel._source, "storage.pouch-1")
	panel._fill_items()
	check(panel._items.item_count == 1 and panel._items.get_item_metadata(0)["item_id"] == "crowbar-1", "nested browsing lists direct pouch content only")
	select_item(panel._items, "crowbar-1")
	choose(panel._destination, "body.human-1")
	choose(panel._slot, "hand.right")
	var reordered: Dictionary = observed.duplicate(true)
	reordered["inventory"]["container_ids"].reverse()
	reordered["inventory"]["slot_ids"].reverse()
	reordered["inventory"]["items"].reverse()
	panel.observe(reordered)
	check(panel._picker_id(panel._destination) == "body.human-1" and panel._picker_id(panel._slot) == "hand.right" and panel._selected_id(panel._items) == "crowbar-1", "container hand and item stable IDs survive reordering")
	choose(panel._slot, "back")
	panel._self_action("select_hand")
	check(remote.sent.is_empty() and panel._result.text.contains("configured hand"), "non-hand slot cannot be presented as a selected hand")
	choose(panel._slot, "hand.right")
	panel._self_action("move")
	check(remote.sent.size() == 1 and panel._pending_inventory["source_container_id"] == "storage.pouch-1", "owned nested transfer freezes exact source and destination")
	var pinned: Dictionary = panel._pending_inventory.duplicate(true)
	var waiting: String = panel._result.text
	var missing: Dictionary = reordered.duplicate(true)
	missing["inventory"]["items"].clear()
	missing["inventory"]["container_ids"] = ["storage.pouch-1"]
	panel.observe(missing)
	panel.use_active_tool()
	panel._repair_component()
	panel._self_action("move")
	check(remote.sent.size() == 1 and panel._pending_inventory == pinned and panel._result.text == waiting, "removed item does not imply success or retarget pending move")
	apply(world, owner, remote.sent[0])
	check(last_result.is_success, "real owner accepts valid nested move")
	check(PlayerInventoryPresentation.item(inventory.own_inventory_observation(owner).value, "crowbar-1")["container_id"] == "body.human-1", "canonical owner moves same stable item")
	remote.command_completed.emit(remote.sent[0], last_result)
	check(panel._pending_inventory.is_empty() and panel._result.text.contains("Host accepted"), "matching host acknowledgement resolves pending move")
	panel.observe(missing)
	check(panel._destination.selected == -1, "vanished destination stays unselected across refresh")
	panel.observe(frame(world, inventory, owner))
	check(panel._destination.selected == -1, "returning container requires explicit reselection")
	choose(panel._source, "*")
	panel._fill_items()
	select_item(panel._items, "crowbar-1")
	panel._self_action("move")
	check(remote.sent.size() == 1 and panel._result.text.contains("destination"), "missing destination prevents implicit retarget")
	choose(panel._destination, "body.human-1")
	panel._self_action("move")
	check(remote.sent.size() == 1 and panel._result.text.contains("already"), "same-container move prerequisite is explained")
	select_item(panel._items, "backpack-1")
	choose(panel._destination, "storage.pouch-1")
	panel._self_action("move")
	check(remote.sent.size() == 1 and panel._result.text.contains("Unequip"), "equipped bag uses existing unequip prerequisite")
	select_item(panel._items, "crowbar-1")
	panel._world_action("drop")
	check(remote.sent.size() == 2, "drop queues exact observed owned item")
	apply(world, owner, remote.sent[-1])
	check(last_result.is_success, "real owner accepts cooperative tray drop")
	remote.command_completed.emit(remote.sent[-1], last_result)
	panel.observe(frame(world, inventory, collector))
	check(panel._items.item_count == 0 and panel._world_items.item_count == 1, "collector sees direct tray item and no foreign private descendants")
	choose(panel._destination, "body.human-2")
	select_item(panel._world_items, "crowbar-1")
	panel._inspect_world()
	check(panel._world_details.text.contains("capacity are unavailable"), "tray details express missing capacity and nested contents")
	var roomy: String = world.capture_world_snapshot_json().value
	var tight: Dictionary = JSON.parse_string(roomy)
	for container in tight["systems"]["inventory"]["owner"]["ledger"]["containers"]:
		if container["container_id"] == "body.human-2": container["capacity"]["max_volume_millilitres"] = 1
	var limited_world := WorldRuntime.new()
	root.add_child(limited_world)
	var restored_tight: ServiceResult = limited_world.restore_world_snapshot_json(JSON.stringify(tight))
	check(restored_tight.is_success, "empty receiving root can validly have insufficient capacity: " + restored_tight.message)
	limited_world.command_completed.connect(func(_command: SimulationCommand, result: ServiceResult) -> void: last_result = result)
	limited_world.start_simulation()
	limited_world.get_node("SimulationRunner").set_physics_process(false)
	var limited_inventory: InventorySimulationSystem = limited_world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	panel.observe(frame(limited_world, limited_inventory, collector))
	check(panel._storage_status.text.contains("Host rechecks capacity"), "insufficient observed destination never advertised as guaranteed fit")
	panel._world_action("pickup")
	var full_before: String = JSON.stringify(limited_inventory.capture_snapshot().value["owner"])
	apply(limited_world, collector, remote.sent[-1])
	check(not last_result.is_success and JSON.stringify(limited_inventory.capture_snapshot().value["owner"]) == full_before, "real full destination rejects without changing ownership or receipts")
	remote.command_completed.emit(remote.sent[-1], last_result)
	check(panel._result.text.contains("Host rejected") and panel._pending_world.is_empty(), "actual capacity rejection clears pending without claiming collection")
	limited_world.free()
	panel.observe(frame(world, inventory, collector))
	panel._world_action("pickup")
	apply(world, collector, remote.sent[-1])
	check(last_result.is_success, "real collector owner accepts tray pickup")
	remote.command_completed.emit(remote.sent[-1], last_result)
	panel.observe(frame(world, inventory, collector))
	check(panel._items.item_count == 1 and panel._world_items.item_count == 0 and panel._selected_id(panel._world_items).is_empty(), "accepted handoff visible only from fresh owner observation; stale tray selection clears")
	panel._world_action("pickup")
	check(remote.sent.size() == 4, "removed tray item cannot produce fake successful pickup")
	select_item(panel._items, "crowbar-1")
	remote.reject_queue = true
	panel._world_action("drop")
	check(panel._pending.is_empty() and panel._pending_world.is_empty() and panel._result.text.begins_with("Queue unavailable") and panel._result.text.contains("Code: offline") and not panel._result.text.contains("Next:"), "unavailable queue creates no pending ownership claim")
	remote.reject_queue = false
	panel._world_action("drop")
	var late: SimulationCommand = remote.sent[-1]
	remote.connection_closed.emit("Disconnected")
	remote.command_completed.emit(late, ServiceResult.success())
	check(panel._result.text.contains("outcome is unknown") and panel._pending_inventory.is_empty() and panel._items.item_count == 0, "disconnect clears target and late acknowledgement cannot claim success")
	panel.observe(frame(world, inventory, collector))
	var stale: Dictionary = frame(world, inventory, collector).duplicate(true)
	stale["inventory"]["inventory_revision"] = 0
	panel.observe(stale)
	select_item(panel._items, "crowbar-1")
	panel._world_action("drop")
	var stale_before: String = JSON.stringify(inventory.capture_snapshot().value["owner"])
	apply(world, collector, remote.sent[-1])
	check(not last_result.is_success and JSON.stringify(inventory.capture_snapshot().value["owner"]) == stale_before, "real stale panel request rejects atomically")
	remote.command_completed.emit(remote.sent[-1], last_result)
	check(panel._result.text.contains("Host rejected"), "stale revision rejection stays visible")
	panel.free()
	remote.free()
	world.free()
	print("Inventory tray handoffs: %d failures" % failures)
	quit(1 if failures else 0)
