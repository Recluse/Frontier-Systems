extends SceneTree

class RecordingRemote extends RemoteWorldRuntime:
	var sent: Array[SimulationCommand] = []
	func connect_host(_url: String, _invite: String) -> ServiceResult:
		return ServiceResult.success()
	func enqueue_command(command: SimulationCommand) -> ServiceResult:
		sent.append(command)
		return ServiceResult.success()

class InventoryClient extends FirstPlayableBootstrap:
	func _create_client_remote() -> RemoteWorldRuntime:
		return RecordingRemote.new()

var client: InventoryClient

func settle() -> void:
	for _frame in range(6): await process_frame

func layout() -> void:
	var canonical: String = world.capture_world_snapshot_json().value
	var sent: int = remote.sent.size()
	var selected: String = panel._selected_id(panel._items)
	var slot: String = panel._picker_id(panel._slot)
	var destination: String = panel._picker_id(panel._destination)
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1100, 720), Vector2i(900, 640)]:
		root.size = size
		await settle()
		var scroll := panel.get_parent() as ScrollContainer
		for guidance: Label in [panel._transfer_preview, panel._storage_status]:
			check(guidance.size.x <= scroll.size.x + 1 and guidance.get_line_count() == guidance.get_visible_line_count(), "paid transfer/capacity guidance wraps in actual shell")
			guidance.grab_focus()
			await settle()
			check(scroll.get_global_rect().intersects(guidance.get_global_rect()), "focus reveals paid transfer/capacity guidance")
			var previous: int = scroll.scroll_vertical
			var up := InputEventKey.new()
			up.keycode = KEY_PAGEUP
			up.physical_keycode = KEY_PAGEUP
			up.pressed = true
			root.push_input(up)
			await process_frame
			up = InputEventKey.new()
			up.keycode = KEY_PAGEUP
			up.physical_keycode = KEY_PAGEUP
			root.push_input(up)
			await settle()
			check(scroll.scroll_vertical < previous, "paid transfer guidance keyboard page scroll works")
		check(panel._transfer_preview.text.contains(selected) and panel._transfer_preview.text.contains(destination) and not panel._transfer_preview.text.contains("Slot:"), "paid move preview retains exact targets without equipment slot")
		check(panel._storage_status.text.contains(destination) and not panel._transfer_preview.text.contains("Observed destination"), "paid capacity remains beside destination without repetition")
		check(panel.get_child(panel._slot.get_index() - 1) == panel._equipment, "equipment guidance immediately precedes its slot control")
		check(panel._equipment.size.x <= scroll.size.x + 1 and panel._equipment.get_line_count() == panel._equipment.get_visible_line_count(), "paid equipment guidance wraps in actual shell")
		panel._equipment.grab_focus()
		await settle()
		check(scroll.get_global_rect().intersects(panel._equipment.get_global_rect()), "focus reveals paid equipment guidance")
		panel._slot.grab_focus()
		await settle()
		var event := InputEventKey.new()
		event.keycode = KEY_TAB
		event.physical_keycode = KEY_TAB
		event.pressed = true
		root.push_input(event)
		await process_frame
		event = InputEventKey.new()
		event.keycode = KEY_TAB
		event.physical_keycode = KEY_TAB
		root.push_input(event)
		await settle()
		var focused: Control = root.gui_get_focus_owner()
		check(focused != null and focused != panel._slot and scroll.get_global_rect().encloses(focused.get_global_rect()), "keyboard Tab reveals next enabled equipment control")
		check(panel._selected_id(panel._items) == selected and panel._picker_id(panel._slot) == slot and panel._picker_id(panel._destination) == destination, "focus/scroll retains exact selections")
	check(remote.sent.size() == sent and world.capture_world_snapshot_json().value == canonical, "paid shell layout/focus queues nothing and conserves canonical world")

var failures: int = 0
var sequence: int = 0
var world: WorldRuntime
var inventory: InventorySimulationSystem
var actor: AuthenticatedCommandContext
var last: ServiceResult
var panel: PlayerInventoryPanel
var remote: RecordingRemote

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func frame() -> Dictionary:
	return {"inventory": inventory.own_inventory_observation(actor, true).value}

func step(count: int = 1) -> void:
	for _index in range(count): world.get_node("SimulationRunner")._physics_process(1.0 / 60.0)

func apply(operation: String, payload: Dictionary, production: bool = false, success: bool = true) -> void:
	sequence += 1
	var request: SimulationCommand = ProductionDevelopmentCommand.new() if production else InventoryDevelopmentCommand.new()
	request.command_id = StringName("nested-guidance-%d" % sequence)
	request.operation = operation
	request.payload = payload
	request.authenticated_context = actor
	check(world.enqueue_command(request).is_success, "actual queued " + operation)
	step()
	check(last.is_success == success, operation + ": " + last.message)

func produce(operation: String, payload: Dictionary = {}) -> void:
	payload["expected_revision"] = world.production_observation(actor).value["state_revision"]
	apply(operation, payload, true)

func closure(operation: String) -> void:
	apply(operation, {"container_id": "storage.backpack-1", "expected_revision": frame()["inventory"]["inventory_revision"]})

func transfer(id: String, source: String, destination: String, success: bool = true) -> void:
	apply("self", {"operation": "move", "item_id": id, "source_container_id": source, "destination_container_id": destination, "slot_id": "", "expected_revision": frame()["inventory"]["inventory_revision"]}, false, success)

func equipment(operation: String, id: String = "", source: String = "", destination: String = "", slot: String = "hand.right", success: bool = true) -> void:
	apply("self", {"operation": operation, "item_id": id, "source_container_id": source, "destination_container_id": destination, "slot_id": slot, "expected_revision": frame()["inventory"]["inventory_revision"]}, false, success)
func choose(picker: OptionButton, id: String) -> void:
	for index in range(picker.item_count):
		if picker.get_item_metadata(index) == id:
			picker.select(index)
			picker.item_selected.emit(index)

func select_item(id: String) -> void:
	for index in range(panel._items.item_count):
		if panel._items.get_item_metadata(index)["item_id"] == id:
			panel._items.select(index)
			panel._items.item_selected.emit(index)

func run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: push_error("Paid equipment shell fixture deadline"); quit(1))
	PlayerInputSettings.instance()._reset_map()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "real runtime starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	inventory = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	actor = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	apply("move_to", {"position_millimetres": [0, 0, 0]})
	apply("world", {"operation": "pickup", "item_id": "resource-canister-2", "world_container_id": "world.tray-1", "destination_container_id": "body.human-1", "slot_id": "", "expected_revision": frame()["inventory"]["inventory_revision"]})
	# Produce physical matter through finite extraction, energy-paid processing and printing.
	for _batch in range(2):
		apply("move_to", {"position_millimetres": ProductionSimulationSystem.SOURCE_POSITIONS["deposit.iron"]})
		produce("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-2", "amount_milligrams": 1000000})
		apply("move_to", {"position_millimetres": [0, 0, 0]})
		produce("unload_cargo", {"carrier_id": "resource-canister-2", "material": "ore.iron", "amount_milligrams": 1000000})
		produce("process", {"recipe_id": "refine.iron"})
		step(120)
	produce("process", {"recipe_id": "craft.plate"})
	step(120)
	produce("materialize_plate")
	var production: Dictionary = world.production_observation(actor).value
	check(production["deposits"]["deposit.iron"] == 8000000 and production["store"]["iron"] == 200000 and production["store"]["tailings"] == 800000, "paid finite matter budget")
	if production["components"].is_empty():
		world.free()
		quit(1)
		return
	var plate: String = production["components"][0]
	transfer("crowbar-1", "storage.pouch-1", "body.human-1")
	transfer(plate, "body.human-1", "storage.pouch-1")
	closure("close_container")
	var before: Dictionary = inventory.capture_snapshot().value
	var paid_before: Dictionary = world.production_observation(actor).value.duplicate(true)
	client = InventoryClient.new()
	root.add_child(client)
	client.set_process(false)
	remote = client._remote as RecordingRemote
	remote.set_process(false)
	remote.server_slot = 0
	panel = client._inventory_panel
	client._open_panel(1)
	panel.observe(frame())
	choose(panel._source, "storage.pouch-1")
	select_item(plate)
	choose(panel._destination, "body.human-1")
	check(panel._selected_id(panel._items) == plate and panel._transfer_preview.text.contains("Source physical access: observed closed container storage.backpack-1"), "known paid descendant stays browsable with named source ancestor")
	check(panel._inventory_buttons["move"].disabled and panel._inventory_buttons["move"].tooltip_text.contains("Known contents remain browsable"), "same helper explains observed blocker in prerequisite")
	await layout()
	transfer(plate, "storage.pouch-1", "body.human-1", false)
	check(last.error_code == &"inventory_container_closed" and inventory.capture_snapshot().value["owner"] == before["owner"], "host rejects closed path atomically")
	for field in ["deposits", "store", "cargo", "energy_joules", "state_revision", "components", "structures"]:
		check(world.production_observation(actor).value[field] == paid_before[field], "rejection conserves paid " + field)
	var closed: Dictionary = frame()
	closure("open_container")
	panel.observe(frame())
	check(panel._transfer_preview.text.contains("Source closure path: observed open") and not panel._inventory_buttons["move"].disabled, "fresh reopen removes hint without predicting acceptance")
	transfer(plate, "storage.pouch-1", "body.human-1")
	var after: Dictionary = inventory.capture_snapshot().value
	var expected_items: Array = before["owner"]["ledger"]["items"].duplicate(true)
	for entry in expected_items:
		if entry["item_id"] == plate: entry["container_id"] = "body.human-1"
	check(after["owner"]["ledger"]["items"] == expected_items, "exact paid item IDs and all provenance conserved except intended location")
	check(world.production_observation(actor).value["cargo"] == paid_before["cargo"], "physical transfer preserves exact payload")
	closure("close_container")
	panel.observe(frame())
	choose(panel._source, "*")
	select_item(plate)
	choose(panel._destination, "storage.pouch-1")
	check(panel._transfer_preview.text.contains("Destination physical access: observed closed container storage.backpack-1"), "nested insertion names destination ancestor")
	before = inventory.capture_snapshot().value
	transfer(plate, "body.human-1", "storage.pouch-1", false)
	check(inventory.capture_snapshot().value["owner"] == before["owner"], "closed insertion preserves exact owner")
	closure("open_container")
	transfer(plate, "body.human-1", "storage.pouch-1")
	panel.observe(frame())
	check(remote.sent.is_empty(), "browsing/hints never queue open or retry")
	# Actual paid nested equipment: source and destination must follow the operation.
	closure("close_container")
	panel.observe(frame())
	choose(panel._source, "*")
	select_item(plate)
	choose(panel._slot, "hand.right")
	choose(panel._destination, "storage.pouch-1")
	check(panel._equipment.text.contains("Equip source physical access: observed closed container storage.backpack-1"), "equip names actual paid nested source")
	check(panel._equipment.text.contains("storage destination selection is not used"), "equip target differs from move destination")
	await layout()
	before = inventory.capture_snapshot().value
	equipment("equip", plate, "storage.pouch-1", "", "hand.right", false)
	check(last.error_code == &"inventory_container_closed" and inventory.capture_snapshot().value["owner"] == before["owner"], "closed equip rejection is atomic")
	closure("open_container")
	equipment("equip", plate, "storage.pouch-1")
	closure("close_container")
	panel.observe(frame())
	select_item("crowbar-1")
	check(panel._equipment.text.contains("Unequip slot item: %s · source: body.human-1 · destination: storage.pouch-1" % plate), "unequip uses slot occupant rather than selected crowbar")
	check(panel._equipment.text.contains("Unequip destination physical access: observed closed container storage.backpack-1") and panel._inventory_buttons["unequip"].disabled, "unequip names nested destination blocker")
	before = inventory.capture_snapshot().value
	equipment("unequip", "", "", "storage.pouch-1", "hand.right", false)
	check(last.error_code == &"inventory_container_closed" and inventory.capture_snapshot().value["owner"] == before["owner"], "closed unequip rejection is atomic")
	# Selecting a configured hand does not access the paid item or closed contents.
	var ledger_before: Dictionary = before["owner"]["ledger"].duplicate(true)
	equipment("select_hand")
	check(inventory.capture_snapshot().value["owner"]["ledger"] == ledger_before, "hand selection moves no matter")
	equipment("switch_hand", "", "", "", "")
	check(inventory.capture_snapshot().value["owner"]["ledger"] == ledger_before, "hand switch moves no matter")
	panel.observe(frame())
	check(panel._equipment.text.contains("Neither moves items or opens storage"), "hand selection explanation remains explicit")
	# A closed shell remains externally accessible for same-root equipment changes.
	equipment("unequip", "", "", "body.human-1", "back")
	equipment("equip", "backpack-1", "body.human-1", "", "back")
	check(not PlayerInventoryPresentation.equipment_access(frame()["inventory"], "backpack-1", "back", "body.human-1").contains("Equip source physical access: observed closed"), "closed shell uses exterior source")
	closure("open_container")
	panel.observe(frame())
	choose(panel._slot, "hand.right")
	choose(panel._destination, "body.human-1")
	# Activate the paid-item unequip through the existing focused GUI control.
	var button: Button = panel._inventory_buttons["unequip"]
	button.grab_focus()
	await settle()
	check(not button.disabled and button.has_focus() and (panel.get_parent() as ScrollContainer).get_global_rect().encloses(button.get_global_rect()), "paid unequip button focused and visible")
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	root.push_input(enter)
	await process_frame
	enter = InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.physical_keycode = KEY_ENTER
	root.push_input(enter)
	await settle()
	button.release_focus()
	check(remote.sent.size() == 1 and panel._pending_equipment_observation.contains("slot item " + plate), "submission freezes actual paid slot occupant")
	var pending_payload: Dictionary = remote.sent[0].payload.duplicate(true)
	equipment("unequip", "", "", "body.human-1")
	var unequip_result: ServiceResult = last
	equipment("equip", "crowbar-1", "body.human-1")
	panel.observe(frame())
	check(panel._equipment.text.contains("Unequip slot item: crowbar-1") and panel._equipment.text.contains("Submitted equipment observation · slot hand.right · slot item " + plate), "fresh slot occupant does not replace submitted identity")
	check(remote.sent[0].payload == pending_payload and not pending_payload.has("observed_slot_item"), "presentation metadata never enters command payload")
	await layout()
	check(remote.sent[0].payload == pending_payload and panel._pending_equipment_observation.contains("slot item " + plate), "narrow focus preserves frozen paid submission identity")
	remote.command_completed.emit(remote.sent[0], unequip_result)
	check(panel._pending_equipment_observation.is_empty() and panel._pending.is_empty() and panel._result.text.contains("slot item " + plate), "matching receipt retains submitted identity in feedback")
	await settle()
	check((panel.get_parent() as ScrollContainer).get_global_rect().encloses(panel._result.get_global_rect()), "complete paid receipt revealed in narrow shell")
	for field in ["deposits", "store", "cargo", "energy_joules", "state_revision", "components", "structures"]:
		check(world.production_observation(actor).value[field] == paid_before[field], "equipment conserves paid " + field)
	# Return the exact paid item to its nested location for freshness checks below.
	equipment("unequip", "", "", "body.human-1")
	transfer(plate, "body.human-1", "storage.pouch-1")
	panel.observe(frame())
	select_item(plate)
	choose(panel._destination, "storage.pouch-1")
	# Earlier closed state must not replace current closure evidence or stable selections.
	panel.observe(closed)
	check(panel._equipment.text.contains("Equip source physical access: unknown") and panel._transfer_preview.text.contains("Source physical access: unknown") and not panel._transfer_preview.text.contains("observed closed container"), "older revision fences transfer closure claims")
	panel.observe(frame())
	var malformed: Dictionary = frame()["inventory"].duplicate(true)
	for container in malformed["container_records"]:
		if container["container_id"] == "storage.backpack-1": container["is_open"] = "true"
	check(PlayerInventoryPresentation.observed_access(malformed, "storage.pouch-1")["state"] == "unknown", "malformed boolean never means open")
	var missing: Dictionary = frame()["inventory"].duplicate(true)
	missing["container_records"].clear()
	check(PlayerInventoryPresentation.observed_access(missing, "storage.pouch-1")["state"] == "unknown", "missing path never means open")
	var incomplete: Dictionary = frame()["inventory"].duplicate(true)
	for container in incomplete["container_records"]:
		if container["container_id"] == "body.human-1": container.erase("owner_item_id")
	check(PlayerInventoryPresentation.observed_access(incomplete, "storage.pouch-1")["state"] == "unknown", "missing root ownership never means open")
	var cycle: Dictionary = frame()["inventory"].duplicate(true)
	for entry in cycle["items"]:
		if entry["item_id"] == "backpack-1": entry["container_id"] = "storage.pouch-1"
	check(PlayerInventoryPresentation.observed_access(cycle, "storage.pouch-1")["state"] == "unknown", "bounded cyclic observation unknown")
	check(PlayerInventoryPresentation.transfer_preview(closed["inventory"], "backpack-1", "body.human-1", "").contains("Source closure path: observed open"), "closed shell exterior does not imply accessing its contents")
	var partial: Dictionary = frame()
	for container in partial["inventory"]["container_records"]:
		if container["container_id"] == "storage.backpack-1": container.erase("is_open")
	panel.observe(partial)
	check(panel._transfer_preview.text.contains("Source physical access: unknown"), "missing ancestor closure means unknown")
	var legacy: Dictionary = frame()
	legacy["inventory"]["schema_version"] = 3
	panel.observe(legacy)
	check(panel._transfer_preview.text.contains("Source physical access: unknown"), "legacy never means open")
	panel.observe(frame())
	while Time.get_ticks_msec() - panel._equipment_observed_at <= panel.EQUIPMENT_OBSERVATION_TIMEOUT_MSEC + 100:
		await process_frame
	panel._process(0.0)
	check(panel._equipment.text.contains("Equip source physical access: unknown") and panel._transfer_preview.text.contains("Source physical access: unknown"), "aged transfer hint refreshes through existing freshness fence: now=%s at=%s empty=%s text=%s" % [Time.get_ticks_msec(), panel._equipment_observed_at, panel._equipment_record.is_empty(), panel._transfer_preview.text])
	panel.observe({})
	check(panel._transfer_preview.text.is_empty(), "unavailable inventory removes disposable hints")
	check(PlayerInventoryPresentation.access_hint({}, "retained.id", "Source").contains("unknown"), "unavailable closure honest")
	client.free()
	PlayerInputSettings.instance().release_all()
	world.free()
	print("Owned nested access guidance: %d failures" % failures)
	quit(0 if failures == 0 else 1)
