extends "res://tests/godot/client_inventory_shell_test.gd"

## Detached long-ID observations in the real client shell; no domain/network claim.
var observed: Dictionary
var ids: Dictionary = {}
var capture_stage: String = "preview"

func key(code: Key, shift: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.shift_pressed = shift
	root.push_input(event)
	await settle()

func bounded(control: Control, width: float) -> void:
	if not control.is_visible_in_tree(): return
	check(control.size.x <= width + 1, "shell width bounded: " + control.get_class())
	if control is Label:
		check(control.get_line_count() == control.get_visible_line_count(), "all wrapped lines retained")
	for child in control.get_children():
		if child is Control: bounded(child, width)

func selections() -> void:
	choose(panel._source, ids["storage.pouch-1"])
	panel._fill_items()
	select_tool(ids["crowbar-1"])
	choose(panel._destination, ids["body.human-1"])
	choose(panel._slot, ids["hand.right"])
	choose(panel._world_root, ids["world.tray-1"])
	panel._fill_world_items()
	panel._world_items.select(0)
	panel._inspect_world()
	panel._update_buttons()

func snap(name: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://var/ci/inventory-transfer-layout-render")
	check(root.get_texture().get_image().save_png("res://var/ci/inventory-transfer-layout-render/" + capture_stage + "-" + name + ".png") == OK, "internal ordinary shell capture")

func readable(label: Label) -> void:
	var scroll := panel.get_parent() as ScrollContainer
	check(label.focus_mode == Control.FOCUS_ALL, "guidance keyboard-focusable")
	label.grab_focus()
	await settle()
	var bottom: float = label.get_global_rect().end.y
	check(bottom <= scroll.get_global_rect().end.y + 1, "focus reveals guidance end")
	# A long receipt can exceed the viewport; keyboard scrolling must reach its start.
	var previous: int = scroll.scroll_vertical
	await key(KEY_UP)
	check(scroll.scroll_vertical < previous, "focused guidance scrolls up")
	for _step in range(60):
		if label.get_global_rect().position.y >= scroll.get_global_rect().position.y: break
		await key(KEY_UP)
	check(label.get_global_rect().position.y >= scroll.get_global_rect().position.y, "guidance start reachable")
	await snap("layout-%d-%s-start" % [root.size.x, label.get_index()])
	previous = scroll.scroll_vertical
	await key(KEY_PAGEDOWN)
	check(scroll.scroll_vertical > previous, "focused guidance page scrolls down")
	await key(KEY_PAGEUP)
	check(scroll.scroll_vertical <= previous, "focused guidance page scrolls up")
	for _step in range(60):
		if label.get_global_rect().end.y <= scroll.get_global_rect().end.y: break
		await key(KEY_DOWN)
	check(label.get_global_rect().end.y <= scroll.get_global_rect().end.y, "guidance end reachable after reading start")
	await snap("layout-%d-%s-end" % [root.size.x, label.get_index()])

func run() -> void:
	create_timer(60.0).timeout.connect(func() -> void: push_error("Transfer layout deadline"); quit(1))
	capture = OS.get_cmdline_user_args().has("--capture-inventory")
	PlayerInputSettings.instance()._reset_map()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	world = WorldRuntime.new()
	root.add_child(world)
	check(world.start_simulation().is_success, "canonical fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	context = AuthenticatedCommandContext.for_local_development(&"local-inventory-target", world.world_id, world.region_id)
	client = InventoryClient.new()
	root.add_child(client)
	client.set_process(false)
	remote = client._remote
	remote.set_process(false)
	remote.server_slot = 0
	observe_shell()
	panel = client._inventory_panel
	client._tabs.current_tab = 1
	var canonical: String = world.capture_world_snapshot_json().value
	var encoded: String = JSON.stringify(frame())
	for id: String in ["storage.pouch-1", "storage.backpack-1", "body.human-1", "crowbar-1", "hand.right", "world.tray-1"]:
		ids[id] = id + "x".repeat(128 - id.length())
		check(ControlContractValidation.is_id(ids[id]), "fixture ID fits existing contract")
		encoded = encoded.replace('"' + id + '"', '"' + ids[id] + '"')
	observed = JSON.parse_string(encoded)
	observed["world_items"]["containers"][0]["items"] = [{"item_id": "tray-item-" + "x".repeat(118), "definition_id": "item.crowbar.prototype", "container_id": ids["world.tray-1"]}]
	var input_before: String = JSON.stringify(observed)
	for viewport_size: Vector2i in [Vector2i(1920, 1080), Vector2i(1100, 720)]:
		capture_stage = "preview"
		root.size = viewport_size
		(client._tabs.get_parent() as HSplitContainer).split_offset = 420 if viewport_size.x == 1100 else 540
		panel.observe(observed)
		selections()
		await settle()
		var scroll := panel.get_parent() as ScrollContainer
		print("Layout viewport %s; actual sidebar %.0f; inventory pane %.0f x %.0f" % [viewport_size, client._tabs.size.x, scroll.size.x, scroll.size.y])
		check(client._tabs.get_global_rect().end.x <= root.size.x, "shell fits supported viewport")
		bounded(panel, scroll.size.x)
		check(panel._transfer_preview.text.contains(ids["crowbar-1"]) and panel._transfer_preview.text.contains(ids["storage.pouch-1"]) and panel._transfer_preview.text.contains(ids["body.human-1"]) and not panel._transfer_preview.text.contains(ids["hand.right"]), "complete move IDs exclude the unused equipment slot")
		check(panel._storage_status.text.contains(ids["body.human-1"]) and panel._storage_status.text.contains("Host rechecks"), "capacity guidance retains destination and host decision")
		await readable(panel._transfer_preview)
		await readable(panel._storage_status)
		await readable(panel._world_transfer_preview)
		for operation: String in ["equip", "move", "pickup", "drop"]:
			var button: Button = panel._inventory_buttons[operation]
			check(not button.disabled, operation + " enabled")
			button.grab_focus()
			await settle()
			check(scroll.get_global_rect().encloses(button.get_global_rect()), operation + " fully revealed by focus")
			await key(KEY_TAB)
			await key(KEY_TAB, true)
			check(button.has_focus(), operation + " reachable in bidirectional Tab traversal")
		var request: SimulationCommand = await activate("move")
		var pinned: Dictionary = panel._pending_inventory.duplicate(true)
		var waiting: String = panel._result.text
		await settle()
		check(waiting.contains(ids["crowbar-1"]) and waiting.contains(ids["storage.pouch-1"]) and waiting.contains(ids["body.human-1"]), "pending retains complete target IDs")
		for operation: String in ["equip", "move", "pickup", "drop"]: check(panel._inventory_buttons[operation].disabled, "pending freezes " + operation)
		await snap("layout-%d-pending" % root.size.x)
		panel.observe(observed)
		var unrelated := InventoryDevelopmentCommand.new()
		unrelated.command_id = &"unrelated-layout-receipt"
		remote.command_completed.emit(unrelated, ServiceResult.failure(&"fixture", "Unrelated"))
		check(panel._pending_inventory == pinned and panel._result.text == waiting and request.payload == pinned, "exact pending isolated from observation/unrelated receipt")
		var guidance: String = ("Capacity changed for " + ids["body.human-1"] + ". Refresh the observed destination before explicitly retrying. ").repeat(8)
		remote.command_completed.emit(request, ServiceResult.failure(&"inventory_capacity_exceeded", guidance))
		await settle()
		check(panel._pending.is_empty() and panel._result.text.contains(guidance), "complete matching failure retained")
		bounded(panel, scroll.size.x)
		capture_stage = "rejected" if panel._result.text.contains("Host rejected") else "disconnected"
		await readable(panel._result)
		# Transport completes requests before emitting connection_closed.
		selections()
		request = await activate("move")
		remote.command_completed.emit(request, ServiceResult.failure(&"remote_disconnected", "Host connection closed"))
		var recovery: String = panel._result.text
		remote.connection_closed.emit("Layout fixture disconnect")
		check(panel._result.text == recovery and panel._pending.is_empty() and panel._pending_inventory.is_empty(), "completion-first disconnect keeps display context but clears live request")
		for target: String in [String(request.command_id), ids["crowbar-1"], ids["storage.pouch-1"], ids["body.human-1"], "revision " + str(int(request.payload["expected_revision"]))]:
			check(recovery.contains(target), "unknown Move retains exact target: " + target)
		check(recovery.contains("outcome is unknown") and recovery.contains("no automatic retry") and not recovery.contains("Waiting for"), "recovery is uncertain historical context, not pending work")
		remote.command_completed.emit(request, ServiceResult.success())
		check(panel._result.text == recovery, "late Move success cannot rewrite uncertainty")
		panel.observe(observed)
		selections()
		check(panel._result.text == recovery, "fresh same-revision observation and selection changes keep historical context")
		await settle()
		bounded(panel, scroll.size.x)
		capture_stage = "disconnected"
		await readable(panel._result)
		# Also cover connection_closed arriving before remote completion.
		var fresh_move: SimulationCommand = await activate("move")
		check(fresh_move.command_id != request.command_id and panel._move_recovery_text.is_empty(), "explicit new submission clears historical context and allocates new identity")
		remote.connection_closed.emit("Signal-first disconnect")
		var second_recovery: String = panel._result.text
		remote.command_completed.emit(fresh_move, ServiceResult.failure(&"remote_disconnected", "Host connection closed"))
		check(panel._result.text == second_recovery and second_recovery.contains(String(fresh_move.command_id)), "signal-first disconnect keeps fresh exact Move identity")
		panel.observe(observed)
		var removed: Dictionary = observed.duplicate(true)
		removed["inventory"]["items"].clear()
		removed["inventory"]["container_ids"].clear()
		removed["inventory"]["slot_ids"].clear()
		removed["world_items"]["containers"].clear()
		panel.observe(removed)
		await settle()
		check(panel._transfer_preview.text.contains("Item/source: unavailable") and panel._destination.selected == -1 and panel._slot.selected == -1, "removed selections never retarget")
		for operation: String in ["equip", "move", "pickup", "drop"]: check(panel._inventory_buttons[operation].disabled, "removed targets disable " + operation)
		panel.observe(observed)
		selections()
		request = await activate("pickup")
		var world_pending: Dictionary = panel._pending_world.duplicate(true)
		remote.command_completed.emit(unrelated, ServiceResult.success())
		check(panel._pending_world == world_pending and request.payload == world_pending, "world pending receipt isolated")
		remote.connection_closed.emit("Layout fixture disconnect")
		await settle()
		check(panel._pending.is_empty() and panel._pending_world.is_empty() and panel._transfer_preview.text.is_empty() and panel._world_transfer_preview.text.is_empty(), "disconnect clears targets and previews")
		check(panel._result.text.contains("outcome is unknown"), "disconnect retains uncertainty guidance")
		capture_stage = "rejected" if panel._result.text.contains("Host rejected") else "disconnected"
		await readable(panel._result)
	check(JSON.stringify(observed) == input_before and world.capture_world_snapshot_json().value == canonical, "layout/input/receipts preserve observed input and canonical state")
	client.free()
	world.free()
	PlayerInputSettings.instance().release_all()
	print("Transfer layout actual shell: %d failures; detached observations, injected keys, no sockets/human acceptance" % failures)
	quit(1 if failures else 0)