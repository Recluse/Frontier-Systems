extends "res://tests/godot/client_inventory_shell_test.gd"

## Actual shell and paid inventory commands, with an injected socket-free remote.
func shown(fragment: String) -> void:
	check(panel._active_tool.text.contains(fragment) and panel._equipment.text.contains(fragment), "both equipment summaries: " + fragment)


func snap(name: String) -> void:
	if not capture: return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://var/ci/active-hand-tool-render")
	check(root.get_texture().get_image().save_png("res://var/ci/active-hand-tool-render/" + name + ".png") == OK, "internal shell capture")


func run() -> void:
	create_timer(40.0).timeout.connect(func() -> void: push_error("Active equipment fixture deadline"); quit(1))
	capture = OS.get_cmdline_user_args().has("--capture-inventory")
	PlayerInputSettings.instance()._reset_map()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1100, 720)
	world = WorldRuntime.new()
	root.add_child(world)
	check(world.start_simulation().is_success, "canonical fixture starts")
	world.get_node("SimulationRunner").set_physics_process(false)
	world.command_completed.connect(func(_request: SimulationCommand, result: ServiceResult) -> void: last = result)
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
	await settle()
	choose(panel._source, "storage.pouch-1")
	panel._fill_items()
	select_tool("crowbar-1")
	choose(panel._slot, "hand.right")
	panel._update_buttons()
	shown("Active hand: hand.left")
	shown("Active hand item: empty")
	shown("Selected inventory item: crowbar-1")
	shown("Selected equipment slot: hand.right")
	await accepted("equip")
	shown("Active hand item: empty")
	var before: String = world.capture_world_snapshot_json().value
	var request: SimulationCommand = await activate("select_hand")
	shown("outcome unconfirmed")
	shown("Active hand: hand.left")
	check(world.capture_world_snapshot_json().value == before, "queued hand selection changes no canonical state")
	var pinned: Dictionary = panel._pending_inventory.duplicate(true)
	var unrelated := InventoryDevelopmentCommand.new()
	unrelated.command_id = &"unrelated-hand-receipt"
	remote.command_completed.emit(unrelated, ServiceResult.success())
	check(panel._pending_inventory == pinned, "unrelated receipt leaves hand command pending")
	apply(request)
	check(last.is_success, "real select hand accepts")
	remote.command_completed.emit(request, last)
	shown("Active hand: hand.left")
	check(panel._pending.is_empty(), "receipt clears only exact pending request; does not synthesize observation")
	observe_shell()
	shown("Active hand: hand.right")
	shown("Active hand item: Crowbar · crowbar-1")
	choose(panel._source, "body.human-1")
	panel._fill_items()
	select_tool("backpack-1")
	choose(panel._slot, "hand.left")
	panel._update_buttons()
	shown("Selected inventory item: backpack-1")
	shown("Selected equipment slot: hand.left")
	shown("Active hand item: Crowbar · crowbar-1")
	await accepted("switch_hand")
	shown("Active hand: hand.left")
	shown("Active hand item: empty")
	await accepted("switch_hand")
	shown("Active hand: hand.right")
	# Reject the queued hand change through a real intervening revision change.
	request = await activate("switch_hand")
	observe_shell()
	shown("outcome unconfirmed")
	check(not panel._pending.is_empty(), "fresh observation cannot confirm pending equipment command")
	var competing := InventoryDevelopmentCommand.new()
	competing.command_id = &"fixture-intervening-switch"
	competing.operation = "self"
	competing.payload = {"operation": "switch_hand", "item_id": "", "source_container_id": "", "destination_container_id": "", "slot_id": "", "expected_revision": frame()["inventory"]["inventory_revision"]}
	apply(competing)
	check(last.is_success, "intervening command accepted")
	var owner: InventorySimulationSystem = world.get_simulation_system(InventorySimulationSystem.SYSTEM_ID)
	var inventory_before: String = JSON.stringify(owner.capture_snapshot().value["owner"])
	apply(request)
	check(not last.is_success and JSON.stringify(owner.capture_snapshot().value["owner"]) == inventory_before, "stale hand change rejects without canonical inventory mutation")
	remote.command_completed.emit(request, last)
	shown("Active hand: hand.right")
	check(panel._result.text.contains("Host rejected"), "matching rejection remains visible")
	observe_shell()
	shown("Active hand: hand.left")
	await accepted("switch_hand")
	shown("Active hand item: Crowbar · crowbar-1")
	# Detached absence/freshness/layout observations never affect the canonical owner.
	before = world.capture_world_snapshot_json().value
	var sent: int = remote.sent.size()
	var observed: Dictionary = frame()
	observed["tick_number"] = 100
	var encoded: String = JSON.stringify(observed)
	panel.observe(observed)
	var removed: Dictionary = observed.duplicate(true)
	removed["tick_number"] = 101
	removed["inventory"]["items"] = removed["inventory"]["items"].filter(func(entry: Dictionary) -> bool: return entry["item_id"] != "crowbar-1")
	panel.observe(removed)
	shown("Active hand item: unavailable")
	removed["inventory"].erase("active_hand_slot_id")
	panel.observe(removed)
	shown("Active hand/item: unavailable")
	panel.observe({})
	shown("Active hand/item: unavailable")
	observed["tick_number"] = 102
	panel.observe(observed)
	shown("Active hand item: Crowbar · crowbar-1")
	var older: Dictionary = observed.duplicate(true)
	older["tick_number"] = 101
	panel.observe(older)
	shown("Active hand/item: unavailable")
	observed["tick_number"] = 103
	older = observed.duplicate(true)
	older["inventory"]["inventory_revision"] -= 1
	panel.observe(older)
	shown("Active hand/item: unavailable")
	panel.observe(observed)
	await create_timer(5.1).timeout
	shown("Active hand/item: unavailable")
	panel.observe(observed)
	shown("Active hand/item: unavailable")
	observed["tick_number"] = 104
	panel.observe(observed)
	shown("Active hand item: Crowbar · crowbar-1")
	# Long full IDs at desktop and narrow actual-shell sizes must wrap and scroll.
	var long_id: String = "crowbar-1" + "x".repeat(119)
	var layout: Dictionary = observed.duplicate(true)
	layout["tick_number"] = 105
	for entry in layout["inventory"]["items"]:
		if entry["item_id"] == "crowbar-1": entry["item_id"] = long_id
	for binding in layout["inventory"]["equipped"]:
		if binding["item_id"] == "crowbar-1": binding["item_id"] = long_id
	panel.observe(layout)
	for size: Vector2i in [Vector2i(1920, 1080), Vector2i(1100, 720), Vector2i(900, 640)]:
		root.size = size
		await settle()
		var scroll := panel.get_parent() as ScrollContainer
		for label: Label in [panel._equipment, panel._active_tool]:
			check(label.text.contains(long_id), "full observed active item ID retained")
			check(label.size.x <= scroll.size.x + 1 and label.get_line_count() == label.get_visible_line_count(), "wrapped active equipment bounded in shell")
			label.grab_focus()
			await settle()
			check(scroll.get_global_rect().intersects(label.get_global_rect()), "keyboard focus reveals equipment guidance")
		await snap("active-%d" % size.x)
	request = await activate("switch_hand")
	remote.connection_closed.emit("Equipment fixture disconnect")
	shown("Active hand/item: unavailable")
	remote.command_completed.emit(request, ServiceResult.success())
	shown("Active hand/item: unavailable")
	check(panel._result.text.contains("outcome is unknown"), "late receipt after disconnect cannot confirm equipment")
	check(remote.sent.size() == sent + 1 and world.capture_world_snapshot_json().value == before, "observation/rendering/disconnect emits no extra commands and changes no canonical state")
	observed["tick_number"] = 100
	check(JSON.stringify(observed) == encoded, "rendering preserves source observation")
	client.free()
	world.free()
	PlayerInputSettings.instance().release_all()
	print("Active hand/tool actual shell: %d failures; injected GUI, real hand commands, no sockets/human acceptance" % failures)
	quit(1 if failures else 0)
