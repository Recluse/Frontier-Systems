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

func choose(picker: OptionButton, id: String) -> void:
	picker.select(-1)
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == id:
			picker.select(index)
			picker.item_selected.emit(index)

func select_item(list: ItemList, id: String) -> void:
	list.deselect_all()
	for index in range(list.item_count):
		if list.get_item_metadata(index)["item_id"] == id:
			list.select(index)
			list.item_selected.emit(index)

func run() -> void:
	var world := WorldRuntime.new()
	root.add_child(world)
	world.start_simulation()
	world.get_node("SimulationRunner").set_physics_process(false)
	var owner := AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	var inventory: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var observed: Dictionary = {"inventory": inventory.own_inventory_observation(owner, true).value, "production": world.production_observation(owner).value, "world_items": inventory.world_inventory_observation(owner).value}
	var original: String = JSON.stringify(observed)
	var before: String = world.capture_world_snapshot_json().value
	var remote := RecordingRemote.new()
	root.add_child(remote)
	var panel := PlayerInventoryPanel.new()
	var scroll := ScrollContainer.new()
	root.add_child(scroll)
	scroll.add_child(panel)
	panel.configure(remote)
	panel.observe(observed)
	choose(panel._source, "storage.pouch-1")
	select_item(panel._items, "crowbar-1")
	choose(panel._destination, "body.human-1")
	choose(panel._slot, "hand.right")
	check(panel._transfer_preview.text.contains("Item: crowbar-1 · source: storage.pouch-1") and panel._transfer_preview.text.contains("Destination: body.human-1") and not panel._transfer_preview.text.contains("Slot:"), "move identifies actual item/source/destination without unrelated equipment slot")
	choose(panel._destination, "storage.backpack-1")
	check(panel._transfer_preview.text.contains("Destination: storage.backpack-1") and panel._storage_status.text.contains("Observed destination storage.backpack-1") and not panel._transfer_preview.text.contains("Observed destination"), "destination selection refreshes observed load/capacity")
	choose(panel._world_root, "world.tray-1")
	check(panel._world_transfer_preview.text.contains("Item: crowbar-1 · source: storage.pouch-1 · tray destination: world.tray-1"), "drop summary distinguishes world tray from owned move destination")
	var changed_tray: Dictionary = observed.duplicate(true)
	changed_tray["world_items"]["containers"][0]["container_id"] = "fixture.tray-2"
	panel.observe(changed_tray)
	choose(panel._world_root, "fixture.tray-2")
	check(panel._world_transfer_preview.text.contains("tray destination: fixture.tray-2"), "host-observed tray destination changes refresh drop target")
	panel.observe(observed)
	choose(panel._source, "*")
	select_item(panel._items, "backpack-1")
	choose(panel._slot, "back")
	var loaded_mass: int = 0
	for detail in observed["inventory"]["item_details"]:
		if detail["item"]["item_id"] == "backpack-1": loaded_mass = detail["mass_milligrams"]
	check(loaded_mass > 0 and panel._transfer_preview.text.contains("Observed loaded mass: %.2f kg" % [float(loaded_mass) / 1000000.0]) and panel._equipment.text.contains("backpack-1") and not panel._transfer_preview.text.contains("Observed slot item"), "move quotes loaded mass while equipment retains its observed occupant")
	# Detached host-observation fixture: deliberately disagree with separate cargo
	# so the preview must quote item_details once, never add or reconstruct payload.
	var payload: Dictionary = observed.duplicate(true)
	for detail in payload["inventory"]["item_details"]:
		if detail["item"]["item_id"] == "backpack-1": detail["mass_milligrams"] = 12345000
	payload["production"]["cargo"]["backpack-1"] = {"ore.iron": 9000000}
	panel.observe(payload)
	check(panel._transfer_preview.text.contains("Observed loaded mass: 12.35 kg"), "nested loaded payload is quoted once without adding cargo")
	var missing_details: Dictionary = observed.duplicate(true)
	missing_details["inventory"].erase("item_details")
	missing_details["inventory"].erase("container_records")
	panel.observe(missing_details)
	check(panel._transfer_preview.text.contains("Loaded mass: unavailable") and panel._storage_status.text.contains("capacity is unavailable"), "older observation reports missing mass/capacity")
	var moved: Dictionary = observed.duplicate(true)
	for entry in moved["inventory"]["items"]:
		if entry["item_id"] == "backpack-1": entry["container_id"] = "body.human-1"
	moved["inventory"]["inventory_revision"] += 1
	panel.observe(moved)
	check(panel._transfer_preview.text.contains("source: body.human-1"), "fresh host source replaces earlier observed source")
	var removed: Dictionary = observed.duplicate(true)
	removed["inventory"]["items"].clear()
	removed["inventory"]["container_ids"].clear()
	removed["inventory"]["slot_ids"].clear()
	panel.observe(removed)
	check(panel._transfer_preview.text.contains("Item/source: unavailable") and panel._transfer_preview.text.contains("Destination: unavailable") and not panel._transfer_preview.text.contains("Slot:") and not panel._transfer_preview.text.contains("12.35"), "removed selection cannot leave stale detail or silently retarget")
	panel.observe(observed)
	check(panel._destination.selected == -1 and panel._slot.selected == -1 and panel._selected_id(panel._items).is_empty(), "returning records require explicit reselection")
	var tray: Dictionary = observed.duplicate(true)
	tray["world_items"]["containers"][0]["items"] = [{"item_id": "observed-tray-item", "definition_id": "item.crowbar.prototype", "container_id": "world.tray-1"}]
	panel.observe(tray)
	choose(panel._world_root, "world.tray-1")
	choose(panel._destination, "body.human-1")
	select_item(panel._world_items, "observed-tray-item")
	check(panel._world_transfer_preview.text.contains("source: world.tray-1") and panel._world_transfer_preview.text.contains("Loaded mass: unavailable") and panel._world_transfer_preview.text.contains("Destination: body.human-1"), "nearby pickup summary quotes source and marks hidden loaded mass unavailable")
	panel.observe(observed)
	check(not panel._world_transfer_preview.text.contains("observed-tray-item"), "removed tray item clears preview")
	check(remote.sent.is_empty() and panel._pending.is_empty(), "selection and observation never queue commands or retry")
	check(JSON.stringify(observed) == original and world.capture_world_snapshot_json().value == before, "presentation preserves input observation and complete canonical snapshot")
	remote.connection_closed.emit("Disconnected")
	check(panel._transfer_preview.text.is_empty() and panel._world_transfer_preview.text.is_empty(), "disconnect clears disposable preview")
	scroll.free()
	remote.free()
	world.free()
	print("Inventory transfer preview: %d failures" % failures)
	quit(1 if failures else 0)
