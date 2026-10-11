extends "res://tests/godot/player_inventory_components_test.gd"

## Actual panel and real finite-resource commands; no ports or services.
func run() -> void:
	world = WorldRuntime.new()
	world.resource_carriers_enabled = true
	root.add_child(world)
	check(world.start_simulation().is_success, "fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-actor", world.world_id, world.region_id)
	remote = RecordingRemote.new()
	root.add_child(remote)
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(440, 320)
	scroll.follow_focus = true
	root.add_child(scroll)
	panel = PlayerInventoryPanel.new()
	scroll.add_child(panel)
	panel.configure(remote)
	panel.observe(frame())
	check(panel._picker_id(panel._carrier).is_empty(), "receiver requires explicit selection")
	choose(panel._carrier, "resource-canister-1")
	panel._update_buttons()
	check(panel._work_targets.text.contains("Observed receiving contents: empty") and panel._work_targets.text.contains("1000000 mg (shell and payload included)"), "empty payload distinguished from shell mass")
	check(panel._work_targets.text.contains("Payload capacity unavailable"), "no invented capacity quote")
	move(ProductionSimulationSystem.SOURCE_POSITIONS["deposit.iron"])
	command("extract", {"deposit_id": "deposit.iron", "carrier_id": "resource-canister-1", "amount_milligrams": 1000000})
	panel.observe(frame())
	check(panel._work_targets.text.contains("ore.iron 1.000 kg") and panel._work_targets.text.contains("2000000 mg"), "real extraction changes observed payload and loaded mass")
	var before: Dictionary = frame()
	var saved: String = world.capture_world_snapshot_json().value
	var sent: int = remote.sent.size()
	var missing: Dictionary = before.duplicate(true)
	missing["production"]["cargo"].erase("resource-canister-1")
	panel.observe(missing)
	check(panel._picker_id(panel._carrier) == "resource-canister-1" and panel._carrier.is_item_disabled(panel._carrier.selected), "removed receiver retained unavailable without retargeting")
	check(panel._work_targets.text.contains("Receiving contents and loaded mass unavailable"), "removed payload cannot appear empty")
	panel._use_tool()
	check(remote.sent.size() == sent, "missing receiver cannot submit")
	var legacy: Dictionary = before.duplicate(true)
	legacy["inventory"].erase("item_details")
	panel.observe(legacy)
	check(panel._work_targets.text.contains("loaded mass: unavailable") and panel._work_targets.text.contains("ore.iron 1.000 kg"), "missing mass does not erase observed contents")
	var missing_production: Dictionary = before.duplicate(true)
	missing_production.erase("production")
	panel.observe(missing_production)
	check(panel._work_status.text.contains("unavailable"), "missing production cannot claim no reserved work")
	panel.observe({})
	check(panel._work_targets.text.contains("unavailable"), "missing frame clears claims")
	panel.observe(before)
	check(world.capture_world_snapshot_json().value == saved and remote.sent.size() == sent, "rendering conserves canonical state and submits nothing")
	# Equip the real extractor for existing sustained work commands.
	for operation: String in ["equip", "select_hand"]:
		var request := InventoryDevelopmentCommand.new()
		request.command_id = StringName("canister-" + operation)
		request.operation = "self"
		request.payload = {"operation": operation, "expected_revision": frame()["inventory"]["inventory_revision"], "slot_id": "hand.left", "item_id": "", "source_container_id": "", "destination_container_id": ""}
		if operation == "equip": request.payload.merge({"item_id": "extractor-1", "source_container_id": "storage.backpack-2"}, true)
		apply(request)
		check(last.is_success, "equip fixture " + operation)
	panel.observe(frame())
	choose(panel._deposit, "deposit.iron")
	choose(panel._carrier, "resource-canister-1")
	panel._work_cycles.value = 1
	panel._sustained_action("start_tool_extract")
	var request: SimulationCommand = remote.sent[-1]
	var pinned: Dictionary = panel._pending_component.duplicate(true)
	# Change intended selection while receipt is pending; frozen payload remains exact.
	choose(panel._deposit, "deposit.ice")
	panel._carrier.select(0)
	panel._update_buttons()
	check(panel._pending_component == pinned and request.payload["carrier_id"] == "resource-canister-1", "selection cannot retarget pending extraction")
	apply(request)
	check(last.is_success, "real sustained reservation accepted")
	remote.command_completed.emit(request, last)
	panel.observe(frame())
	check(panel._work_targets.text.contains("Observed reserved carrier_id: resource-canister-1") and panel._work_status.text.contains("0 completed, 1 reserved"), "reservation separate from intended empty receiver and completion")
	for _tick in range(60): step()
	panel.observe(frame())
	choose(panel._carrier, "resource-canister-1")
	panel._update_buttons()
	check(panel._work_targets.text.contains("ore.iron 2.000 kg") and panel._work_targets.text.contains("3000000 mg"), "real completed cycle updates receiver")
	choose(panel._deposit, "deposit.iron")
	panel._use_tool()
	request = remote.sent[-1]
	before = frame()
	apply(request)
	check(not last.is_success and frame()["production"]["cargo"] == before["production"]["cargo"] and frame()["production"]["deposits"] == before["production"]["deposits"], "real full-canister rejection conserves contents and source")
	remote.command_completed.emit(request, last)
	check(panel._result.text.contains(last.message) and panel._result.text.contains("resource-canister-1"), "rejection retains reason and exact receiver")
	panel._work_targets.grab_focus()
	await process_frame
	await process_frame
	check(panel._work_targets.has_focus() and panel._work_targets.focus_mode == Control.FOCUS_ALL and scroll.get_v_scroll_bar().max_value > scroll.size.y, "actual guidance remains focusable and scrollable")
	var down := InputEventAction.new()
	down.action = &"ui_page_down"
	down.pressed = true
	scroll.scroll_vertical = 0
	panel._guidance_input(down, panel._work_targets)
	check(scroll.scroll_vertical > 0, "focused guidance page-down actually scrolls")
	move([0, 0, 0])
	command("unload_cargo", {"carrier_id": "resource-canister-1", "material": "ore.iron", "amount_milligrams": 1000000})
	panel.observe(frame())
	check(panel._work_targets.text.contains("ore.iron 1.000 kg") and panel._work_targets.text.contains("2000000 mg"), "real unloading refreshes observed receiver")
	var drop := InventoryDevelopmentCommand.new()
	drop.command_id = &"canister-feedback-drop"
	drop.operation = "world"
	drop.payload = {"operation": "drop", "item_id": "resource-canister-1", "world_container_id": "world.tray-1", "destination_container_id": "", "slot_id": "", "expected_revision": frame()["inventory"]["inventory_revision"]}
	apply(drop)
	check(last.is_success, "real canister drop")
	panel.observe(frame())
	check(panel._picker_id(panel._carrier) == "resource-canister-1" and panel._work_targets.text.contains("Receiving contents and loaded mass unavailable"), "real ownership removal clears payload without retargeting")
	sent = remote.sent.size()
	remote.connection_closed.emit("Disconnected")
	check(panel._work_targets.text.contains("unavailable") and panel._pending_component.is_empty() and panel._carrier.item_count == 0, "disconnect removes claims and selections")
	remote.command_completed.emit(request, ServiceResult.success())
	check(panel._result.text.contains("outcome is unknown") and remote.sent.size() == sent, "late receipt cannot claim success or retry")
	for _frame in range(5): await process_frame
	scroll.free()
	remote.free()
	world.free()
	if failures == 0: print("Canister feedback: real extraction, reserved/completed cycle, rejection, missing data, conservation and focus/scroll passed.")
	quit(0 if failures == 0 else 1)


